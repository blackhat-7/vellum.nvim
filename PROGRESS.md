# Progress

## Where things stand

Working plugin, public at github.com/blackhat-7/vellum.nvim. `:Vellum` opens the preview; it re-renders on every edit and follows the cursor; scrolling the preview scrolls the source. Keystroke cost: 0.23 ms for a README, ~6.8 ms median at 5,000 lines (`test/perf.lua`). Rendered: headings, paragraphs with bold/italic/strike/code/links/bare URLs/escapes/entities, lists, quotes, GitHub alerts, footnotes, tables, code with syntax colors, front matter, HTML blocks, `<details>` summaries (`▾`), images (block, or inline one row high for badges), mermaid diagrams, math.

Math: inline `$…$` becomes Unicode text (`latex.lua`); `$$…$$` and ```` ```math ```` become KaTeX pictures through the same headless browser as mermaid, with the text form while rendering or without kitty graphics. `$5 and $10` stays text.

Rendering is split by job: `render.lua` (blocks), `inline.lua` (inline text, wrap), `code.lua` (code panels, diagrams), `media.lua` (images), `latex.lua` (math). The renderer starts on `:Vellum`; the PNG cache is capped at 100 MB.

Resizing the pane stays smooth. Math verified by eye in kitty inside tmux. `nvim --clean -l test/run.lua`: 108 checks green.

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
- **Harness: start nvim after kitty attaches to tmux.** Before a client attaches, tmux reports no RGB and images are disabled.
- **Screenshot checks:** a headless Hyprland output (`hyprctl output create headless`) plus `grim -o` captures kitty without covering the real screen. Launch kitty with `-o confirm_os_window_close=0`.
- **`vim.fn.tempname()` + `XDG_CACHE_HOME`:** `test/run.lua` sets a private cache before requiring the plugin, because `browser.lua` prunes the cache on load.
- **Recording video:** `wf-recorder` is broken here (libavutil). Pipe `grim -g <window> -t ppm -` in a loop into `ffmpeg -f image2pipe -use_wallclock_as_timestamps 1`; drive nvim with `tmux send-keys`.
- **Tree-sitter's `latex_block` swallows markup:** `$5 [a](b) $10` is one node; `inline.lua` re-parses after a rejected `$`. Markup spanning the second `$` (`**$10**`) still shows raw.
- **Renderer page must stay in standards mode** (`<!DOCTYPE html>`) for KaTeX; mermaid SVGs are `display:block` there to keep diagram sizes unchanged.
- **Measuring redraw cost:** the UI is its own `nvim` process (the server is `nvim --embed`); its `/proc/<pid>/io` `wchar` is bytes sent to the terminal. `pgrep -f` also matches the tmux/shell wrappers.
- **README shots come from `docs/demo.md`.** Launch kitty with `-o background_image=none -o background_opacity=1` (transparent schemes show the wallpaper). The compositor pointer lands on the headless output; patch it out.
- **`WinScrolled` fires in the current window for any window that scrolled** (a mouse wheel over the preview). Check `v:event` for the window. `nvim -l` never fires it; test under `-c luafile` with `vim.defer_fn`.
- **Two-way scroll sync loops unless each side ignores its own echo:** `sync` records `S.top`, `follow` records `S.view`. The preview needs `scrolloff=0`, or it shifts the topline `sync` set.
- **The preview must never scroll sideways.** Image rows carry kitty diacritics on their first cell only; shift it off and every row shows row 0. `scrolled()` pins `leftcol` to 0. Headless never fires `WinScrolled`; check it in tmux.
