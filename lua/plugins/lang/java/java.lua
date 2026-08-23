-- Java LSP via nvim-jdtls
-- Builds on LazyVim's lang.java extra with project-specific config:
--   · per-service workspace dirs (each service has its own pom.xml)
--   · Lombok javaagent (required — every service uses @Getter, @Builder, etc.)
--   · Java 21 settings

return {
  -- Override jdtls config for this project
  -- (lang.java extra is enabled via lazyvim.json)
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      local lombok_jar = vim.fn.expand(
        "~/.m2/repository/org/projectlombok/lombok/1.18.42/lombok-1.18.42.jar"
      )

      opts.settings = vim.tbl_deep_extend("force", opts.settings or {}, {
        java = {
          configuration = {
            runtimes = {
              {
                name = "JavaSE-21",
                path = "/usr/lib/jvm/java-21-openjdk",
                default = true,
              },
            },
          },
          jdt = { ls = { lombokSupport = { enabled = true } } },
          format = { enabled = false }, -- we use conform.nvim + palantir instead
          saveActions = { organizeImports = true },
          completion = {
            favoriteStaticMembers = {
              "org.assertj.core.api.Assertions.*",
              "org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*",
              "org.springframework.test.web.servlet.result.MockMvcResultMatchers.*",
            },
            importOrder = { "java", "javax", "jakarta", "org", "com", "local.madr" },
          },
          sources = {
            organizeImports = {
              starThreshold = 9999,
              staticStarThreshold = 9999,
            },
          },
        },
      })

      -- Lombok javaagent — without this every @Getter/@Builder shows as an error
      opts.cmd_env = { JAVA_TOOL_OPTIONS = "-javaagent:" .. lombok_jar }

      -- Per-service workspace: each service gets its own jdtls workspace dir
      -- so classpaths don't bleed between auth-service, dgsv-service, etc.
      opts.root_dir = function(fname)
        return require("jdtls.setup").find_root({ "pom.xml", ".git" }, fname)
      end

      opts.workspace_folder_fn = function()
        local root = require("jdtls.setup").find_root({ "pom.xml", ".git" })
        if not root then return vim.fn.getcwd() end
        local service_name = vim.fn.fnamemodify(root, ":t")
        local ws = vim.fn.stdpath("data") .. "/jdtls-workspaces/" .. service_name
        vim.fn.mkdir(ws, "p")
        return ws
      end

      return opts
    end,
  },
}
