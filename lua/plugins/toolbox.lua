-- toolbox.nvim — personal script catalog/launcher.
-- Module: lua/toolbox/init.lua. Tools live in the separate ~/tools repo.
--
-- setup() and the user commands run unconditionally here at spec-load time
-- (Lazy always executes every plugins/*.lua file's top-level code during
-- startup, regardless of whether the plugin itself lazy-loads) — this is
-- cheap since setup() never touches telescope/snacks, those are only
-- required lazily inside the functions that actually need them.

local toolbox = require("toolbox")
toolbox.setup({})

-- A failure here should always be visible (and the keymap must keep working
-- on the next press regardless) rather than silently appearing to do nothing.
local function safe(fn)
  return function()
    local ok, err = pcall(fn)
    if not ok then
      vim.notify("toolbox: " .. tostring(err), vim.log.levels.ERROR)
    end
  end
end

vim.api.nvim_create_user_command("Toolbox", safe(toolbox.picker), { desc = "Open the toolbox script picker" })
vim.api.nvim_create_user_command("ToolboxEnv", safe(toolbox.select_env), { desc = "Switch the active toolbox environment" })

return {
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>t", group = "toolbox" },
      },
    },
  },
  {
    "LazyVim/LazyVim",
    keys = {
      { "<leader>tt", safe(toolbox.picker), desc = "Toolbox: open picker" },
      { "<leader>te", safe(toolbox.select_env), desc = "Toolbox: switch environment" },
    },
  },
}
