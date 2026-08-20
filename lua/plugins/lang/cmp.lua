return {
  -- db-value-completion: local dev (switch to "yourusername/db-value-completion.nvim" after publishing)
  {
    dir = vim.fn.expand("~/projects/db-value-completion.nvim"),
    name = "db-value-completion.nvim",
    ft = { "sql", "mysql", "plsql" },
    config = function()
      require("db_value_completion").setup({
        limit = 50,
        cache_ttl = 300,
      })
    end,
  },

  {
    "saghen/blink.cmp",
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      opts.sources.per_filetype = vim.tbl_extend("force", opts.sources.per_filetype or {}, {
        sql   = { "lsp", "dadbod", "db_values" },
        mysql = { "lsp", "dadbod", "db_values" },
        plsql = { "lsp", "dadbod", "db_values" },
      })
      opts.sources.providers = vim.tbl_extend("force", opts.sources.providers or {}, {
        dadbod = {
          name   = "Dadbod",
          module = "vim_dadbod_completion.blink",
          score_offset = 85,
        },
        db_values = {
          name   = "DB Values",
          module = "db_value_completion.sources.blink",
          score_offset = 90,
        },
      })
    end,
  },
}
