-- Component gallery — throwaway demo, NOT wired into the real dashboard.
-- Purpose: play with live/animated UI pieces and real per-character color
-- (gradients, hue-cycling) before deciding what's worth folding into the
-- real dashboard. Neovim floating windows support true 24-bit color, so
-- none of this is limited to the usual 16/256-color terminal palette.

local Popup = require("nui.popup")

local M = {}

local popup = nil
local timer = nil
local tick = 0

local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local SPARK_CHARS = { "▁", "▂", "▃", "▅", "▇", "▆", "▄", "▂", "▁", "▂", "▃", "▆", "█", "▇", "▅", "▃", "▂", "▁" }

--- Color helpers -----------------------------------------------------------

local function hex(r, g, b)
  return string.format("#%02x%02x%02x", math.max(0, math.min(255, r)), math.max(0, math.min(255, g)), math.max(0, math.min(255, b)))
end

-- Linear interpolation between two "#rrggbb" colors, t in [0,1].
local function mix(c1, c2, t)
  local r1, g1, b1 = tonumber(c1:sub(2, 3), 16), tonumber(c1:sub(4, 5), 16), tonumber(c1:sub(6, 7), 16)
  local r2, g2, b2 = tonumber(c2:sub(2, 3), 16), tonumber(c2:sub(4, 5), 16), tonumber(c2:sub(6, 7), 16)
  return hex(math.floor(r1 + (r2 - r1) * t + 0.5), math.floor(g1 + (g2 - g1) * t + 0.5), math.floor(b1 + (b2 - b1) * t + 0.5))
end

