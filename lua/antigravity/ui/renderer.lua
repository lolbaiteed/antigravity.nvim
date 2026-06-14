local config = require("antigravity.config")
local utils = require("antigravity.utils")

local M = {}

local thinking_timer = nil
local thinking_ns = vim.api.nvim_create_namespace("antigravity_thinking")
local extmark_ns = vim.api.nvim_create_namespace("antigravity_extmarks")
local stream_buffer = ""
local current_stream_line = -1

function M.render_messages(bufnr, messages)
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
  local headings = {}
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
    local content_lines = vim.split(msg.content, "\n")
    for _, l in ipairs(content_lines) do
      table.insert(lines, l)
    end
    table.insert(lines, "")
    table.insert(lines, "---")
    table.insert(lines, "")
  end
  if #lines > 1 then
    table.remove(lines)
    table.remove(lines)
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  for _, h in ipairs(headings) do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, extmark_ns, h.line, 0, {
      end_col = h.icon_len,
      hl_group = h.hl,
    })
  end
  vim.bo[bufnr].modifiable = false
  stream_buffer = ""
  current_stream_line = -1
end

function M.start_assistant_message(bufnr)
  vim.bo[bufnr].modifiable = true


  local icon = config.options.icons.assistant
  local header_text = string.format("%s Antigravity (%s)", icon, utils.format_timestamp(os.time()))
  local line_count = vim.api.nvim_buf_line_count(bufnr)


  if line_count > 1 then
    vim.api.nvim_buf_set_lines(bufnr, line_count, -1, false, { "", "---", "", header_text, "" })
  else
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { header_text, "" })
  end


  local new_line_count = vim.api.nvim_buf_line_count(bufnr)
  pcall(vim.api.nvim_buf_set_extmark, bufnr, extmark_ns, new_line_count - 2, 0, {
    end_col = #icon,
    hl_group = "AntigravityAssistant",
  })

  stream_buffer = ""
  current_stream_line = new_line_count - 1
  utils.log("info", "[DEBUG] start_assistant_message: current_stream_line=" .. tostring(current_stream_line))
  vim.bo[bufnr].modifiable = false
end

function M.append_stream_chunk(bufnr, text)
  vim.bo[bufnr].modifiable = true
  stream_buffer = stream_buffer .. text
  utils.log("info", "[DEBUG] append_stream_chunk: accumulated=" .. tostring(#stream_buffer) .. " chars")

  local new_lines = vim.split(stream_buffer, "\n")

  if current_stream_line >= 0 then
    utils.log("info",
      "[DEBUG] append_stream_chunk: writing to line " ..
      tostring(current_stream_line) .. " with " .. tostring(#new_lines) .. " lines")
    vim.api.nvim_buf_set_lines(bufnr, current_stream_line, -1, false, new_lines)
  else
    utils.log("warn", "[DEBUG] append_stream_chunk: current_stream_line is -1, skipping update")
  end
  vim.bo[bufnr].modifiable = false
end

function M.finish_assistant_message(bufnr)
  local chat = require("antigravity.chat")
  utils.log("info", "[DEBUG] finish_assistant_message: adding message with " .. tostring(#stream_buffer) .. " chars")
  chat.add_assistant_message(stream_buffer)
  stream_buffer = ""
  current_stream_line = -1 -- Reset for next message
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
