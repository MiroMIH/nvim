-- natural sort so V2 comes before V10 instead of lexicographic order
local function natural_cmp(a, b)
  if a.type ~= b.type then
    return a.type < b.type
  end
  local a_str = vim.fn.fnamemodify(a.path, ":t"):lower()
  local b_str = vim.fn.fnamemodify(b.path, ":t"):lower()
  local ia, ib = 1, 1
  while ia <= #a_str and ib <= #b_str do
    local ca, cb = a_str:sub(ia, ia), b_str:sub(ib, ib)
    if ca:match("%d") and cb:match("%d") then
      local na = a_str:match("^%d+", ia)
      local nb = b_str:match("^%d+", ib)
      local numa, numb = tonumber(na), tonumber(nb)
      if numa ~= numb then
        return numa < numb
      end
      ia = ia + #na
      ib = ib + #nb
    else
      if ca ~= cb then
        return ca < cb
      end
      ia = ia + 1
      ib = ib + 1
    end
  end
  return #a_str < #b_str
end

-- build icon glyphs from their Nerd Font codepoints (typing the raw glyph
-- directly is unreliable across editors/terminals and can silently save as empty)
local nf = function(codepoint)
  return vim.fn.nr2char(codepoint)
end

-- Spring Boot layer -> {icon, highlight group, color} for folders matched by exact name
local folder_style = {
  controller = { icon = nf(0xf0ac), hl = "NeoTreeSpringController", color = "#61AFEF" }, -- fa-globe, blue: entry point
  service = { icon = nf(0xf085), hl = "NeoTreeSpringService", color = "#E5C07B" }, -- fa-cogs, orange: business logic
  repository = { icon = nf(0xf1c0), hl = "NeoTreeSpringRepository", color = "#C678DD" }, -- fa-database, purple: data access
  entity = { icon = nf(0xf1b2), hl = "NeoTreeSpringEntity", color = "#56B6C2" }, -- fa-cube, teal: domain objects
  model = { icon = nf(0xf1b2), hl = "NeoTreeSpringEntity", color = "#56B6C2" },
  dto = { icon = nf(0xf0e0), hl = "NeoTreeSpringDto", color = "#61E0E0" }, -- fa-envelope, cyan: wire format
  mapper = { icon = nf(0xf074), hl = "NeoTreeSpringMapper", color = "#ABB2BF" }, -- fa-random, gray: conversion glue
  config = { icon = nf(0xf0ad), hl = "NeoTreeSpringConfig", color = "#E06C75" }, -- fa-wrench, red: high blast radius
  exception = { icon = nf(0xf071), hl = "NeoTreeSpringException", color = "#E06C75" }, -- fa-exclamation-triangle
  security = { icon = nf(0xf023), hl = "NeoTreeSpringSecurity", color = "#D19A66" }, -- fa-lock
  migration = { icon = nf(0xf1da), hl = "NeoTreeSpringMigration", color = "#98C379" }, -- fa-history, green: ordered/append-only
  seed = { icon = nf(0xf06c), hl = "NeoTreeSpringSeed", color = "#7FB77E" }, -- fa-leaf
  test = { icon = nf(0xf0c3), hl = "NeoTreeSpringTest", color = "#5C6370" }, -- fa-flask, dimmed
}

-- Spring Boot role, matched by filename suffix (for "package by feature" repos
-- where there's no dedicated controller/service/repository folder at all).
-- Ordered longest-suffix-first so "Specifications" doesn't get caught by nothing else.
local file_suffix_style = {
  { suffix = "Specifications", icon = nf(0xf1c0), hl = "NeoTreeSpringRepository" },
  { suffix = "Repository", icon = nf(0xf1c0), hl = "NeoTreeSpringRepository" },
  { suffix = "Controller", icon = nf(0xf0ac), hl = "NeoTreeSpringController" },
  { suffix = "Service", icon = nf(0xf085), hl = "NeoTreeSpringService" },
  { suffix = "Mapper", icon = nf(0xf074), hl = "NeoTreeSpringMapper" },
  { suffix = "Configuration", icon = nf(0xf0ad), hl = "NeoTreeSpringConfig" },
  { suffix = "Config", icon = nf(0xf0ad), hl = "NeoTreeSpringConfig" },
  { suffix = "Exception", icon = nf(0xf071), hl = "NeoTreeSpringException" },
  { suffix = "Application", icon = nf(0xf135), hl = "NeoTreeSpringApplication" }, -- fa-rocket: Spring Boot main class
  { suffix = "Request", icon = nf(0xf061), hl = "NeoTreeSpringRequest" }, -- fa-arrow-right: incoming payload
  { suffix = "Response", icon = nf(0xf060), hl = "NeoTreeSpringResponse" }, -- fa-arrow-left: outgoing payload
}

-- role words that must never be used as a domain-color group key: they're
-- architecture labels shared across unrelated domains (e.g. every *Controller
-- ends in "Controller"), already represented by the icon shape, not the color
local role_words = { Impl = true }
for _, style in ipairs(file_suffix_style) do
  role_words[style.suffix] = true
end

local function apply_folder_highlights()
  for _, style in pairs(folder_style) do
    vim.api.nvim_set_hl(0, style.hl, { fg = style.color, default = false })
  end
  vim.api.nvim_set_hl(0, "NeoTreeSpringApplication", { fg = "#98FB98", default = false }) -- fa-rocket: Spring Boot main class
  vim.api.nvim_set_hl(0, "NeoTreeSpringRequest", { fg = "#61AFEF", default = false }) -- fa-arrow-right: incoming
  vim.api.nvim_set_hl(0, "NeoTreeSpringResponse", { fg = "#98C379", default = false }) -- fa-arrow-left: outgoing
end

apply_folder_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  desc = "Reapply neo-tree Spring Boot folder highlights after theme reload",
  callback = apply_folder_highlights,
})

