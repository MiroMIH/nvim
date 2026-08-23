-- sqls  → regular .sql files (DB connection, table/column completions)
-- sqlls → Flyway migration files (no DB needed, syntax/keyword completions)
return {
  {
    "williamboman/mason-lspconfig.nvim",
    opts = {
      ensure_installed = { "sqlls" },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = { sqlls = {} },
    },
    init = function()
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if not client then return end
          local path = vim.api.nvim_buf_get_name(args.buf)
          local is_migration = path:match("db/migration") or path:match("V%d+__")

          if client.name == "sqls" and is_migration then
            vim.lsp.buf_detach_client(args.buf, args.data.client_id)
          elseif client.name == "sqlls" and not is_migration then
            vim.lsp.buf_detach_client(args.buf, args.data.client_id)
          end
        end,
      })
    end,
  },
}
