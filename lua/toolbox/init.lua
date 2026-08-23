-- toolbox.nvim — personal script catalog/launcher.
-- Scans a tools directory for executable scripts, reads `# desc:` metadata
-- comments, and shows them in a plain split list (no Telescope/fuzzy popup
-- — j/k + <CR>, with the file content live-previewed alongside as you
-- move). Running a tool opens a plain vertical split terminal (native
-- jobstart, no Snacks.terminal — its toggle-by-command identity semantics
-- were hiding/losing terminals across repeat runs).
-- Tools live in a separate repo: ~/tools (see ~/tools/README.md).

local M = {}

M.config = {
  dirs = { vim.fn.expand("~/tools") },
  recursive = true,
  -- fraction of editor width the terminal split takes
  terminal = { width_fraction = 0.4 },
  -- extension (no dot) -> interpreter. Anything not listed here runs
  -- directly via its own shebang + exec bit.
  interpreters = {
    py = "python3",
    lua = "lua",
    js = "node",
    rb = "ruby",
  },
  environments = { "local", "dev", "staging", "prod" },
  default_env = "local",
}

local ENV_DIR = vim.fn.expand("~/tools/env")
local ENV_STATE_FILE = vim.fn.expand("~/tools/.toolbox-env")
local SCAN_EXCLUDE = { [".git"] = true, ["env"] = true }

local configured = false

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  configured = true
end

local function ensure_configured()
  if not configured then
    M.setup({})
  end
end

--- Metadata + discovery ------------------------------------------------

-- Reads `# desc: ...` from the first few comment lines of a script. Stops
-- at the first non-comment, non-shebang line. Scripts that need input just
-- read it themselves (e.g. `read -p`) once running in the terminal — no
-- separate args-prompt step, since the terminal is already interactive.
local function parse_metadata(path)
  local meta = { desc = nil }
  local f = io.open(path, "r")
  if not f then
    return meta
  end
  local n = 0
  for line in f:lines() do
    n = n + 1
    if n > 20 then
      break
    end
    if n == 1 and line:match("^#!") then
      goto continue
    end
    if not line:match("^#") then
      break
    end
    local desc = line:match("^#+%s*[Dd][Ee][Ss][Cc]:%s*(.*)$")
    if desc then
      meta.desc = desc
    end
    ::continue::
  end
  f:close()
  return meta
end

local function scan_dir(dir, recursive, results)
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return
  end
  while true do
    local name, kind = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if not SCAN_EXCLUDE[name] and not name:match("^%.") then
      local path = dir .. "/" .. name
      if kind == "directory" and recursive then
        scan_dir(path, recursive, results)
      elseif kind == "file" then
        local ext = path:match("%.([%w_]+)$")
        -- Include it if it's directly runnable (exec bit + shebang) OR its
        -- extension has an interpreter configured — a .py file shouldn't
        -- need chmod +x just because `python3 script.py` doesn't care.
        local runnable = vim.fn.executable(path) == 1 or (ext and M.config.interpreters[ext] ~= nil)
        if runnable then
          local meta = parse_metadata(path)
          table.insert(results, {
            name = name,
            path = path,
            desc = meta.desc,
            ext = ext,
          })
        end
      end
    end
  end
end

function M.scan_tools()
  ensure_configured()
  local results = {}
  for _, dir in ipairs(M.config.dirs) do
    scan_dir(dir, M.config.recursive, results)
  end
  table.sort(results, function(a, b)
    return a.name < b.name
  end)
  return results
end

--- Environments ----------------------------------------------------------

function M.get_current_env()
  ensure_configured()
  local f = io.open(ENV_STATE_FILE, "r")
  if not f then
    return M.config.default_env
  end
  local env = f:read("l")
  f:close()
  env = env and env:match("^%s*(.-)%s*$") or nil
  if not env or not vim.tbl_contains(M.config.environments, env) then
    return M.config.default_env
  end
  return env
end

function M.set_current_env(name)
  local f = io.open(ENV_STATE_FILE, "w")
  if not f then
    vim.notify("toolbox: couldn't write " .. ENV_STATE_FILE, vim.log.levels.ERROR)
    return
  end
  f:write(name .. "\n")
  f:close()
end

function M.select_env()
  ensure_configured()
  vim.ui.select(M.config.environments, {
    prompt = "Toolbox environment",
    format_item = function(item)
      return item == M.get_current_env() and (item .. "  (current)") or item
    end,
  }, function(choice)
    if choice then
      M.set_current_env(choice)
      vim.notify("toolbox: env -> " .. choice:upper())
    end
  end)
end

