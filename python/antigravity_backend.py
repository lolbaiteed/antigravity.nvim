#!/usr/bin/env python3
import asyncio
import json
import sys
import os
import traceback


try:
    from google.antigravity import Agent, LocalAgentConfig
    SDK_AVAILABLE = True
except ImportError:
    SDK_AVAILABLE = False


def log(msg):
    sys.stderr.write(f"[AG-BACKEND] {msg}\n")
    sys.stderr.flush()


# ---------------------------------------------------------------------------
# Cross-platform stdin reader
#
# Linux:  connect_read_pipe works fine with the default SelectorEventLoop,
#         giving us a fully async StreamReader.
#
# Windows: ProactorEventLoop (default) has a broken _ProactorReadPipeTransport
#          in Python 3.12+/3.14, and SelectorEventLoop doesn't implement
#          connect_read_pipe at all. So we fall back to run_in_executor to
#          push blocking stdin reads onto a thread, keeping the event loop free.
# ---------------------------------------------------------------------------

if sys.platform == "win32":
    class _StdinReader:
        """Thread-based stdin reader for Windows (ProactorEventLoop compatible)."""

        def __init__(self):
            self._loop = None
            self._buf = sys.stdin.buffer

        def _set_loop(self, loop):
            self._loop = loop

        async def readline(self):
            return await self._loop.run_in_executor(None, self._buf.readline)

        async def readexactly(self, n):
            def _read():
                data = b""
                while len(data) < n:
                    chunk = self._buf.read(n - len(data))
                    if not chunk:
                        raise asyncio.IncompleteReadError(data, n)
                    data += chunk
                return data
            return await self._loop.run_in_executor(None, _read)

    async def make_stdin_reader():
        reader = _StdinReader()
        reader._set_loop(asyncio.get_running_loop())
        return reader

else:
    async def make_stdin_reader():
        """Async StreamReader via connect_read_pipe (Linux/macOS)."""
        loop = asyncio.get_running_loop()
        reader = asyncio.StreamReader()
        protocol = asyncio.StreamReaderProtocol(reader)
        await loop.connect_read_pipe(lambda: protocol, sys.stdin)
        return reader


