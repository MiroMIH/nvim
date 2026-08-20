# Neovim Cheatsheet

Personal reference — shortcuts, combos, and workflows built up over time.
Update this file whenever a new shortcut clicks, then commit it.

---

## DB (vim-dadbod-ui)

| Key / Command | Mode | What it does |
|---|---|---|
| `<leader>db` | Normal | Toggle DB UI sidebar |
| `<leader>dr` | Normal | Run entire SQL buffer |
| `<leader>dr` | Visual | Run selected SQL only |
| `r` (in sidebar) | Normal | Open new query buffer for selected DB |
| `o` (in sidebar) | Normal | Open/expand item |
| `R` (in sidebar) | Normal | Refresh DB tree |
| `q` (in sidebar) | Normal | Close sidebar |

---

## Go Projects (project.nvim)

| Key / Command | Mode | What it does |
|---|---|---|
| `<leader>fp` | Normal | Open Telescope project switcher (recently opened Go/git projects) |
| `:GoNewProject <path>` | Command | Scaffold a new Go project: mkdir, `go mod init`, starter `main.go`, cd + open |

_Detection: any dir with `go.mod`, `.git`, or `Makefile` is auto-recognized as a project root._

New Go projects live under `~/Projects/LearningGo/`, e.g. `:GoNewProject ~/Projects/LearningGo/my-new-app`.

---

## Navigation

_Add shortcuts here as you learn them._

---

## LSP / Code

_Add shortcuts here as you learn them._

---

## Git (vim-fugitive / gitsigns)

_Add shortcuts here as you learn them._

---

## General Tricks

_Add combos and workflows here as you discover them._
