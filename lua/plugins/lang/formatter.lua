-- Java formatting via Spotless (Palantir Java Format 2.50.0)
-- Maven is too slow for conform.nvim integration — runs async instead.
-- Keybinding:  Space j f  →  runs ./mvnw spotless:apply in the background
-- Neovim stays fully responsive while it runs.

return {
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      -- No Java formatter in conform — handled by the keybinding below
      opts.format_on_save = false
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.sql = { "sql_formatter" }
      return opts
    end,
  },
  {
    "folke/snacks.nvim",
    opts = function()
      -- Register  Space j f  for Java formatting via Spotless
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "java",
        callback = function()
          vim.keymap.set("n", "<leader>jf", function()
            local root = require("jdtls.setup").find_root({ "pom.xml" })
            if not root then
              vim.notify("No pom.xml found", vim.log.levels.ERROR)
              return
            end

            vim.notify("Spotless: formatting...", vim.log.levels.INFO)

            vim.fn.jobstart({ "./mvnw", "spotless:apply", "-q" }, {
              cwd = root,
              on_exit = function(_, code)
                if code == 0 then
                  -- Reload the file to show formatted content
                  vim.schedule(function()
                    vim.cmd("checktime")
                    vim.notify("Spotless: done ✓", vim.log.levels.INFO)
                  end)
                else
                  vim.schedule(function()
                    vim.notify("Spotless: failed (check Maven output)", vim.log.levels.ERROR)
                  end)
                end
              end,
            })
          end, { buffer = true, desc = "Format with Spotless (Palantir)" })
        end,
      })
    end,
  },
}
