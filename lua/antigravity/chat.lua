local backend = require("antigravity.backend")
local utils = require("antigravity.utils")

local M = {}

local messages = {}
local is_streaming = false

local on_message_callbacks = {}
local on_stream_chunk_callbacks = {}
local on_thinking_callbacks = {}

local current_request_id = nil

backend.on_notification("stream_chunk", function(params)
  local text = params.text
  local done = params.done

  for _, cb in ipairs(on_stream_chunk_callbacks) do
    cb({ text = text, done = done })
  end

  if done then
    is_streaming = false
    for _, cb in ipairs(on_thinking_callbacks) do
      cb(false)
    end
  end
end)

function M.get_messages()
  return messages
end

function M.new_conversation()
  messages = {}
  is_streaming = false
  backend.request("new_conversation", {}, function(err, result)
    if err then
      utils.log("error", "Failed to clear conversation: " .. tostring(err))
    else
      utils.log("info", "Started new conversation.")
    end
  end)

  for _, cb in ipairs(on_message_callbacks) do
    cb(nil)
  end
end

function M.send_message(text, context)
  if text == "" then return end

  local user_msg = {
    role = "user",
    content = text,
    timestamp = os.time()
  }
  table.insert(messages, user_msg)

  for _, cb in ipairs(on_message_callbacks) do
    cb(user_msg)
  end

  for _, cb in ipairs(on_thinking_callbacks) do
    cb(true)
  end

  is_streaming = true

  backend.request("chat", { message = text, context = context }, function(err, result)
    if err then
      is_streaming = false
      for _, cb in ipairs(on_thinking_callbacks) do
        cb(false)
      end
      utils.log("error", "Chat request error: " .. tostring(err))

      local error_msg = {
        role = "system",
        content = "Error: " .. tostring(err),
        timestamp = os.time()
      }
      table.insert(messages, error_msg)
      for _, cb in ipairs(on_message_callbacks) do
        cb(error_msg)
      end
    else
    end
  end)
end

function M.add_assistant_message(text)
  local asst_msg = {
    role = "assistant",
    content = text,
    timestamp = os.time()
  }
  table.insert(messages, asst_msg)
  return asst_msg
end

function M.on_message(callback)
  table.insert(on_message_callbacks, callback)
end

function M.on_stream_chunk(callback)
  table.insert(on_stream_chunk_callbacks, callback)
end

function M.on_thinking(callback)
  table.insert(on_thinking_callbacks, callback)
end

function M.is_streaming()
  return is_streaming
end

return M
