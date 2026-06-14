local M = {}

M.defaults = {
  window = {
    position = "right",
    width = "35%",
    input_height = 4,
  },
  backend = {
    python_cmd = "python3",
    script_path = nil,
  },
  keymaps = {
    toggle = "<leader>ac",
    send = "<CR>",
    close = "q",
    new_chat = "<leader>an",
    scroll_up = "<C-u>",
    scroll_down = "<C-d>",
  },
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
