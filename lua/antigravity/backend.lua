local utils = require("antigravity.utils")
local config = require("antigravity.config")

local M = {}

local job_id = nil
local request_id = 0
local callbacks = {}
local notification_handlers = {}
local read_buffer = ""

local function parse_messages()
  while true do
    -- Find content length header
    local cl_start, cl_end = read_buffer:find("Content%-Length: %d+\r?\n\r?\n")
    if not cl_start then
      break
    end
    
    local length_str = read_buffer:match("Content%-Length: (%d+)", cl_start)
    local length = tonumber(length_str)
    
    -- Check if we have the full body yet
    local body_start = cl_end + 1
    local body_end = body_start + length - 1
    if #read_buffer < body_end then
      break
    end
    
    local body = read_buffer:sub(body_start, body_end)
    -- Remove parsed message from read_buffer
    read_buffer = read_buffer:sub(body_end + 1)
    
    local ok, msg = pcall(vim.json.decode, body)
    if ok and msg then
      if msg.id then
        -- Response
        local cb = callbacks[msg.id]
        if cb then
          callbacks[msg.id] = nil
          vim.schedule(function()
            if msg.error then
              cb(msg.error, nil)
            else
              cb(nil, msg.result)
            end
          end)
        end
      elseif msg.method then
        -- Notification
        local handler = notification_handlers[msg.method]
        if handler then
          vim.schedule(function()
            handler(msg.params)
          end)
        end
      end
    else
      utils.log("error", "Failed to decode JSON message: " .. tostring(msg))
    end
  end
end

function M.start()
  if job_id then return end

  local script_path = config.options.backend.script_path
  if not script_path then
    script_path = utils.get_plugin_dir() .. "/python/antigravity_backend.py"
  end

  local cmd = { config.options.backend.python_cmd, script_path }
  
  read_buffer = ""
  
  job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      if not data then return end
      local chunk = table.concat(data, "\n")
      read_buffer = read_buffer .. chunk
      parse_messages()
    end,
    on_stderr = function(_, data, _)
      if not data then return end
      local err = table.concat(data, "\n"):gsub("^%s*(.-)%s*$", "%1")
      if err ~= "" then
        utils.log("debug", "[Stderr] " .. err)
      end
    end,
    on_exit = function(_, exit_code, _)
      utils.log("info", "Backend process exited with code " .. tostring(exit_code))
      job_id = nil
      callbacks = {}
    end,
    stdout_buffered = false,
  })

  if job_id <= 0 then
    utils.log("error", "Failed to start backend process. Job ID: " .. tostring(job_id))
    job_id = nil
    return false
  end

  -- Call initialize
  M.request("initialize", {}, function(err, result)
    if err then
      utils.log("error", "Initialization failed: " .. tostring(err))
    else
      utils.log("info", "Backend connected successfully. Status: " .. tostring(result.status))
    end
  end)

  return true
end

function M.stop()
  if job_id then
    vim.fn.jobstop(job_id)
    job_id = nil
  end
end

function M.is_running()
  return job_id ~= nil
end

function M.request(method, params, callback)
  if not M.is_running() then
    if not M.start() then
      if callback then callback("Backend not running and failed to start", nil) end
      return
    end
  end

  request_id = request_id + 1
  if callback then
    callbacks[request_id] = callback
  end

  local payload = {
    jsonrpc = "2.0",
    id = request_id,
    method = method,
    params = params
  }

  local body = vim.json.encode(payload)
  local msg = string.format("Content-Length: %d\r\n\r\n%s", #body, body)
  
  vim.fn.chansend(job_id, msg)
end

function M.on_notification(method, handler)
  notification_handlers[method] = handler
end

function M.notify(method, params)
  if not M.is_running() then return end
  local payload = {
    jsonrpc = "2.0",
    method = method,
    params = params
  }
  local body = vim.json.encode(payload)
  local msg = string.format("Content-Length: %d\r\n\r\n%s", #body, body)
  vim.fn.chansend(job_id, msg)
end

return M
