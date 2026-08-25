-- jvmlens.nvim, loaded from its local repo (dir = local dev checkout, not
-- a git URL) so edits there take effect immediately without reinstalling.
-- See ~/Projects/personal_projects/jvmlens.nvim/doc/ARCHITECTURE.md.

return {
  {
    "jvmlens.nvim",
    dir = vim.fn.expand("~/Projects/personal_projects/jvmlens.nvim"),
    name = "jvmlens.nvim",
    config = function()
      require("jvmlens").setup({})
    end,
  },
}