-- Parses a simple KEY=VALUE env file (comments/blank lines skipped) into a
-- Lua table, so it can be passed straight to Snacks.terminal's `env` option
-- — no shell `source` involved, no quoting to get wrong.
local function parse_env_file(path)
  local env = {}
  local f = io.open(path, "r")
  if not f then
    return env
  end
  for line in f:lines() do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" and not trimmed:match("^#") then
      local k, v = trimmed:match("^([%w_]+)=(.*)$")
      if k then
        v = v:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
        env[k] = v
      end
    end
  end
  f:close()
  return env
end

local function build_env_table()
  local current = M.get_current_env()
  local env_file = ENV_DIR .. "/" .. current .. ".env"
  local env = parse_env_file(env_file)
  env.TOOLBOX_ENV = current:upper()
  return env
end

--- Running -----------------------------------------------------------------

-- Builds an argv table (never a shell string) — Snacks.terminal runs this
-- directly, so tool names/paths/args never need shell-escaping.
function M.build_cmd(tool, args_str)
  local cmd = {}
  local interpreter = tool.ext and M.config.interpreters[tool.ext]
  if interpreter then
    table.insert(cmd, interpreter)
  end
  table.insert(cmd, tool.path)
  if args_str and args_str ~= "" then
    for word in args_str:gmatch("%S+") do
      table.insert(cmd, word)
    end
  end
  return cmd
end

-- Plain vertical split + native jobstart(..., {term=true}) — a fresh
-- window/buffer every call, so there's no toggle/identity/caching state
-- that could hide an already-open terminal or leave a stale one behind.
local function launch(tool, args_str, cwd)
  cwd = cwd or vim.fn.getcwd()
  local cmd = M.build_cmd(tool, args_str)
  local env = build_env_table()

  -- Opens in whatever tab is current when this runs — from the toolbox
  -- list that's the toolbox tab itself (by design: list + terminal share
  -- one tab, closing the picker closes both together).
  vim.cmd("botright vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, math.floor(vim.o.columns * M.config.terminal.width_fraction))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)

  local job_ok, job_err = pcall(vim.fn.jobstart, cmd, { term = true, cwd = cwd, env = env })
  if not job_ok then
    vim.notify("toolbox: failed to start " .. tool.name .. " — " .. tostring(job_err), vim.log.levels.ERROR)
    vim.api.nvim_win_close(win, true)
    return
  end

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true, desc = "Close toolbox terminal" })
  vim.cmd("startinsert")
end

-- No args-prompt step: the terminal is already interactive, so a script
-- that needs input just reads it itself (`read -p ...` etc.) once running.
function M.run_tool(tool, opts)
  opts = opts or {}
  launch(tool, nil, opts.cwd)
end

function M.copy_command(tool)
  local parts = M.build_cmd(tool, nil)
  local cmd_str = "TOOLBOX_ENV=" .. M.get_current_env():upper() .. " " .. table.concat(parts, " ")
  vim.fn.setreg("+", cmd_str)
  vim.notify("toolbox: copied — " .. cmd_str)
end

--- List UI ---------------------------------------------------------------
-- Plain split list instead of a Telescope fuzzy popup, opened in its own
-- isolated TAB — not spliced into whatever layout (neo-tree sidebar, other
-- splits) was already on screen; a tabpage-relative split like
-- `topleft vsplit` would just squeeze in next to that. Running a tool opens
-- its terminal in this same tab, alongside the list — closing the picker
-- (toggle <leader>tt, or q/<Esc>) closes the whole tab, terminal included,
-- and returns to the exact original tab untouched.

local list_state = nil

local function list_current_tool()
  if not list_state or not vim.api.nvim_win_is_valid(list_state.list_win) then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(list_state.list_win)[1]
  return list_state.tools[line]
end

local function list_update_preview()
  local tool = list_current_tool()
  if not tool or not list_state or not vim.api.nvim_win_is_valid(list_state.preview_win) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(list_state.preview_win)
  -- Only overwrite if the preview window is still showing our scratch
  -- buffer — if the user pressed `e` and it's now a real editable file
  -- buffer, leave it alone.
  if buf ~= list_state.preview_buf then
    return
  end
  local lines = vim.fn.readfile(tool.path)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local ft = vim.filetype.match({ filename = tool.path })
  vim.bo[buf].filetype = ft or ""
end

