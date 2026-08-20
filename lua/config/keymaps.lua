-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Exit terminal mode with Esc
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { noremap = true })

-- Grep scoped to src/main/ grouped by file (excludes tests/resources)
vim.keymap.set("n", "<leader>fm", function()
  require("grug-far").open({ prefills = { paths = vim.fn.getcwd() .. "/src/main" } })
end, { desc = "Grep src/main/ (grug-far)" })

-- Insert a new line below without breaking the current line (like Ctrl+Enter in VS Code)
vim.keymap.set("i", "<C-CR>", "<C-o>o", { desc = "New line below, cursor stays put" })
vim.keymap.set("i", "<C-j>", "<C-o>o", { desc = "New line below, cursor stays put (fallback if C-CR doesn't reach the terminal)" })
