return {
  "hrsh7th/nvim-cmp",
  dependencies = { "kristijanhusak/vim-dadbod-completion" },
  opts = function(_, opts)
    local cmp = require("cmp")
    opts.sources = opts.sources or {}
    table.insert(opts.sources, { name = "vim-dadbod-completion" })

    -- Only show dadbod completions in SQL buffers
    opts.enabled = function()
      local ft = vim.bo.filetype
      if ft == "sql" or ft == "mysql" or ft == "plsql" then
        return true
      end
      return require("cmp.config.default")().enabled()
    end
  end,
}
