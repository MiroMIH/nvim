-- NAIS Dashboard — visual control panel for the local dev stack.
-- Design doc: ~/Documents/DevNaisPerso/dev-workflow/nvim/service-dashboard-plugin.md
-- Stage: UI mock only (lua/nais_dashboard/ui.lua) — no docker/process drivers yet.

return {
  {
    "MunifTanjim/nui.nvim",
    lazy = true,
  },
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>n", group = "nais dashboard" },
      },
    },
  },
  {
    "LazyVim/LazyVim",
    keys = {
      {
        "<leader>nn",
        function()
          require("nais_dashboard.ui").open()
        end,
        desc = "Open NAIS Dashboard",
      },
      {
        "<leader>ng",
        function()
          require("nais_dashboard.gallery").open()
        end,
        desc = "Open Component Gallery (demo)",
      },
    },
  },
}
