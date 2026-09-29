-- ghosttype.nvim, loaded from its local repo (dir = local dev checkout, not
-- a git URL) so edits there take effect immediately without reinstalling.
-- MVP: typing engine + multi-step navigation + side panel, exercised via
-- :GhosttypeDemo (hardcoded 2-step lesson).

return {
  {
    "ghosttype.nvim",
    dir = vim.fn.expand("~/Projects/personal_projects/ghosttype.nvim"),
    name = "ghosttype.nvim",
    cmd = { "GhosttypeDemo", "GhosttypeNext", "GhosttypeSave", "GhosttypeDelete", "GhosttypeReset", "Lesson" },
    config = function()
      require("ghosttype").setup({})
    end,
  },
}
