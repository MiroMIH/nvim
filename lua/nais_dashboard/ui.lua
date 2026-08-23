-- NAIS Dashboard — control panel UI.
-- Stage: mock data only, no docker/process drivers wired up yet.
-- See ~/Documents/DevNaisPerso/dev-workflow/nvim/service-dashboard-plugin.md
--
-- v2 architecture: previously drew every box as hand-padded ASCII text plus
-- manual byte-offset highlight math into one shared buffer — fragile (three
-- rounds of alignment/overflow bugs). Now: one borderless "backdrop" popup
-- for the frame/title/group headers, and one REAL native-bordered nui.Popup
-- per service box. Neovim draws each box's border itself (can't overflow —
-- it's a window edge, not padded text), coloring is per-window `winhighlight`
-- instead of per-byte-range extmarks, and click-to-select is free: each box
-- is a real window, so a click there natively focuses it, no hit-testing.

local Popup = require("nui.popup")

local M = {}

---@type NuiPopup?
local backdrop = nil
---@type table<table, NuiPopup> service -> its box popup
local box_popups = {}
---@type table? currently focused service (nil = none of our boxes focused)
local focused_svc = nil
---@type table[] services in reading order, for Tab/S-Tab
local nav_order = {}
---@type table<table, integer> service -> index into nav_order
local nav_index_of = {}
local nav_index = 1

local BOX_W = 22 -- interior width (border is separate, native)
local BOX_H = 2 -- interior height: badge+name line, meta line
local COL_GAP = 2
local ROW_GAP = 1

-- Mock registry — stand-in for lua/nais_dashboard/registry.lua (not built yet).
M.mock_services = {
  { name = "auth-postgres", kind = "docker", port = 5432, group = "infra", status = "on" },
  { name = "keycloak", kind = "docker", port = 8180, group = "infra", status = "off" },
  { name = "minio", kind = "docker", port = 9000, group = "infra", status = "on" },
  { name = "mailpit", kind = "docker", port = 8025, group = "infra", status = "off" },
  { name = "auth-service", kind = "process", port = 8080, group = "backend", status = "on" },
  { name = "profile-service", kind = "process", port = 8082, group = "backend", status = "off" },
  { name = "dsv-service", kind = "process", port = 8084, group = "backend", status = "off" },
  { name = "gateway-service", kind = "process", port = 8088, group = "backend", status = "on" },
  { name = "backoffice", kind = "process", port = 5174, group = "frontend", status = "on" },
  { name = "citizen-portal", kind = "process", port = 5173, group = "frontend", status = "off" },
}

local GROUP_ORDER = { "infra", "backend", "frontend" }
local GROUP_LABEL = {
  infra = "Infrastructure",
  backend = "Backend Services",
  frontend = "Frontend Apps",
}

