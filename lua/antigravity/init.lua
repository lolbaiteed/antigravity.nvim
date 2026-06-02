local config = require("antigravity.config")
local backend = require("antigravity.backend")
local chat = require("antigravity.chat")
local utils = require("antigravity.utils")

local M = {}

function M.setup(opts)
  -- Initialize configurations
  config.setup(opts)
  
  -- Setup highlight groups
  require("antigravity.ui.highlights").setup()
  
  -- Lazy start the backend if requested (default to lazy, startup on demand)
  -- If you want it started eagerly, you can call backend.start()
  
  -- Register global toggle keymap if configured
  if config.options.keymaps.toggle then
    vim.keymap.set("n", config.options.keymaps.toggle, function()
      M.toggle()
    end, { desc = "Toggle Antigravity Chat Panel" })
  end
end

function M.open()
  backend.start()
  require("antigravity.ui.chat_window").open()
end

function M.close()
  require("antigravity.ui.chat_window").close()
end

function M.toggle()
  backend.start()
  require("antigravity.ui.chat_window").toggle()
end

function M.new_conversation()
  chat.new_conversation()
end

function M.ask(text)
  M.open()
  if text and text ~= "" then
    -- Let's give the UI window a tiny moment to construct if it just opened
    vim.defer_fn(function()
      local context = utils.get_buffer_context()
      local chat_window = require("antigravity.ui.chat_window")
      -- Start assistant block render
      local bufnr = chat_window.get_chat_bufnr and chat_window.get_chat_bufnr()
      if bufnr then
        require("antigravity.ui.renderer").start_assistant_message(bufnr)
      end
      chat.send_message(text, context)
    end, 100)
  end
end

function M.send_selection()
  local text = utils.get_visual_selection()
  if not text then
    utils.log("warn", "No visual selection found.")
    return
  end
  
  M.open()
  vim.defer_fn(function()
    local context = utils.get_buffer_context()
    context.selection = text
    
    -- Ask user for the prompt to go with the selection
    vim.ui.input({ prompt = "Ask with selection: " }, function(input)
      if not input or input == "" then return end
      chat.send_message(input, context)
    end)
  end, 100)
end

return M
