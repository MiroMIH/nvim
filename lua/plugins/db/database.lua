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

          -- DBUI's "New query" opens its buffer in a fresh split rather than
          -- reusing the LazyVim start screen's window (dashboard's buftype
          -- and non-modifiable state make dadbod-ui's focus_window() skip
          -- it), so the dashboard is left behind in another window — and
          -- its "q" keymap is bound to `:qa`, not "close this window", so
          -- pressing q on it quits Neovim entirely. Once a real query
          -- buffer exists, the dashboard has nothing left to do.
          --
          -- Delete its buffer (not nvim_win_close on the window) so Snacks'
          -- own BufWipeout/BufDelete autocmd runs and tears down its
          -- WinResized/VimResized autocmd along with it — closing the
          -- window directly skips that cleanup and leaves the resize
          -- autocmd pointing at a now-invalid window id.
          --
          -- Deferred to the next tick: this FileType event fires while
          -- dadbod-ui's own open_buffer/setup_buffer is still mid-transaction
          -- (it hasn't finished laying out the new split yet), so touching
          -- other windows/buffers here can itself trigger a WinResized
          -- while Snacks' dashboard autocmd is between "about to fire" and
          -- "about to be torn down" — same stale-window-id error, just
          -- self-inflicted instead of dadbod-ui's. Running after the event
          -- loop settles avoids racing that window.
          vim.schedule(function()
            local dash_wins, dash_bufs, seen = {}, {}, {}
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
              local dbuf = vim.api.nvim_win_get_buf(win)
              if vim.b[dbuf].snacks_main then
                dash_wins[#dash_wins + 1] = win
                if not seen[dbuf] then
                  seen[dbuf] = true
                  dash_bufs[#dash_bufs + 1] = dbuf
                end
              end
            end
            for _, dbuf in ipairs(dash_bufs) do
              pcall(vim.api.nvim_buf_delete, dbuf, { force = true })
            end
            for _, win in ipairs(dash_wins) do
              if vim.api.nvim_win_is_valid(win) and #vim.api.nvim_tabpage_list_wins(0) > 1 then
                pcall(vim.api.nvim_win_close, win, true)
              end
            end
          end)
        end,
      })
    end,
  },
  {
    "kristijanhusak/vim-dadbod-completion",
    dependencies = { "tpope/vim-dadbod" },
    ft = { "sql", "mysql", "plsql" },
  },

  {
    dir = vim.fn.expand("~/Projects/personal_projects/dbout-render.nvim"),
    name = "dbout-render.nvim",
    ft = "dbout",
    config = function()
      require("dbout_render").setup()
    end,
  },
}
