local config = require("antigravity.config")
local utils = require("antigravity.utils")

local M = {}

local thinking_timer = nil
local thinking_ns = vim.api.nvim_create_namespace("antigravity_thinking")
local extmark_ns = vim.api.nvim_create_namespace("antigravity_extmarks")
local stream_buffer = ""

function M.render_messages(bufnr, messages)
  -- Cancel active thinking spinner
  M.show_thinking(bufnr, false)
  
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_clear_namespace(bufnr, extmark_ns, 0, -1)
  
  if not messages or #messages == 0 then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "# Antigravity Chat",
      "",
      "Ask a question to begin a session.",
    })
    vim.bo[bufnr].modifiable = false
    return
  end
  
  local lines = {}
  local headings = {} -- Store locations to put icons/highlights
  
  for _, msg in ipairs(messages) do
    local icon = ""
    local title = ""
    local hl_group = "AntigravitySystem"
    
    if msg.role == "user" then
      icon = config.options.icons.user
      title = "You"
      hl_group = "AntigravityUser"
    elseif msg.role == "assistant" then
      icon = config.options.icons.assistant
      title = "Antigravity"
      hl_group = "AntigravityAssistant"
    else
      icon = config.options.icons.system
      title = "System"
      hl_group = "AntigravitySystem"
    end
    
    local header_text = string.format("%s %s (%s)", icon, title, utils.format_timestamp(msg.timestamp))
    table.insert(lines, header_text)
    table.insert(headings, { line = #lines - 1, hl = hl_group, icon_len = #icon })
    table.insert(lines, "")
    
    -- Content
    local content_lines = vim.split(msg.content, "\n")
    for _, l in ipairs(content_lines) do
      table.insert(lines, l)
    end
    
    table.insert(lines, "")
    table.insert(lines, "---")
    table.insert(lines, "")
  end
  
  -- Remove final separator
  if #lines > 1 then
    table.remove(lines)
    table.remove(lines)
  end
  
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  
  -- Apply highlights/extmarks to headers
  for _, h in ipairs(headings) do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, extmark_ns, h.line, 0, {
      end_col = h.icon_len,
      hl_group = h.hl,
    })
  end
  
  vim.bo[bufnr].modifiable = false
  stream_buffer = ""
end

function M.start_assistant_message(bufnr)
  vim.bo[bufnr].modifiable = true
  
  -- Add header
  local icon = config.options.icons.assistant
  local header_text = string.format("%s Antigravity (%s)", icon, utils.format_timestamp(os.time()))
  
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  
  -- Append separator if not empty
  if line_count > 1 then
    vim.api.nvim_buf_set_lines(bufnr, line_count, -1, false, { "", "---", "", header_text, "" })
  else
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { header_text, "" })
  end
  
  -- Apply highlight to new assistant header
  local new_line_count = vim.api.nvim_buf_line_count(bufnr)
  pcall(vim.api.nvim_buf_set_extmark, bufnr, extmark_ns, new_line_count - 2, 0, {
    end_col = #icon,
    hl_group = "AntigravityAssistant",
  })
  
  stream_buffer = ""
  vim.bo[bufnr].modifiable = false
end

function M.append_stream_chunk(bufnr, text)
  vim.bo[bufnr].modifiable = true
  stream_buffer = stream_buffer .. text
  
  -- Update last lines
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local new_lines = vim.split(stream_buffer, "\n")
  
  -- Determine where the assistant content starts
  -- We appended the header at `new_line_count - 2`, and content starts at `new_line_count - 1`
  -- Let's replace from the content start line onwards
  -- Actually, let's keep it simple: find the header, replace lines below it.
  -- Our assistant content starts at the last line currently.
  local content_start = line_count - 1
  -- If we've already written content, we replace it.
  -- Let's trace content start:
  local target_start = math.max(0, content_start)
  
  vim.api.nvim_buf_set_lines(bufnr, target_start, -1, false, new_lines)
  
  vim.bo[bufnr].modifiable = false
end

function M.finish_assistant_message(bufnr)
  -- Add to chat history in core module
  local chat = require("antigravity.chat")
  chat.add_assistant_message(stream_buffer)
  stream_buffer = ""
end

function M.show_thinking(bufnr, is_thinking)
  if thinking_timer then
    thinking_timer:stop()
    thinking_timer:close()
    thinking_timer = nil
  end
  
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, thinking_ns, 0, -1)
  
  if not is_thinking then return end
  
  local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local idx = 1
  
  thinking_timer = vim.loop.new_timer()
  thinking_timer:start(0, 100, vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      M.show_thinking(bufnr, false)
      return
    end
    
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, thinking_ns, 0, -1)
    
    pcall(vim.api.nvim_buf_set_extmark, bufnr, thinking_ns, line_count - 1, 0, {
      virt_text = { { " " .. frames[idx] .. " Thinking...", "AntigravityThinking" } },
      virt_text_pos = "overlay",
    })
    
    idx = (idx % #frames) + 1
  end))
end

return M