class AntigravityBackend:
    def __init__(self):
        self.agents = {}  # conversation_id -> Agent instance
        self.default_agent = None

    async def initialize(self, params):
        global SDK_AVAILABLE
        log("Initializing backend...")
        if not SDK_AVAILABLE:
            log("google-antigravity SDK is not available. Attempting automatic installation...")
            try:
                proc = await asyncio.create_subprocess_exec(
                    sys.executable, "-m", "pip", "install", "google-antigravity",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE
                )
                stdout, stderr = await proc.communicate()
                if proc.returncode == 0:
                    log("google-antigravity installed successfully!")
                    try:
                        global Agent, LocalAgentConfig
                        from google.antigravity import Agent, LocalAgentConfig
                        SDK_AVAILABLE = True
                    except ImportError:
                        log("Installed but failed to import. Falling back to ECHO mode.")
                else:
                    log(f"Pip install failed with code {proc.returncode}. Stderr: {stderr.decode()}")
            except Exception as e:
                log(f"Auto-install encountered error: {e}")

        if not SDK_AVAILABLE:
            return {"status": "echo_mode", "version": "0.1.0", "info": "google-antigravity SDK missing"}

        api_key = params.get("api_key")
        if api_key:
            os.environ["GEMINI_API_KEY"] = api_key

        try:
            config = LocalAgentConfig()
            self.default_agent = Agent(config)
            await self.default_agent.__aenter__()
            self.agents["default"] = self.default_agent
            log("google-antigravity Agent initialized successfully.")
            return {"status": "ok", "version": "0.1.0"}
        except Exception as e:
            log(f"Error initializing agent: {traceback.format_exc()}")
            return {"status": "error", "error": str(e)}

    async def new_conversation(self, params):
        conv_id = params.get("conversation_id", "default")
        log(f"Resetting conversation for: {conv_id}")
        if not SDK_AVAILABLE:
            return {"status": "ok"}

        if conv_id in self.agents:
            try:
                await self.agents[conv_id].__aexit__(None, None, None)
            except Exception as e:
                log(f"Error closing agent: {e}")

        try:
            config = LocalAgentConfig()
            agent = Agent(config)
            await agent.__aenter__()
            self.agents[conv_id] = agent
            return {"status": "ok"}
        except Exception as e:
            log(f"Error creating agent: {e}")
            return {"status": "error", "error": str(e)}

    async def chat(self, params, request_id):
        message = params.get("message", "")
        context = params.get("context", {})
        conv_id = params.get("conversation_id", "default")

        full_prompt = ""
        if context.get("content"):
            full_prompt += f"--- CURRENT FILE CONTEXT ---\n"
            full_prompt += f"File: {context.get('file', 'unknown')}\n"
            full_prompt += f"Language: {context.get('filetype', 'unknown')}\n"
            full_prompt += "```" + context.get('filetype', '') + "\n"
            full_prompt += context.get("content", "") + "\n"
            full_prompt += "```\n"

        if context.get("selection"):
            full_prompt += f"--- VISUAL SELECTION CONTEXT ---\n"
            full_prompt += "```\n" + context.get("selection") + "\n```\n"

        full_prompt += f"--- USER MESSAGE ---\n{message}"

        log(f"Received chat request (id={request_id})")

        if not SDK_AVAILABLE:
            echo_response = f"Echo (No SDK): You said '{message}'\nContext: {list(context.keys())}"
            words = echo_response.split(" ")
            for i, word in enumerate(words):
                await asyncio.sleep(0.05)
                chunk = f"{word} " if i < len(words) - 1 else word
                await self.send_notification("stream_chunk", {"request_id": request_id, "text": chunk, "done": False})
            await self.send_notification("stream_chunk", {"request_id": request_id, "text": "", "done": True})
            return {"status": "ok"}

        agent = self.agents.get(conv_id)
        if not agent:
            await self.new_conversation({"conversation_id": conv_id})
            agent = self.agents.get(conv_id)

        try:
            response = await agent.chat(full_prompt)
            if hasattr(response, "chunks") or hasattr(response, "__aiter__"):
                async for chunk in response:
                    text_chunk = getattr(chunk, "text", str(chunk))
                    await self.send_notification("stream_chunk", {"request_id": request_id, "text": text_chunk, "done": False})
            else:
                text = await response.text()
                chunk_size = 50
                for i in range(0, len(text), chunk_size):
                    await asyncio.sleep(0.01)
                    await self.send_notification("stream_chunk", {"request_id": request_id, "text": text[i:i+chunk_size], "done": False})

            await self.send_notification("stream_chunk", {"request_id": request_id, "text": "", "done": True})
            return {"status": "ok"}
        except Exception as e:
            log(f"Error during chat: {traceback.format_exc()}")
            return {"status": "error", "error": str(e)}

    async def send_notification(self, method, params):
        payload = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        }
        await self.write_message(payload)

    async def write_message(self, message):
        body = json.dumps(message)
        content = f"Content-Length: {len(body)}\r\n\r\n{body}"
        sys.stdout.write(content)
        sys.stdout.flush()

    async def run(self):
        log("Backend started. Waiting for requests...")
        reader = await make_stdin_reader()

        while True:
            try:
                header_line = await reader.readline()
                if not header_line:
                    break

                header_str = header_line.decode('utf-8')
                if not header_str.startswith("Content-Length:"):
                    continue

                length = int(header_str.split(":")[1].strip())

                await reader.readline()  # blank line

                body_bytes = await reader.readexactly(length)
                body = body_bytes.decode('utf-8')
                request = json.loads(body)

                method = request.get("method")
                params = request.get("params", {})
                if not isinstance(params, dict):
                    params = {}
                req_id = request.get("id")

                if method == "initialize":
                    res = await self.initialize(params)
                    await self.write_message({"jsonrpc": "2.0", "id": req_id, "result": res})
                elif method == "chat":
                    asyncio.create_task(self.handle_chat_task(params, req_id))
                elif method == "new_conversation":
                    res = await self.new_conversation(params)
                    await self.write_message({"jsonrpc": "2.0", "id": req_id, "result": res})
                elif method == "shutdown":
                    log("Shutting down backend...")
                    for agent in list(self.agents.values()):
                        try:
                            await agent.__aexit__(None, None, None)
                        except:
                            pass
                    await self.write_message({"jsonrpc": "2.0", "id": req_id, "result": {"status": "ok"}})
                    break
            except asyncio.IncompleteReadError:
                break
            except Exception as e:
                log(f"Error in main loop: {traceback.format_exc()}")

    async def handle_chat_task(self, params, req_id):
        res = await self.chat(params, req_id)
        await self.write_message({"jsonrpc": "2.0", "id": req_id, "result": res})


if __name__ == "__main__":
    asyncio.run(AntigravityBackend().run())