function M.close_picker()
  if not list_state then
    return
  end
  local tab = list_state.tab
  local origin_tab = list_state.origin_tab
  local list_buf = list_state.list_buf
  local preview_buf = list_state.preview_buf
  list_state = nil
  if vim.api.nvim_tabpage_is_valid(tab) then
    pcall(vim.cmd, vim.api.nvim_tabpage_get_number(tab) .. "tabclose")
  end
  if vim.api.nvim_tabpage_is_valid(origin_tab) then
    vim.api.nvim_set_current_tabpage(origin_tab)
  end
  -- `:tabclose` only removes the windows — the buffers that were shown in
  -- them (including :tabnew's own default empty buffer, which is *listed*
  -- by default) stick around as orphaned "[No Name]" entries otherwise,
  -- piling up in bufferline one per toggle.
  if vim.api.nvim_buf_is_valid(list_buf) then
    pcall(vim.api.nvim_buf_delete, list_buf, { force = true })
  end
  if vim.api.nvim_buf_is_valid(preview_buf) then
    pcall(vim.api.nvim_buf_delete, preview_buf, { force = true })
  end
end

function M.picker()
  ensure_configured()
  if list_state and vim.api.nvim_tabpage_is_valid(list_state.tab) then
    -- <leader>tt again while it's open = toggle closed, back to whatever
    -- you were doing, rather than just refocusing the list.
    M.close_picker()
    return
  end

  local tools = M.scan_tools()
  if #tools == 0 then
    vim.notify("toolbox: no tools found in " .. table.concat(M.config.dirs, ", "), vim.log.levels.WARN)
    return
  end

  local origin_tab = vim.api.nvim_get_current_tabpage()
  local origin_dir = vim.fn.expand("%:p:h")
  if origin_dir == "" then
    origin_dir = vim.fn.getcwd()
  end

  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()
  local preview_win = vim.api.nvim_get_current_win()
  local preview_buf = vim.api.nvim_get_current_buf()
  vim.bo[preview_buf].buftype = "nofile"
  vim.bo[preview_buf].buflisted = false
  vim.bo[preview_buf].swapfile = false
  vim.bo[preview_buf].modifiable = false
  -- q/<Esc> close the picker from the preview pane too, not just the list —
  -- without this, plain Vim `q` in the preview pane starts recording a
  -- macro instead (no mapping there = falls through to native behavior).
  -- Only wired up now, while it's still our scratch buffer; once `e`
  -- swaps in a real file buffer, that buffer never had this mapping, so
  -- normal editing keys work as expected there.
  vim.keymap.set("n", "q", function()
    M.close_picker()
  end, { buffer = preview_buf, silent = true, desc = "Toolbox: close" })
  vim.keymap.set("n", "<Esc>", function()
    M.close_picker()
  end, { buffer = preview_buf, silent = true, desc = "Toolbox: close" })

  vim.cmd("leftabove 42vsplit")
  local list_win = vim.api.nvim_get_current_win()
  local list_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(list_win, list_buf)
  vim.bo[list_buf].filetype = "toolboxlist"
  vim.wo[list_win].cursorline = true
  vim.wo[list_win].number = false
  vim.wo[list_win].wrap = false

  -- Name only in the listing — desc is still visible in the live preview
  -- pane on the right as you move through the list.
  local lines = {}
  for _, t in ipairs(tools) do
    table.insert(lines, t.name)
  end
  vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
  vim.bo[list_buf].modifiable = false

  list_state = {
    tab = tab,
    origin_tab = origin_tab,
    list_win = list_win,
    list_buf = list_buf,
    preview_win = preview_win,
    preview_buf = preview_buf,
    origin_dir = origin_dir,
    tools = tools,
  }

  vim.api.nvim_create_autocmd("CursorMoved", { buffer = list_buf, callback = list_update_preview })
  list_update_preview()

  local function map(key, fn, desc)
    vim.keymap.set("n", key, fn, { buffer = list_buf, silent = true, desc = desc })
  end

  map("<CR>", function()
    local tool = list_current_tool()
    if tool then
      M.run_tool(tool, { cwd = vim.fn.getcwd() })
    end
  end, "Toolbox: run")
  map("f", function()
    local tool = list_current_tool()
    if tool and list_state then
      M.run_tool(tool, { cwd = list_state.origin_dir })
    end
  end, "Toolbox: run in origin file's dir")
  map("e", function()
    local tool = list_current_tool()
    if tool and list_state and vim.api.nvim_win_is_valid(list_state.preview_win) then
      vim.api.nvim_set_current_win(list_state.preview_win)
      vim.cmd.edit(tool.path)
    end
  end, "Toolbox: edit")
  map("y", function()
    local tool = list_current_tool()
    if tool then
      M.copy_command(tool)
    end
  end, "Toolbox: copy run command")
  map("r", M.select_env, "Toolbox: switch environment")
  map("q", M.close_picker, "Toolbox: close")
  vim.keymap.set("n", "<Esc>", M.close_picker, { buffer = list_buf, silent = true, desc = "Toolbox: close" })
end

return M
