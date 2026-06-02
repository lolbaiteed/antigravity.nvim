#!/usr/bin/env python3
import asyncio
import json
import sys
import os
import traceback

# Try to import google-antigravity. If missing, we'll run in mock/echo mode for safety and development.
try:
    from google.antigravity import Agent, LocalAgentConfig
    SDK_AVAILABLE = True
except ImportError:
    SDK_AVAILABLE = False

# Logger writing to stderr (Neovim captures stderr of jobs)
def log(msg):
    sys.stderr.write(f"[AG-BACKEND] {msg}\n")
    sys.stderr.flush()

class AntigravityBackend:
    def __init__(self):
        self.agents = {}  # conversation_id -> Agent instance
        self.default_agent = None

    async def initialize(self, params):
        log("Initializing backend...")
        if not SDK_AVAILABLE:
            log("google-antigravity SDK is not available. Running in ECHO mode.")
            return {"status": "echo_mode", "version": "0.1.0", "info": "google-antigravity SDK missing"}
        
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
        
        # Prepend context to the message in a structured way
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
            # Echo mode simulation
            echo_response = f"Echo (No SDK): You said '{message}'\nContext: {list(context.keys())}"
            # Stream chunk by chunk
            words = echo_response.split(" ")
            for i, word in enumerate(words):
                await asyncio.sleep(0.05)
                # Send stream notification
                chunk = f"{word} " if i < len(words) - 1 else word
                await self.send_notification("stream_chunk", {"request_id": request_id, "text": chunk, "done": False})
            await self.send_notification("stream_chunk", {"request_id": request_id, "text": "", "done": True})
            return {"status": "ok"}

        agent = self.agents.get(conv_id)
        if not agent:
            # Initialize on demand
            await self.new_conversation({"conversation_id": conv_id})
            agent = self.agents.get(conv_id)

        try:
            # Send message and handle potential streaming
            response = await agent.chat(full_prompt)
            # If the response supports streaming, stream it. Let's look for standard text streaming or direct text.
            # In google-antigravity SDK, a response has `.text()` or supports streaming chunks.
            # Let's write robust code to stream if possible, or fall back to full resolution.
            if hasattr(response, "chunks") or hasattr(response, "__aiter__"):
                async for chunk in response:
                    text_chunk = getattr(chunk, "text", str(chunk))
                    await self.send_notification("stream_chunk", {"request_id": request_id, "text": text_chunk, "done": False})
            else:
                # Fallback: get entire text and send as one or a few chunks
                text = await response.text()
                # Split in small chunks to simulate streaming for nicer UX even if SDK resolved synchronously
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
        reader = asyncio.StreamReader()
        protocol = asyncio.StreamReaderProtocol(reader)
        await asyncio.get_event_loop().connect_read_pipe(lambda: protocol, sys.stdin)

        while True:
            try:
                header_line = await reader.readline()
                if not header_line:
                    break
                
                header_str = header_line.decode('utf-8')
                if not header_str.startswith("Content-Length:"):
                    continue
                
                length = int(header_str.split(":")[1].strip())
                # Read the remaining headers and the blank line \r\n\r\n
                blank_line = await reader.readline()
                
                # Now read the body
                body_bytes = await reader.readexactly(length)
                body = body_bytes.decode('utf-8')
                request = json.loads(body)
                
                # Dispatch
                method = request.get("method")
                params = request.get("params", {})
                if not isinstance(params, dict):
                    params = {}
                req_id = request.get("id")
                
                if method == "initialize":
                    res = await self.initialize(params)
                    await self.write_message({"jsonrpc": "2.0", "id": req_id, "result": res})
                elif method == "chat":
                    # Run chat in background so we don't block main loop (allows concurrently receiving cancels/other commands)
                    asyncio.create_task(self.handle_chat_task(params, req_id))
                elif method == "new_conversation":
                    res = await self.new_conversation(params)
                    await self.write_message({"jsonrpc": "2.0", "id": req_id, "result": res})
                elif method == "shutdown":
                    log("Shutting down backend...")
                    # Cleanup
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
