-- Enables Java debugging (nvim-dap + nvim-dap-ui).
-- The lang.java LazyVim extra already wires jdtls <-> dap.configurations.java
-- and mason ensure_installed for java-debug-adapter/java-test, but only if
-- nvim-dap itself is actually loaded as a plugin — it's declared `optional`
-- over there, so it does nothing unless we add the real plugin here.

return {
  {
    "mfussenegger/nvim-dap",
    -- nvim-dap has no setup() function. Without this, lazy.nvim's default
    -- "opts present -> require(main).setup(opts)" behavior kicks in once
    -- the lang.java extra's `opts` merges onto this spec, and blows up
    -- trying to call a nil `dap.setup`. The extra's opts function still
    -- runs (it registers dap.configurations.java as a side effect during
    -- opts merging) — this just stops lazy from also calling setup(opts).
    config = function() end,
    dependencies = {
      "nvim-neotest/nvim-nio",
      {
        "rcarriga/nvim-dap-ui",
        opts = {},
        config = function(_, opts)
          local dapui = require("dapui")
          dapui.setup(opts)
          local dap = require("dap")
          dap.listeners.after.event_initialized["dapui_config"] = function()
            dapui.open()
          end
          dap.listeners.before.event_terminated["dapui_config"] = function()
            dapui.close()
          end
          dap.listeners.before.event_exited["dapui_config"] = function()
            dapui.close()
          end
        end,
      },
    },
    keys = {
      { "<leader>dB", function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
      { "<leader>dc", function() require("dap").continue() end, desc = "Continue" },
      { "<leader>do", function() require("dap").step_over() end, desc = "Step Over" },
      { "<leader>di", function() require("dap").step_into() end, desc = "Step Into" },
      { "<leader>du", function() require("dap").step_out() end, desc = "Step Out" },
      { "<leader>dt", function() require("dap").terminate() end, desc = "Terminate" },
      { "<leader>dU", function() require("dapui").toggle() end, desc = "Toggle Dap UI" },
    },
  },
}