-- HSL (h in [0,1), fixed s/l) -> "#rrggbb", for hue-cycling/rainbow effects.
local function hsl_to_hex(h)
  local s, l = 0.70, 0.55
  local function hue2rgb(p, q, t)
    if t < 0 then
      t = t + 1
    end
    if t > 1 then
      t = t - 1
    end
    if t < 1 / 6 then
      return p + (q - p) * 6 * t
    end
    if t < 1 / 2 then
      return q
    end
    if t < 2 / 3 then
      return p + (q - p) * (2 / 3 - t) * 6
    end
    return p
  end
  local q = l < 0.5 and l * (1 + s) or l + s - l * s
  local p = 2 * l - q
  local r = hue2rgb(p, q, h + 1 / 3)
  local g = hue2rgb(p, q, h)
  local b = hue2rgb(p, q, h - 1 / 3)
  return hex(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local GREEN, YELLOW, RED = "#22c55e", "#eab308", "#ef4444"
-- Health/severity gradient: green at t=0, through yellow, to red at t=1.
local function severity_color(t)
  if t < 0.6 then
    return mix(GREEN, YELLOW, t / 0.6)
  end
  return mix(YELLOW, RED, (t - 0.6) / 0.4)
end

-- Highlight groups are cheap but shouldn't be redefined every frame for the
-- same color, so cache by hex value -> group name.
local hl_fg_cache = {}
local function hl_fg(color)
  local name = hl_fg_cache[color]
  if not name then
    name = "NaisGalleryFg" .. color:sub(2)
    vim.api.nvim_set_hl(0, name, { fg = color })
    hl_fg_cache[color] = name
  end
  return name
end
local hl_bg_cache = {}
local function hl_bg(color)
  local name = hl_bg_cache[color]
  if not name then
    name = "NaisGalleryBg" .. color:sub(2)
    vim.api.nvim_set_hl(0, name, { bg = color })
    hl_bg_cache[color] = name
  end
  return name
end

-- Character offset -> byte offset (nvim_buf_add_highlight wants bytes; the
-- block-drawing glyphs used below are multi-byte UTF-8 despite being 1
-- display cell each).
local function byte_col(line, char_col)
  if char_col <= 0 then
    return 0
  end
  return vim.str_byteindex(line, char_col)
end

--- Component renderers ------------------------------------------------------

local function bar(pct, width)
  local filled = math.floor(width * pct / 100 + 0.5)
  return "[" .. string.rep("█", filled) .. string.rep("░", width - filled) .. "]"
end

local function render()
  if not popup or not popup.winid or not vim.api.nvim_win_is_valid(popup.winid) then
    return
  end
  tick = tick + 1

  local lines = {}
  local hls = {} -- { {line=0idx, char_start=, char_end=, group=} }
  local function push(line_text)
    table.insert(lines, line_text)
    return #lines - 1
  end
  local function add_hl(line_idx0, char_start, char_end, group)
    table.insert(hls, { line = line_idx0, char_start = char_start, char_end = char_end, group = group })
  end

  local loading_pct = tick % 40 < 20 and (tick % 20) * 5 or 100 - (tick % 20) * 5
  local spin = SPINNER_FRAMES[(tick % #SPINNER_FRAMES) + 1]
  local spark_offset = tick % #SPARK_CHARS
  local spark = {}
  for i = 1, 18 do
    table.insert(spark, SPARK_CHARS[((i + spark_offset) % #SPARK_CHARS) + 1])
  end

  push("")
  push("  1) Loading bar — service starting/stopping")
  push("     auth-service  " .. bar(loading_pct, 24) .. string.format("  %3d%%", loading_pct))
  push("")
  push("  2) Braille spinner — lightweight \"working\" indicator")
  push("     " .. spin .. "  connecting to keycloak...")
  push("")
  push("  3) Status badge pill (static)")
  push("     [ON]  [OFF]  [STARTING]  [ERROR]")
  push("")
  push("  4) Sparkline — request rate / port traffic over time")
  push("     " .. table.concat(spark))
  push("")

  -- 5) Gauges with a real green->yellow->red severity gradient, not a flat
  --    color — each filled cell gets its own color based on position.
  push("  5) Gradient gauge — color encodes severity, not just fill %")
  local cpu_pct = math.floor(45 + 25 * math.sin(tick * 0.05) + 0.5)
  local mem_pct = math.floor(60 + 25 * math.sin(tick * 0.03 + 1) + 0.5)
  for _, row in ipairs({ { "CPU", cpu_pct }, { "MEM", mem_pct } }) do
    local label, pct = row[1], row[2]
    local width = 24
    local filled = math.floor(width * pct / 100 + 0.5)
    local prefix = "     " .. label .. "  "
    local segs = {}
    for i = 1, width do
      segs[i] = i <= filled and "█" or "░"
    end
    local line = prefix .. "▕" .. table.concat(segs) .. "▏ " .. pct .. "%"
    local lineidx = push(line)
    local base = vim.fn.strchars(prefix) + 1 -- +1 skips the "▕" glyph
    for i = 1, filled do
      add_hl(lineidx, base + i - 1, base + i, hl_fg(severity_color(i / width)))
    end
  end
  push("")

  -- 6) Palette swatches — solid color blocks, for previewing future accent
  --    colors without redefining highlight groups by hand each time.
  push("  6) Accent palette — 10 evenly-spaced hues, generated not hand-picked")
  do
    local prefix = "     "
    local n = 10
    local line = prefix .. string.rep("  ", n)
    local lineidx = push(line)
    local base = vim.fn.strchars(prefix)
    for i = 0, n - 1 do
      add_hl(lineidx, base + i * 2, base + i * 2 + 2, hl_bg(hsl_to_hex(i / n)))
    end
  end
  push("")

  -- 7) Rainbow hue-cycling text — every character its own animated color.
  push("  7) Hue-cycling text — per-character animated color")
  do
    local prefix = "     "
    local title = "N A I S   D A S H B O A R D"
    local line = prefix .. title
    local lineidx = push(line)
    local base = vim.fn.strchars(prefix)
    for i = 1, #title do
      if title:sub(i, i) ~= " " then
        local hue = (tick * 0.015 + i * 0.04) % 1
        add_hl(lineidx, base + i - 1, base + i, hl_fg(hsl_to_hex(hue)))
      end
    end
  end
  push("")

  push("  8) Toggle switch (static)")
  push("     ◉────────  OFF        ────────◉  ON")
  push("")

  -- 9) DB scan — cycling "active row" like an index scan sweeping a table.
  push("  9) DB scan — index scan animation (EXPLAIN-style)")
  do
    local rows = {
      { "1", "42", "paid", "120.00" },
      { "2", "17", "pending", "45.50" },
      { "3", "88", "paid", "300.00" },
      { "4", "56", "failed", "12.00" },
      { "5", "91", "paid", "88.25" },
    }
    push(string.format("     %-3s %-8s %-9s %-8s", "id", "user_id", "status", "amount"))
    push("     " .. string.rep("─", 32))
    local active = (math.floor(tick / 4) % #rows) + 1
    for i, r in ipairs(rows) do
      local line = string.format("     %-3s %-8s %-9s %-8s", r[1], r[2], r[3], r[4])
      local lineidx = push(line)
      if i == active then
        add_hl(lineidx, 0, vim.fn.strchars(line), hl_bg("#1e3a5f"))
      end
    end
    push("     Index Scan using idx_orders_status  (cost=0.29..8.31 rows=5)")
  end
  push("")

  -- 10) BPMN token flow — a token dot animates across node anchor points.
  push("  10) BPMN token flow (Flowable-style)")
  do
    local diagram = "     (Start) ──▶ [ Validate ] ──▶ <Gateway> ──▶ [ Approve ] ──▶ (End)"
    push(diagram)
    local nodes = { 8, 22, 38, 52, 68 }
    local pos = nodes[(math.floor(tick / 5) % #nodes) + 1]
    local token_line = string.rep(" ", pos) .. "●"
    local tlineidx = push(token_line)
    add_hl(tlineidx, pos, pos + 1, hl_fg("#f97316"))
  end
  push("")

  -- 11) Sequence diagram — one message pulses active at a time.
  push("  11) Sequence diagram — message passing")
  do
    local msg_lines = {
      "     Client    Gateway    AuthSvc     DB",
      "       |          |          |         |",
      "       │──POST /login───────▶│         |",
      "       |          │──validate()───────▶│",
      "       |          │◀──user row──────────│",
      "       │◀──200 OK────────────│         |",
    }
    local active = (math.floor(tick / 5) % 4) + 3
    for i, l in ipairs(msg_lines) do
      local lineidx = push(l)
      if i == active then
        add_hl(lineidx, 0, vim.fn.strchars(l), hl_fg("#38bdf8"))
      end
    end
  end
  push("")

  -- 12) Git commit graph — static, colored hashes/branch lanes.
  push("  12) Git commit graph (mini log)")
  do
    local rows = {
      { "*", "8f3a1c2", "feat: add token flow demo", "#f59e0b" },
      { "*", "4b9e7aa", "fix: gradient gauge severity math", "#f59e0b" },
      { "|\\", "", "", nil },
      { "| *", "1c2d3e4", "wip: bpmn diagram sketch", "#a78bfa" },
      { "* |", "9f0a1b2", "chore: bump nui.nvim", "#f59e0b" },
      { "|/", "", "", nil },
      { "*", "5566778", "init: control panel skeleton", "#f59e0b" },
    }
    for _, r in ipairs(rows) do
      local graph, hash, msg, color = r[1], r[2], r[3], r[4]
      if hash ~= "" then
        local line = string.format("     %-3s %-9s %s", graph, hash, msg)
        local lineidx = push(line)
        local prefix_w = vim.fn.strchars(string.format("     %-3s ", graph))
        add_hl(lineidx, prefix_w, prefix_w + #hash, hl_fg(color))
      else
        push("     " .. graph)
      end
    end
  end
  push("")

  -- 13) Java stack trace — "your code" frame stands out from framework noise.
  push("  13) Java exception (colored frames)")
  do
    local exc_line = "     java.lang.NullPointerException: Cannot invoke \"String.length()\""
    local lineidx = push(exc_line)
    add_hl(lineidx, 5, vim.fn.strchars(exc_line), hl_fg("#ef4444"))

    local frames = {
      { "at com.nais.auth.service.AuthService.validate(AuthService.java:42)", true },
      { "at com.nais.auth.controller.AuthController.login(AuthController.java:18)", false },
      { "at org.springframework.web.method.support.InvocableHandlerMethod.java:205", false },
      { "at org.springframework.web.servlet.DispatcherServlet.java:1089", false },
    }
    for _, f in ipairs(frames) do
      local text, mine = f[1], f[2]
      local line = "         " .. text
      local flineidx = push(line)
      if mine then
        add_hl(flineidx, 0, vim.fn.strchars(line), hl_bg("#3a2f00"))
        add_hl(flineidx, 0, vim.fn.strchars(line), hl_fg("#eab308"))
      else
        add_hl(flineidx, 0, vim.fn.strchars(line), hl_fg("#6b7280"))
      end
    end
    push("         ... 42 more")
  end
  push("")

  -- 14) JSON tree — real (tiny) tokenizer, not hardcoded columns: finds
  --     every quoted span, number, and boolean and colors it by kind.
  push("  14) JSON tree (syntax-colored via a real tokenizer)")
  do
    local KEY, STR, NUM, BOOL = "#60a5fa", "#4ade80", "#fb923c", "#c084fc"
    local function highlight_json_line(lineidx, line)
      local pos = 1
      while true do
        local s, e = line:find('"[^"]*"', pos)
        if not s then
          break
        end
        local after_colon = line:sub(e + 1):match("^%s*:")
        add_hl(lineidx, s - 1, e, hl_fg(after_colon and KEY or STR))
        pos = e + 1
      end
      for s in line:gmatch("()%d+") do
        local _, e2 = line:find("%d+", s)
        add_hl(lineidx, s - 1, e2, hl_fg(NUM))
      end
      for s, e in line:gmatch("()true()") do
        add_hl(lineidx, s - 1, e - 1, hl_fg(BOOL))
      end
      for s, e in line:gmatch("()false()") do
        add_hl(lineidx, s - 1, e - 1, hl_fg(BOOL))
      end
    end

    local json_lines = {
      "     {",
      '       "service": "auth-service",',
      '       "status": "on",',
      '       "port": 8080,',
      '       "healthy": true,',
      '       "deps": ["postgres", "keycloak"]',
      "     }",
    }
    for _, line in ipairs(json_lines) do
      local lineidx = push(line)
      highlight_json_line(lineidx, line)
    end
  end
  push("")

  -- 15) Request waterfall — segmented multi-color timeline bar.
  push("  15) Request waterfall (gateway → auth-service)")
  do
    local phases = {
      { "DNS", 0, 2, "#60a5fa" },
      { "TCP", 2, 5, "#2dd4bf" },
      { "TLS", 5, 11, "#c084fc" },
      { "TTFB", 11, 34, "#fb923c" },
      { "DL", 34, 37, "#4ade80" },
    }
    for _, p in ipairs(phases) do
      local label, start_ms, end_ms, color = p[1], p[2], p[3], p[4]
      local prefix = string.format("     %-5s", label)
      local span = math.max(1, end_ms - start_ms)
      local line = prefix .. string.rep(" ", start_ms) .. string.rep("▇", span) .. "  " .. span .. "ms"
      local lineidx = push(line)
      local base = vim.fn.strchars(prefix) + start_ms
      add_hl(lineidx, base, base + span, hl_fg(color))
    end
  end
  push("")

  push("  q / <Esc> close this gallery")

  vim.bo[popup.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.bo[popup.bufnr].modifiable = false

  local ns = vim.api.nvim_create_namespace("nais_gallery")
  vim.api.nvim_buf_clear_namespace(popup.bufnr, ns, 0, -1)
  for i, line in ipairs(lines) do
    if line:match("^  %d%)") then
      vim.api.nvim_buf_add_highlight(popup.bufnr, ns, "Title", i - 1, 0, -1)
    end
  end
  for _, h in ipairs(hls) do
    local line_text = lines[h.line + 1]
    vim.api.nvim_buf_add_highlight(popup.bufnr, ns, h.group, h.line, byte_col(line_text, h.char_start), byte_col(line_text, h.char_end))
  end
end

local function close()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  if popup then
    pcall(function()
      popup:unmount()
    end)
    popup = nil
  end
end

function M.open()
  if popup and popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
    vim.api.nvim_set_current_win(popup.winid)
    return
  end

  popup = Popup({
    relative = "editor",
    position = "50%",
    size = { width = 76, height = "90%" },
    enter = true,
    focusable = true,
    zindex = 50,
    border = {
      style = "rounded",
      text = { top = "  Component Gallery (demo)  ", top_align = "center" },
    },
    buf_options = { modifiable = false, filetype = "naisgallery" },
    win_options = { winblend = 0, cursorline = false, wrap = false, list = false },
  })
  popup:mount()
  popup:map("n", "q", close, { noremap = true })
  popup:map("n", "<Esc>", close, { noremap = true })

  tick = 0
  render()
  timer = vim.uv.new_timer()
  timer:start(
    0,
    120,
    vim.schedule_wrap(function()
      render()
    end)
  )
end

return M
