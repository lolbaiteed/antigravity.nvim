local M = {}

function M.log(level, msg)
  local lvl = vim.log.levels[level:upper()] or vim.log.levels.INFO
  vim.notify("[Antigravity] " .. tostring(msg), lvl)
end

function M.get_plugin_dir()
  local info = debug.getinfo(1, "S")
  local path = info.source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(path)))
end

function M.tbl_deep_merge(base, override)
  return vim.tbl_deep_extend("force", {}, base, override or {})
end

function M.format_timestamp(ts)
  return os.date("%I:%M %p", ts or os.time())
end

function M.get_visual_selection()
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  if start_line == 0 or end_line == 0 then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  return table.concat(lines, "\n")
end

function M.get_buffer_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo[bufnr].filetype
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return {
    file = vim.fs.basename(path) or "buffer",
    filetype = filetype,
    content = table.concat(lines, "\n")
  }
end

return M
