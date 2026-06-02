local config = require("antigravity.config")
local utils = require("antigravity.utils")

local M = {}

local placeholder_ns = vim.api.nvim_create_namespace("antigravity_placeholder")

function M.setup_input(popup, on_submit)
  local bufnr = popup.bufnr
  local winid = popup.winid
  utils.log("info", "[DEBUG] setup_input bufnr=" .. tostring(bufnr) .. " winid=" .. tostring(winid))
  
  -- Set buffer as modifiable for input
  vim.bo[bufnr].modifiable = true
  
  -- Render placeholder initially
  M.show_placeholder(bufnr)
  
  -- Setup autocmds for placeholder show/hide
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = bufnr,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      if #lines == 1 and lines[1] == "" then
        M.show_placeholder(bufnr)
      else
        M.clear_placeholder(bufnr)
      end
      
      -- Auto-resize
      local line_count = #lines
      local height = math.min(math.max(line_count, config.options.window.input_height), 10)
      if popup.layout then
        -- If part of nui.layout, we could adjust, but keeping it simpler:
        -- Let's just adjust the window height if needed.
        local current_height = vim.api.nvim_win_get_height(winid)
        if current_height ~= height then
          pcall(vim.api.nvim_win_set_height, winid, height)
        end
      end
    end
  })

  -- Keybindings
  local map_opts = { buffer = bufnr, noremap = true, silent = true }
  
  -- Submit keymaps
  local function submit_msg()
    utils.log("info", "[DEBUG] submit_msg triggered!")
    utils.log("info", "[DEBUG] Current buffer: " .. tostring(vim.api.nvim_get_current_buf()))
    utils.log("info", "[DEBUG] Input buffer: " .. tostring(bufnr))
    local text = M.get_text(bufnr)
    if text ~= "" then
      on_submit(text)
      M.clear(bufnr)
    end
  end

  -- Enter to submit
  vim.keymap.set({ "n", "i" }, config.options.keymaps.send, submit_msg, map_opts)
  
  -- Fallback submit keymaps (in case <CR> is hijacked by autopairs/cmp/etc.)
  vim.keymap.set({ "n", "i" }, "<C-g>", submit_msg, map_opts)
  vim.keymap.set({ "n", "i" }, "<C-s>", submit_msg, map_opts)

  -- Shift-Enter to insert newline
  vim.keymap.set("i", "<S-CR>", "<CR>", map_opts)
end

function M.show_placeholder(bufnr)
  M.clear_placeholder(bufnr)
  vim.api.nvim_buf_set_extmark(bufnr, placeholder_ns, 0, 0, {
    virt_text = { { "Type a message...", "Comment" } },
    virt_text_pos = "overlay",
    hl_mode = "combine",
  })
end

function M.clear_placeholder(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, placeholder_ns, 0, -1)
end

function M.get_text(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  -- Strip whitespace lines
  return table.concat(lines, "\n"):gsub("^%s*(.-)%s*$", "%1")
end

function M.clear(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
  M.show_placeholder(bufnr)
end

return M