-- ===== auto domain-color: files sharing a name "chunk" with a sibling get the =====
-- ===== same icon color, hashed from that shared chunk (independent of role)  =====
local MIN_GROUP_KEY_LEN = 3
local sibling_names_cache = {} -- dir path -> { basenames (without extension), keyed by extension }

local function list_sibling_stems(dir, ext)
  local cache_key = dir .. "|" .. ext
  local cached = sibling_names_cache[cache_key]
  if cached then
    return cached
  end
  local stems = {}
  local fs = vim.loop.fs_scandir(dir)
  if fs then
    while true do
      local name, typ = vim.loop.fs_scandir_next(fs)
      if not name then
        break
      end
      if typ == "file" and name:match("%." .. ext .. "$") then
        table.insert(stems, vim.fn.fnamemodify(name, ":r"))
      end
    end
  end
  sibling_names_cache[cache_key] = stems
  return stems
end

-- raw longest common prefix, then trimmed back to the last clean boundary
-- (underscore, or a lower->UPPER PascalCase edge) so we don't cut mid-word
local function longest_common_prefix(a, b)
  local n = math.min(#a, #b)
  local len = 0
  while len < n and a:sub(len + 1, len + 1) == b:sub(len + 1, len + 1) do
    len = len + 1
  end
  return len
end

local function longest_common_suffix(a, b)
  local la, lb = #a, #b
  local n = math.min(la, lb)
  local len = 0
  while len < n and a:sub(la - len, la - len) == b:sub(lb - len, lb - len) do
    len = len + 1
  end
  return len
end

local function is_boundary(stem, i)
  -- true if position i starts a clean "word": string start, right after '_',
  -- or a PascalCase capital following a lowercase letter
  if i <= 1 then
    return true
  end
  local c, prev = stem:sub(i, i), stem:sub(i - 1, i - 1)
  return prev == "_" or (c:match("%u") ~= nil and prev:match("%l") ~= nil)
end

-- trims a matched *prefix* of length `len` back to the last clean boundary,
-- but only if it actually landed mid-word: if the mismatch point is itself a
-- boundary (e.g. "HcnStock" before "Controller"/"Service"), the match is
-- already clean and must be kept whole, not chopped back to "Hcn"
local function trim_prefix_to_boundary(stem, len)
  if len == #stem or is_boundary(stem, len + 1) then
    return (stem:sub(1, len):gsub("_$", ""))
  end
  local best = 0
  for i = 2, len do
    if is_boundary(stem, i) then
      best = i - 1
    end
  end
  if best == 0 and len <= MIN_GROUP_KEY_LEN + 2 then
    return "" -- nothing meaningful (e.g. "V1" from "V10"/"V11")
  end
  return stem:sub(1, best > 0 and best or len):gsub("_$", "")
end

-- trims a matched *suffix* of length `len` forward to the next clean boundary
local function trim_suffix_to_boundary(stem, len)
  local start_idx = #stem - len + 1
  for i = start_idx, #stem do
    if is_boundary(stem, i) then
      return stem:sub(i)
    end
  end
  return "" -- the whole matched suffix is mid-word garbage
end

-- looks for the strongest shared naming chunk among same-extension siblings,
-- checking both a shared prefix (e.g. "HcnStock*") and a shared suffix
-- (e.g. "*Row", "*Response") and picking whichever is the cleaner/longer match
local function domain_group_key(node)
  local dir = vim.fn.fnamemodify(node.path, ":h")
  local ext = vim.fn.fnamemodify(node.name, ":e")
  if ext == "" then
    return nil
  end
  local stem = vim.fn.fnamemodify(node.name, ":r")
  local stems = list_sibling_stems(dir, ext)

  local best_prefix_len, best_suffix_len = 0, 0
  for _, sibling in ipairs(stems) do
    if sibling ~= stem then
      best_prefix_len = math.max(best_prefix_len, longest_common_prefix(stem, sibling))
      best_suffix_len = math.max(best_suffix_len, longest_common_suffix(stem, sibling))
    end
  end

  local prefix_key = best_prefix_len >= MIN_GROUP_KEY_LEN and trim_prefix_to_boundary(stem, best_prefix_len) or ""
  local suffix_key = best_suffix_len >= MIN_GROUP_KEY_LEN and trim_suffix_to_boundary(stem, best_suffix_len) or ""

  -- a bare architecture role (Controller/Service/Repository/...) is not a domain
  -- signal: it's already shown by the icon shape, so never color by it alone
  if role_words[suffix_key] then
    suffix_key = ""
  end
  if role_words[prefix_key] then
    prefix_key = ""
  end

  if #suffix_key >= MIN_GROUP_KEY_LEN and #suffix_key >= #prefix_key then
    return suffix_key
  elseif #prefix_key >= MIN_GROUP_KEY_LEN then
    return prefix_key
  end
  return nil
end

-- deterministic hash -> pleasant, distinguishable dark-theme-friendly color
local function hash_to_hex(str)
  local hash = 5381
  for i = 1, #str do
    hash = (hash * 33 + str:byte(i)) % 0xFFFFFF
  end
  local hue = hash % 360
  -- HSL(hue, 65%, 65%) -> hex, tuned to stay readable on dark backgrounds
  local s, l = 0.65, 0.65
  local c = (1 - math.abs(2 * l - 1)) * s
  local x = c * (1 - math.abs((hue / 60) % 2 - 1))
  local m = l - c / 2
  local r, g, b
  if hue < 60 then
    r, g, b = c, x, 0
  elseif hue < 120 then
    r, g, b = x, c, 0
  elseif hue < 180 then
    r, g, b = 0, c, x
  elseif hue < 240 then
    r, g, b = 0, x, c
  elseif hue < 300 then
    r, g, b = x, 0, c
  else
    r, g, b = c, 0, x
  end
  local function to255(v)
    return math.floor((v + m) * 255 + 0.5)
  end
  return string.format("#%02x%02x%02x", to255(r), to255(g), to255(b))
end

local domain_hl_cache = {} -- group key -> highlight group name

local function domain_group_highlight(key)
  local hl = domain_hl_cache[key]
  if not hl then
    hl = "NeoTreeAutoGroup_" .. key:gsub("%W", "_")
    vim.api.nvim_set_hl(0, hl, { fg = hash_to_hex(key), default = false })
    domain_hl_cache[key] = hl
  end
  return hl
end

-- ===== auto feature-folder color: every immediate subfolder of the app's root =====
-- ===== package (the dir holding *Application.java) gets a generic "package"   =====
-- ===== icon, colored by hashing its own name -- no manual list required       =====
local FEATURE_FOLDER_ICON = nf(0xf1b3) -- fa-cubes
local app_root_cache = {} -- dir path -> boolean

local function is_app_root_dir(dir)
  if app_root_cache[dir] == nil then
    local found = false
    local fs = vim.loop.fs_scandir(dir)
    if fs then
      while true do
        local name, typ = vim.loop.fs_scandir_next(fs)
        if not name then
          break
        end
        if typ == "file" and name:match("Application%.java$") then
          found = true
          break
        end
      end
    end
    app_root_cache[dir] = found
  end
  return app_root_cache[dir]
end

local function spring_icon_provider(icon, node, state)
  -- default devicons behavior for files/terminals first
  if node.type == "file" or node.type == "terminal" then
    local success, web_devicons = pcall(require, "nvim-web-devicons")
    local name = node.type == "terminal" and "terminal" or node.name
    if success then
      local devicon, hl = web_devicons.get_icon(name)
      icon.text = devicon or icon.text
      icon.highlight = hl or icon.highlight
    end
  end

  if node.type == "directory" then
    local style = folder_style[node.name:lower()]
    if style and style.icon then
      icon.text = style.icon
      icon.highlight = style.hl
    else
      local parent_dir = vim.fn.fnamemodify(node.path, ":h")
      if is_app_root_dir(parent_dir) then
        icon.text = FEATURE_FOLDER_ICON
        icon.highlight = domain_group_highlight(node.name)
      end
    end
  elseif node.type == "file" then
    -- treat "*Impl.ext" as its base role (ServiceImpl -> Service, RepositoryImpl -> Repository, ...)
    local role_match_name = node.name:gsub("Impl%.(%w+)$", ".%1")
    for _, style in ipairs(file_suffix_style) do
      if role_match_name:match(style.suffix .. "%.%w+$") then
        icon.text = style.icon
        icon.highlight = style.hl
        break
      end
    end

    -- domain-color override: same detected name-chunk => same color, regardless of role
    local key = domain_group_key(node)
    if key then
      icon.highlight = domain_group_highlight(key)
    end
  end

  return icon
end

return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    window = {
      width = 25,
    },
    sort_function = natural_cmp,
    default_component_configs = {
      icon = {
        provider = spring_icon_provider,
      },
    },
  },
}
