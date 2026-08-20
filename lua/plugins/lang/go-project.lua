-- Go project management: detect/switch via project.nvim, create via :GoNewProject
--   · detects roots via go.mod / .git and remembers recently opened projects
--   · <leader>fp opens the Telescope project switcher
--   · :GoNewProject <path> scaffolds a new module (mkdir, go mod init, main.go) and opens it

return {
  {
    "ahmedkhalf/project.nvim",
    event = "VeryLazy",
    opts = {
      patterns = { "go.mod", ".git", "Makefile" },
      detection_methods = { "pattern" },
      silent_chdir = true,
    },
    config = function(_, opts)
      require("project_nvim").setup(opts)
      require("telescope").load_extension("projects")
    end,
    keys = {
      { "<leader>fp", "<cmd>Telescope projects<cr>", desc = "Switch Project" },
    },
  },

  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "ahmedkhalf/project.nvim" },
  },

  {
    "LazyVim/LazyVim",
    init = function()
      vim.api.nvim_create_user_command("GoNewProject", function(cmd_opts)
        local path = cmd_opts.args
        if path == "" then
          vim.notify("Usage: :GoNewProject <path>", vim.log.levels.ERROR)
          return
        end

        path = vim.fn.fnamemodify(path, ":p")
        local module_name = vim.fn.fnamemodify(path, ":t")

        vim.fn.mkdir(path, "p")

        vim.system({ "go", "mod", "init", module_name }, { cwd = path }):wait()

        local main_go = path .. "/main.go"
        if vim.fn.filereadable(main_go) == 0 then
          vim.fn.writefile({
            "package main",
            "",
            'import "fmt"',
            "",
            "func main() {",
            '\tfmt.Println("hello, ' .. module_name .. '")',
            "}",
          }, main_go)
        end

        vim.cmd.cd(path)
        vim.cmd.edit(main_go)
        vim.notify("Created Go project: " .. module_name)
      end, { nargs = 1, complete = "dir", desc = "Scaffold a new Go project" })
    end,
  },
}
