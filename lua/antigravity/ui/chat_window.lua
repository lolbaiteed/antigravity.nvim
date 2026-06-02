local config = require("antigravity.config")
local utils = require("antigravity.utils")
local chat = require("antigravity.chat")
local renderer = require("antigravity.ui.renderer")
local input_module = require("antigravity.ui.input")

local M = {}

local sidebar_split = nil
local chat_popup = nil
local input_popup = nil
local original_winid = nil

function M.is_open()
  return sidebar_split ~= nil and sidebar_split.winid ~= nil and vim.api.nvim_win_is_valid(sidebar_split.winid)
end

function M.open()
  if M.is_open() then
    vim.api.nvim_set_current_win(input_popup.winid)
    return
  end

  local has_nui, nui_split = pcall(require, "nui.split")
  local _, nui_popup = pcall(require, "nui.popup")
  local _, nui_layout = pcall(require, "nui.layout")

  if not has_nui then
    utils.log("error", "nui.nvim is required for this plugin. Please install it.")
    return
  end

  original_winid = vim.api.nvim_get_current_win()

  -- Main Split container
  sidebar_split = nui_split({
    position = config.options.window.position,
    size = config.options.window.width,
    enter = false,
  })

  sidebar_split:mount()

  -- Split win config options
  vim.wo[sidebar_split.winid].winfixwidth = true

  -- Chat buffer popup
  chat_popup = nui_popup({
    enter = false,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " Antigravity ",
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      filetype = "markdown",
    },
    win_options = {
      wrap = true,
      linebreak = true,
      conceallevel = 2,
      concealcursor = "n",
    },
  })

  -- Input buffer popup
  input_popup = nui_popup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " Message ",
        top_align = "left",
      },
    },
  })

  -- Construct Layout inside the split window
  local layout = nui_layout(
    sidebar_split.winid,
    nui_layout.Box({
      nui_layout.Box(chat_popup, { grow = 1 }),
      nui_layout.Box(input_popup, { size = config.options.window.input_height }),
    }, { dir = "col" })
  )

  layout:update()

  -- Render existing chat history
  renderer.render_messages(chat_popup.bufnr, chat.get_messages())

  -- Configure input submit
  input_module.setup_input(input_popup, function(text)
    local context = nil
    -- If original window is valid, grab context from it
    if original_winid and vim.api.nvim_win_is_valid(original_winid) then
      local current_win = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(original_winid)
      context = utils.get_buffer_context()
      vim.api.nvim_set_current_win(current_win)
    else
      context = utils.get_buffer_context()
    end
    
    renderer.start_assistant_message(chat_popup.bufnr)
    chat.send_message(text, context)
  end)

  -- Chat display local keymaps
  local map_opts = { buffer = chat_popup.bufnr, noremap = true, silent = true }
  
  -- Close mapping
  vim.keymap.set("n", config.options.keymaps.close, function()
    M.close()
  end, map_opts)

  -- New chat mapping
  vim.keymap.set("n", config.options.keymaps.new_chat, function()
    chat.new_conversation()
  end, map_opts)

  -- Autoscroll callback registrations
  local function scroll_to_bottom()
    if not M.is_open() then return end
    local line_count = vim.api.nvim_buf_line_count(chat_popup.bufnr)
    pcall(vim.api.nvim_win_set_cursor, chat_popup.winid, { line_count, 0 })
  end

  chat.on_message(function(msg)
    if not M.is_open() then return end
    if not msg then
      -- Conversation reset
      renderer.render_messages(chat_popup.bufnr, {})
    else
      if msg.role ~= "assistant" then
        renderer.render_messages(chat_popup.bufnr, chat.get_messages())
      else
        -- Completed assistant message
        renderer.render_messages(chat_popup.bufnr, chat.get_messages())
      end
    end
    scroll_to_bottom()
  end)

  chat.on_stream_chunk(function(chunk)
    if not M.is_open() then return end
    if chunk.done then
      renderer.finish_assistant_message(chat_popup.bufnr)
    else
      renderer.append_stream_chunk(chat_popup.bufnr, chunk.text)
    end
    scroll_to_bottom()
  end)

  chat.on_thinking(function(is_thinking)
    if not M.is_open() then return end
    renderer.show_thinking(chat_popup.bufnr, is_thinking)
    scroll_to_bottom()
  end)
end

function M.close()
  if not M.is_open() then return end

  renderer.show_thinking(chat_popup.bufnr, false)

  if chat_popup then
    chat_popup:unmount()
    chat_popup = nil
  end

  if input_popup then
    input_popup:unmount()
    input_popup = nil
  end

  if sidebar_split then
    sidebar_split:unmount()
    sidebar_split = nil
  end

  if original_winid and vim.api.nvim_win_is_valid(original_winid) then
    vim.api.nvim_set_current_win(original_winid)
  end
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

function M.get_chat_bufnr()
  return chat_popup and chat_popup.bufnr
end

function M.get_input_bufnr()
  return input_popup and input_popup.bufnr
end

return M