local function setup_highlights()
  vim.api.nvim_set_hl(0, "NaisDashboardOff", { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, "NaisDashboardMeta", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "NaisDashboardGroup", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "NaisDashboardSelectedBorder", { link = "Function", default = true })
  -- Explicit, deliberately-chosen green — theme-derived DiffAdd came out
  -- too dim/muted to read as "green" across most colorschemes.
  vim.api.nvim_set_hl(0, "NaisDashboardBoxOnBg", { bg = "#1b6b3c" })
  vim.api.nvim_set_hl(0, "NaisDashboardBoxOnBorder", { fg = "#1b6b3c" })
  -- Bold white, not green-on-green: badge text sits on top of the green fill.
  vim.api.nvim_set_hl(0, "NaisDashboardBadgeOn", { fg = "#ffffff", bold = true })
  -- "starting" transitional state — amber spinner, reused for the border too.
  vim.api.nvim_set_hl(0, "NaisDashboardStarting", { link = "DiagnosticWarn", default = true })
end

local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local SPIN_INTERVAL_MS = 120
local START_DURATION_MS = 1200
---@type table<table, uv_timer> service -> its in-flight "starting" timer
local starting_timers = {}

-- Converts a 0-indexed *character* column into the 0-indexed *byte* column
-- nvim_buf_add_highlight expects. Each box's buffer is now tiny (2 lines),
-- so this math is contained per-box instead of cascading across a shared
-- multi-box line like it did in v1.
local function byte_col(line, char_col)
  if char_col <= 0 then
    return 0
  end
  return vim.str_byteindex(line, char_col)
end

-- Pads/truncates to a target DISPLAY width, not byte length.
local function pad(str, width)
  str = str or ""
  local w = vim.fn.strdisplaywidth(str)
  if w > width then
    return vim.fn.strcharpart(str, 0, math.max(0, width - 1)) .. "…"
  end
  return str .. string.rep(" ", width - w)
end

local function box_winhl(svc)
  local is_on = svc.status == "on"
  local normal_hl = is_on and "NaisDashboardBoxOnBg" or "Normal"
  local border_hl
  if svc == focused_svc then
    border_hl = "NaisDashboardSelectedBorder"
  elseif svc.status == "starting" then
    border_hl = "NaisDashboardStarting"
  elseif is_on then
    border_hl = "NaisDashboardBoxOnBorder"
  else
    border_hl = "FloatBorder"
  end
  return string.format("Normal:%s,FloatBorder:%s,EndOfBuffer:%s", normal_hl, border_hl, normal_hl)
end

local function render_box(svc)
  local popup = box_popups[svc]
  if not popup or not popup.winid or not vim.api.nvim_win_is_valid(popup.winid) then
    return
  end

  local badge, badge_hl
  if svc.status == "on" then
    badge, badge_hl = "[ON] ", "NaisDashboardBadgeOn"
  elseif svc.status == "starting" then
    -- spinner + label, not a fixed 5-char badge — name padding below is
    -- computed from the badge's actual width, so this doesn't need its own
    -- special-cased column math.
    badge, badge_hl = SPINNER_FRAMES[svc.spin_frame or 1] .. " STARTING", "NaisDashboardStarting"
  else
    badge, badge_hl = "[OFF]", "NaisDashboardOff"
  end
  local badge_w = vim.fn.strdisplaywidth(badge)
  local name_line = badge .. " " .. pad(svc.name, BOX_W - badge_w - 1)
  local meta_line = "  " .. pad(svc.kind .. " · :" .. svc.port, BOX_W - 2)

  vim.bo[popup.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, { name_line, meta_line })
  vim.bo[popup.bufnr].modifiable = false

  local ns = vim.api.nvim_create_namespace("nais_dashboard")
  vim.api.nvim_buf_clear_namespace(popup.bufnr, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(popup.bufnr, ns, badge_hl, 0, 0, byte_col(name_line, badge_w))
  vim.api.nvim_buf_add_highlight(popup.bufnr, ns, "NaisDashboardMeta", 1, 0, -1)

  vim.wo[popup.winid].winhighlight = box_winhl(svc)
end

-- Computes each box's target position (absolute editor row/col, matching
-- what nui's relative="editor" + numeric position expects) and each group
-- header's target line, based on the backdrop's current content area.
local function compute_layout()
  local brow, bcol = unpack(vim.api.nvim_win_get_position(backdrop.winid))
  local content_row = brow + 1 -- +1 for backdrop's own border
  local content_col = bcol + 1
  local win_width = vim.api.nvim_win_get_width(backdrop.winid)

  local footprint_w = BOX_W + 2 -- +2 for each box's own native border
  local footprint_h = BOX_H + 2
  local cols = math.max(1, math.floor(win_width / (footprint_w + COL_GAP)))

  local positions = {} -- svc -> {row=, col=}
  local headers = {} -- {label=, row=}
  local order = {}
  local index_of = {}
  local line_idx = 0

  for _, group_name in ipairs(GROUP_ORDER) do
    local subset = {}
    for _, svc in ipairs(M.mock_services) do
      if svc.group == group_name then
        table.insert(subset, svc)
      end
    end
    if #subset > 0 then
      table.insert(headers, { label = GROUP_LABEL[group_name] or group_name, row = line_idx })
      line_idx = line_idx + 2 -- header + blank line

      local i = 1
      while i <= #subset do
        local col = 0
        for _ = 1, cols do
          if subset[i] then
            local svc = subset[i]
            positions[svc] = { row = content_row + line_idx, col = content_col + col }
            table.insert(order, svc)
            index_of[svc] = #order
            col = col + footprint_w + COL_GAP
            i = i + 1
          end
        end
        line_idx = line_idx + footprint_h + ROW_GAP
      end
      line_idx = line_idx + 1 -- extra gap before next group header
    end
  end

  return positions, headers, order, index_of, line_idx
end

local function render_backdrop_headers(headers, content_height)
  local lines = {}
  for i = 1, content_height do
    lines[i] = ""
  end
  for _, h in ipairs(headers) do
    lines[h.row + 1] = h.label
  end

  vim.bo[backdrop.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(backdrop.bufnr, 0, -1, false, lines)
  vim.bo[backdrop.bufnr].modifiable = false

  local ns = vim.api.nvim_create_namespace("nais_dashboard")
  vim.api.nvim_buf_clear_namespace(backdrop.bufnr, ns, 0, -1)
  for _, h in ipairs(headers) do
    vim.api.nvim_buf_add_highlight(backdrop.bufnr, ns, "NaisDashboardGroup", h.row, 0, -1)
  end
end

local function move_focus(delta)
  if #nav_order == 0 then
    return
  end
  nav_index = ((nav_index - 1 + delta) % #nav_order) + 1
  local svc = nav_order[nav_index]
  local popup = box_popups[svc]
  if popup and popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
    vim.api.nvim_set_current_win(popup.winid)
  end
end

local function stop_spinner(svc)
  local t = starting_timers[svc]
  if t then
    t:stop()
    t:close()
    starting_timers[svc] = nil
  end
end

-- Off -> on is animated (spinner for START_DURATION_MS, like a real service
-- actually booting) instead of an instant flip. On -> off stays instant —
-- matches how `make stop` kills a port immediately vs. `mvnw` taking real
-- time to come up.
local function start_service(svc)
  stop_spinner(svc)
  svc.status = "starting"
  svc.spin_frame = 1
  render_box(svc)

  local elapsed = 0
  local t = vim.uv.new_timer()
  starting_timers[svc] = t
  t:start(
    SPIN_INTERVAL_MS,
    SPIN_INTERVAL_MS,
    vim.schedule_wrap(function()
      if svc.status ~= "starting" then
        stop_spinner(svc)
        return
      end
      elapsed = elapsed + SPIN_INTERVAL_MS
      if elapsed >= START_DURATION_MS then
        svc.status = "on"
        stop_spinner(svc)
      else
        svc.spin_frame = (svc.spin_frame % #SPINNER_FRAMES) + 1
      end
      render_box(svc)
    end)
  )
end

local function toggle(svc)
  if svc.status == "on" then
    svc.status = "off"
    stop_spinner(svc)
    render_box(svc)
  elseif svc.status == "off" then
    start_service(svc)
  end
  -- already "starting": ignore, let the in-flight animation finish
end

-- Reflows the whole panel: repositions the backdrop, recomputes the grid,
-- moves every existing box popup to its new spot. Used on open and resize —
-- never rebuilds the box popups themselves, just their layout config.
local function reflow()
  if not backdrop or not backdrop.winid or not vim.api.nvim_win_is_valid(backdrop.winid) then
    return
  end
  backdrop:update_layout({
    relative = "editor",
    position = "50%",
    size = { width = "94%", height = "90%" },
  })

  local positions, headers, order, index_of, content_height = compute_layout()
  nav_order = order
  nav_index_of = index_of
  render_backdrop_headers(headers, content_height)

  for svc, popup in pairs(box_popups) do
    local pos = positions[svc]
    if pos and popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
      popup:update_layout({
        relative = "editor",
        position = { row = pos.row, col = pos.col },
        size = { width = BOX_W, height = BOX_H },
      })
    end
  end
end

local function close()
  for svc, _ in pairs(starting_timers) do
    stop_spinner(svc)
  end
  for _, popup in pairs(box_popups) do
    pcall(function()
      popup:unmount()
    end)
  end
  box_popups = {}
  focused_svc = nil
  nav_order = {}
  nav_index_of = {}
  if backdrop then
    pcall(function()
      backdrop:unmount()
    end)
    backdrop = nil
  end
end

local function attach_shared_keys(popup)
  popup:map("n", "q", close, { noremap = true })
  popup:map("n", "<Esc>", close, { noremap = true })
  popup:map("n", "<Tab>", function()
    move_focus(1)
  end, { noremap = true })
  popup:map("n", "<S-Tab>", function()
    move_focus(-1)
  end, { noremap = true })
end

function M.open()
  if backdrop and backdrop.winid and vim.api.nvim_win_is_valid(backdrop.winid) then
    vim.api.nvim_set_current_win(backdrop.winid)
    return
  end

  setup_highlights()

  backdrop = Popup({
    relative = "editor",
    position = "50%",
    size = { width = "94%", height = "90%" },
    enter = true,
    focusable = true,
    zindex = 50,
    border = {
      style = "rounded",
      text = {
        top = "  NAIS Control Panel  ",
        top_align = "center",
        bottom = "  <Tab>/<S-Tab> select · <CR>/click toggle · q close  ",
        bottom_align = "center",
      },
    },
    buf_options = { modifiable = false, filetype = "naisdashboard" },
    win_options = { winblend = 0, cursorline = false, wrap = false, list = false },
  })
  backdrop:mount()
  attach_shared_keys(backdrop)

  local positions = compute_layout() -- first pass just to get positions for creation
  for _, svc in ipairs(M.mock_services) do
    local pos = positions[svc]
    if pos then
      local popup = Popup({
        relative = "editor",
        position = { row = pos.row, col = pos.col },
        size = { width = BOX_W, height = BOX_H },
        enter = false,
        focusable = true,
        zindex = 60,
        border = { style = "rounded" },
        buf_options = { modifiable = false, filetype = "naisdashboardbox" },
        win_options = { winblend = 0, cursorline = false, wrap = false, list = false },
      })
      popup:mount()
      box_popups[svc] = popup

      attach_shared_keys(popup)
      popup:map("n", "<CR>", function()
        toggle(svc)
      end, { noremap = true })
      popup:map("n", "<LeftMouse>", function()
        toggle(svc)
      end, { noremap = true })

      popup:on("WinEnter", function()
        focused_svc = svc
        nav_index = nav_index_of[svc] or nav_index
        render_box(svc)
      end)
      popup:on("WinLeave", function()
        if focused_svc == svc then
          focused_svc = nil
        end
        render_box(svc)
      end)

      render_box(svc)
    end
  end

  reflow()
  backdrop:on("VimResized", reflow)

  move_focus(0) -- focus the first box in reading order
  vim.cmd("redraw")
end

return M
