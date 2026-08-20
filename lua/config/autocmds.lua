-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Re-root neo-tree to the new cwd whenever project.nvim (or anything else) changes it,
-- but only if the neo-tree sidebar is already open (avoids popping it open unprompted).
vim.api.nvim_create_autocmd("DirChanged", {
  group = vim.api.nvim_create_augroup("neotree_follow_cwd", { clear = true }),
  callback = function()
    local neotree_open = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "neo-tree" then
        neotree_open = true
        break
      end
    end

    if neotree_open then
      require("neo-tree.command").execute({
        action = "focus",
        source = "filesystem",
        dir = vim.loop.cwd(),
      })
    end
  end,
})
