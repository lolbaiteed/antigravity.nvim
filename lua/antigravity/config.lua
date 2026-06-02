local M = {}

M.defaults = {
  -- Window configuration
  window = {
    position = "right",     -- "right", "left"
    width = "35%",           -- Sidebar width
    input_height = 4,        -- input box height in lines
  },
  -- Backend configuration
  backend = {
    python_cmd = "python3",
    script_path = nil,       -- Autodetected in backend.lua
  },
  -- Keymaps (buffer-local in chat / input windows)
  keymaps = {
    toggle = "<leader>ac",
    send = "<CR>",           -- Submit message in input popup normal/insert mode depending on context
    close = "q",             -- Close in chat display popup
    new_chat = "<leader>an",
    scroll_up = "<C-u>",
    scroll_down = "<C-d>",
  },
  -- Appearance
  icons = {
    user = "●",
    assistant = "◆",
    system = "▶",
    thinking = "⟳",
  },
}

M.options = {}

function M.setup(opts)
  local utils = require("antigravity.utils")
  M.options = utils.tbl_deep_merge(M.defaults, opts)
  return M.options
end

return M
