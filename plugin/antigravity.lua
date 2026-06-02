if vim.g.loaded_antigravity then
  return
end
vim.g.loaded_antigravity = 1

-- Register user commands
vim.api.nvim_create_user_command("AntigravityToggle", function()
  require("antigravity").toggle()
end, { desc = "Toggle Antigravity Chat Panel" })

vim.api.nvim_create_user_command("AntigravityOpen", function()
  require("antigravity").open()
end, { desc = "Open Antigravity Chat Panel" })

vim.api.nvim_create_user_command("AntigravityClose", function()
  require("antigravity").close()
end, { desc = "Close Antigravity Chat Panel" })

vim.api.nvim_create_user_command("AntigravityAsk", function(opts)
  require("antigravity").ask(opts.args)
end, { nargs = "?", desc = "Ask Antigravity a question" })

vim.api.nvim_create_user_command("AntigravityNew", function()
  require("antigravity").new_conversation()
end, { desc = "Start new Antigravity conversation" })

vim.api.nvim_create_user_command("AntigravitySendSelection", function()
  require("antigravity").send_selection()
end, { range = true, desc = "Send selection to Antigravity" })
