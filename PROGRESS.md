# Progress

## Where things stand

Working plugin, public at github.com/blackhat-7/vellum.nvim. `:Vellum` opens the preview; it re-renders on every edit and follows the cursor. Keystroke cost: 0.23 ms for a README, ~6.7 ms median at 5,000 lines (`test/perf.lua`). Rendered: headings, paragraphs with bold/italic/strike/code/links/bare URLs/escapes/entities, lists, quotes, GitHub alerts, footnotes, tables, code with syntax colors, front matter, HTML blocks, `<details>` summaries (`▾`), images (block, or inline one row high for badges), mermaid diagrams.

Rendering is split by job: `render.lua` (blocks), `inline.lua` (inline text, wrap), `code.lua` (code panels, diagrams), `media.lua` (images). The renderer starts on `:Vellum`; the PNG cache is capped at 100 MB.

Verified by eye in kitty inside tmux. `nvim --clean -l test/run.lua`: 73 checks green.

## What's next

`PLAN.md` has no open tasks. Candidates: keystroke cost at 5,000 lines under 5 ms; a hint for terminals without kitty graphics.

## Gotchas

- **A setext underline can sit inside a list item** (`- a\n  b\n  -`), and a `block_continuation` can follow it. Never assume a heading's marker is its first or last child.
- **Footnote definitions are not a tree-sitter node.** Multi-word ones parse as paragraphs, one-word ones as `link_reference_definition`; both paths call `footnotes()`.
- **`node:start()` returns three values.** As a last call argument they spill into later parameters; wrap in parens.
- **The inline parser has anonymous punctuation children** (`/`, `:`). Walk only named nodes, or text reaches `push` in fragments.
- **npm may block puppeteer's postinstall** (`allowScripts`), so `build.lua` downloads the headless shell explicitly.
- **tmux needs `set -g allow-passthrough on`** for kitty graphics, and RGB in `terminal-features` for the attached TERM. Over ssh, `COLORTERM` is not forwarded, so tmux does not guess RGB.
- **Screenshot harness can mimic ssh:** kitty `-o term=xterm-256color` and `env -u COLORTERM` before tmux.
- **Kitty placeholders need `termguicolors`**: the image id is the fg color.
- **Screenshot checks:** a headless Hyprland output (`hyprctl output create headless`) plus `grim -o` captures kitty without covering the real screen. Launch kitty with `-o confirm_os_window_close=0`.
- **`vim.fn.tempname()` + `XDG_CACHE_HOME`:** `test/run.lua` sets a private cache before requiring the plugin, because `browser.lua` prunes the cache on load.
