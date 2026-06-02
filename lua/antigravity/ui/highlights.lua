local M = {}

function M.setup()
  local highlights = {
    AntigravityUser = { link = "@markup.heading.1" },
    AntigravityAssistant = { link = "@markup.heading.2" },
    AntigravitySystem = { link = "Comment" },
    AntigravityBorder = { link = "FloatBorder" },
    AntigravityTitle = { link = "Title" },
    AntigravityInput = { link = "Normal" },
    AntigravityInputBorder = { fg = "#7aa2f7" },  -- Default aesthetic blue border, matches FloatBorder fallback
    AntigravityThinking = { link = "DiagnosticInfo" },
    AntigravitySeparator = { link = "WinSeparator" },
    AntigravityTimestamp = { link = "Comment" },
  }

  for name, val in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, val)
  end
end

return M
