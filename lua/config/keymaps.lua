-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Grep scoped to src/main/ grouped by file (excludes tests/resources)
vim.keymap.set("n", "<leader>fm", function()
  require("grug-far").open({ prefills = { paths = vim.fn.getcwd() .. "/src/main" } })
end, { desc = "Grep src/main/ (grug-far)" })
