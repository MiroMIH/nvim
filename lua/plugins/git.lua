-- Git workflow:
--   lazygit   → full TUI (already installed on system, wired via snacks)
--   neogit    → Magit-style stage/commit/push without leaving Neovim
--   diffview  → side-by-side diff, file history, merge conflicts
--   gitsigns  → already installed by LazyVim (inline hunks in gutter)

return {
  -- Magit-style git UI inside Neovim
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
    },
    cmd = "Neogit",
    keys = {
      { "<leader>gn", "<cmd>Neogit<cr>",        desc = "Neogit (stage/commit/push)" },
      { "<leader>gd", "<cmd>DiffviewOpen<cr>",   desc = "Diff view (branch diff)" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
      { "<leader>gD", "<cmd>DiffviewClose<cr>",  desc = "Close diff view" },
    },
    opts = {
      integrations = { diffview = true },
      signs = {
        hunk = { "", "" },
        item = { ">", "v" },
        section = { ">", "v" },
      },
    },
  },

  -- Side-by-side diff viewer
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
  },

  -- gitsigns already installed by LazyVim — extend with extra keymaps
  {
    "lewis6991/gitsigns.nvim",
    opts = function(_, opts)
      local gs = require("gitsigns")
      opts.on_attach = function(bufnr)
        local map = function(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
        end

        -- Navigate hunks
        map("n", "]h", gs.next_hunk,        "Next git hunk")
        map("n", "[h", gs.prev_hunk,        "Prev git hunk")

        -- Stage / reset
        map("n", "<leader>gs", gs.stage_hunk,   "Stage hunk")
        map("n", "<leader>gu", gs.undo_stage_hunk, "Undo stage hunk")
        map("n", "<leader>gS", gs.stage_buffer, "Stage entire file")
        map("n", "<leader>gr", gs.reset_hunk,   "Reset hunk")

        -- Preview & blame
        map("n", "<leader>gp", gs.preview_hunk, "Preview hunk diff")
        map("n", "<leader>gb", function() gs.blame_line({ full = true }) end, "Blame line")

        -- Visual mode stage
        map("v", "<leader>gs", function()
          gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
        end, "Stage selected hunks")
      end
      return opts
    end,
  },
}
