-- Database: vim-dadbod + vim-dadbod-ui
-- Query all 5 NAIS Postgres databases from inside Neovim.
-- Requires:  make infra  to be running (starts the DBs via Docker)

return {
  {
    "tpope/vim-dadbod",
    lazy = true,
  },
  {
    "kristijanhusak/vim-dadbod-ui",
    dependencies = { "tpope/vim-dadbod" },
    cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection" },
    keys = {
      { "<leader>db", "<cmd>DBUIToggle<cr>", desc = "Toggle DB UI" },
    },
    init = function()
      vim.g.dbs = dofile(vim.fn.expand("~/.local/share/nvim/dbs.lua"))

      vim.g.db_ui_result_window_position = "below"
      vim.g.db_ui_result_window_height = 20

      -- Save query history and layout
      vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui"
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_show_database_icon = 1

      -- Auto-execute on save in .sql buffers opened from DBUI
      vim.g.db_ui_execute_on_save = 0  -- off — use explicit keybind instead

      -- Set explicit keymaps in every DBUI query buffer
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "sql", "mysql", "plsql" },
        callback = function()
          -- Normal mode: run whole buffer
          vim.keymap.set("n", "<leader>dr", "<Plug>(DBUI_ExecuteQuery)", { buffer = true, desc = "Run query" })
          -- Visual mode: run selected lines only
          vim.keymap.set("v", "<leader>dr", "<Plug>(DBUI_ExecuteQuery)", { buffer = true, desc = "Run selected query" })
        end,
      })
    end,
  },
  {
    "kristijanhusak/vim-dadbod-completion",
    dependencies = { "tpope/vim-dadbod" },
    ft = { "sql", "mysql", "plsql" },
  },
}
