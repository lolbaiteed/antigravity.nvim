# antigravity.nvim

A modern VS Code-style sidebar AI chat panel for Neovim, integrated directly with Google's Antigravity AI coding assistant SDK (`google-antigravity`).

## Warining
The project is still in alpha, so if you found a bug, want to add some features, or know how to do it better, push a PR or open an issue :)

## Features
- **Sidebar Layout:** A dedicated split panel for chats and input, powered by `nui.nvim`.
- **Streaming Responses:** Real-time token rendering with a custom CSS/UI thinking spinner.
- **Context Awareness:** Automatically captures file context (file type, buffer content, visual selections).
- **Clean Aesthetics:** Syntax highlighting inside chat messages (rendered as Markdown using Treesitter).

## Requirements
- Neovim >= 0.10.0
- [`nui.nvim`](https://github.com/MunifTanjim/nui.nvim)
- Python 3.10+ with the `google-antigravity` package installed:
  ```bash
  pip install google-antigravity
  ```
- Authenticated Antigravity CLI (runs `agy auth login` to authorize Google Cloud access).

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)
```lua
{
  "lolbaiteed/antigravity.nvim", -- Or local path directory
  dependencies = {
    "MunifTanjim/nui.nvim",
    "nvim-treesitter/nvim-treesitter", -- For syntax highlighting inside chat
  },
  config = function()
    require("antigravity").setup({
      keymaps = {
        toggle = "<leader>ac",
      }
    })
  end
}
```

## Usage

| Command | Action | Keybinding |
| --- | --- | --- |
| `:AntigravityToggle` | Toggle the sidebar panel | `<leader>ac` |
| `:AntigravityNew` | Start a new clean conversation session | — |
| `:AntigravitySendSelection` | Send visual selection along with context | — |
| `:AntigravityAsk <query>` | Quickly prompt Antigravity with a query | — |

Within the input area:
- `<CR>` submits the message.
- `<S-CR>` inserts a new line.

Within the chat window:
- `q` closes the sidebar.
