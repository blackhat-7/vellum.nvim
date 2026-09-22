# Vellum — agent guide

**Every session, read these four files first, in order. They are short on purpose.**
`AGENTS.md` (this file) · `PROGRESS.md` (where things stand) · `PLAN.md` (what to do next) · `DECISIONS.md` (why things are the way they are).

## What this is

A Neovim plugin: `:Vellum` opens a live, beautifully rendered GitHub-markdown preview in a split beside the buffer you edit. Mermaid diagrams render as real images. Installed with lazy.nvim.

- `lua/vellum/render.lua` — markdown (tree-sitter) → styled lines + extmarks + scroll anchors. Caches per block.
- `lua/vellum/init.lua` — preview window, autocmds, scroll sync.
- `lua/vellum/theme.lua` — palette derived from the active colorscheme.
- `lua/vellum/image.lua` — kitty graphics via Unicode placeholders (works through tmux).
- `lua/vellum/browser.lua` + `render/browser.mjs` — one long-lived headless Chrome turns diagrams and non-PNG images into cached PNGs.
- `build.lua` — lazy.nvim runs it on install: `npm ci` + headless shell download.

Lua for Neovim ≥ 0.12. Node ≥ 20 for the renderer only.

## Commands

```sh
nvim --clean -l test/run.lua                           # assertion tests, headless
nvim --clean -l test/perf.lua                          # keystroke cost on 5,000 lines
nvim --clean -l test/sweep.lua paths.txt out.tsv       # crash/overflow/missing-text sweep over real files
nvim --clean --headless -c 'luafile test/dump.lua' -c 'qa!'   # print the rendered sample
nvim --clean -u test/init.lua test/sample.md -c Vellum # try it by hand
(cd render && npm ci && npx puppeteer browsers install chrome-headless-shell)  # build renderer
```

## Session routine

1. **Orient.** Read the four files. Run `git log --oneline -5`, then `nvim --clean -l test/run.lua`. Confirm reality matches `PROGRESS.md`. Say so if it does not.
2. **Pick one task** — the top unchecked line in `PLAN.md`. Mark it `[~]`.
3. **Do only that task.** Read the code before changing it.
4. **Verify** with the task's own done-check plus `nvim --clean -l test/run.lua`. Visual changes need a look in a real kitty (+ tmux).
5. **Leave the trail.** Tick `[x]` in `PLAN.md`. Rewrite `PROGRESS.md`. Append to `DECISIONS.md` if you chose something a later reader might undo. Commit saying what and why, then `git push`.
6. **Stop.** Tests green, nothing half-done.

**A task is not finished until step 5 is finished.** Report honestly at step 4: a failing check gets written down, never worked around.

## Project rules

- **Instant.** Typing must never wait on the preview. Unchanged blocks come from the cache; diagrams render off-thread.
- **The preview never lies.** Every source construct renders, or falls back to its dimmed source text. Nothing silently vanishes except HTML comments and link definitions.
- **Colors come from the colorscheme.** Never hardcode a palette in `render.lua`; add a group in `theme.lua`.
- **Keep it small.** A file past ~500 lines gets split. No new dependency without a DECISIONS.md entry.
- **Never weaken a test, type or check to get green.** Changing an assertion needs a stated reason in the commit.
- **This repository is public.** No credentials, no private paths, no personal data.

## Writing rules

- **Write for someone who knows nothing.** Name files, flags and commands.
- **Plain words, short sentences, one idea each.**
- **Rewrite `PROGRESS.md`, never append to it.** It is a handoff note, not a log.
- **Size caps:** `AGENTS.md` ≤ 80 lines · `PROGRESS.md` ≤ 40 lines · `PLAN.md` one line per task · `DECISIONS.md` ≤ 3 lines per entry.
- **Record gotchas, not narrative.** One line each, in `PROGRESS.md`.
- Code comments say **why**, never what.
