# Progress

## Where things stand

Public at github.com/blackhat-7/vellum.nvim, last release v0.3.0; `main` has unreleased work (below). `:Vellum` opens the preview (or its own tab with `setup({ tab = true })`); it re-renders on every edit, follows the cursor, and scrolling it scrolls the source. `<CR>` on an image zooms it (`zoom.lua`); `gx`/`<CR>` follows links (`links.lua`). `:Vellum export` writes PDF or HTML. `:Vellum build` installs the renderer for any plugin manager (`build.lua`; refuses a read-only Nix install). `:checkhealth vellum` renders a mermaid and a D2 test diagram. Options: `max_width`, `max_pixels`, `tab`, `split`, `size`, `auto_open`; bad ones warn; users' `Vellum*` colors win. Keystroke cost ~2.3 ms median at 5,000 lines (`test/perf.lua`), same for `.mdx`.

Unreleased on `main`: `:Vellum build` (#3), MDX (#4), `max_pixels` (joaoptpsa), D2 (issue #2). D2 renders with the user's `d2` command when installed, else in node (`@terrastruct/d2`, WebAssembly, loaded on the first D2 block); either way the same Chrome shoots it; colors from the colorscheme; local and URL icons; export too. `test/d2.md` holds showcase-sized D2 diagrams for visual checks.

Rendering is split by job: `render.lua` (blocks), `inline.lua` (inline text, wrap), `code.lua` (code panels, diagrams), `media.lua` (images), `latex.lua` (math), `mdx.lua` (MDX). The renderer starts on `:Vellum`, in `render/`; the PNG cache is capped at 100 MB. Nix: `flake.nix` + `nix/package.nix`, with a browser (chromium on Linux, a pinned headless shell on aarch64-darwin); checked on aarch64-darwin, aarch64-linux and x86_64-linux. `nvim --clean -l test/run.lua`: 195 checks green.

## What's next

Release the unreleased work. Candidates: vimdoc + CI; WezTerm once wezterm#7924 ships; Graphviz via viz.js.

## Gotchas

- **A setext underline can sit inside a list item** (`- a\n  b\n  -`), and a `block_continuation` can follow it. Never assume a heading's marker is its first or last child.
- **Footnote definitions are not a tree-sitter node.** Multi-word ones parse as paragraphs, one-word ones as `link_reference_definition`; both paths call `footnotes()`.
- **`node:start()` returns three values.** As a last call argument they spill into later parameters; wrap in parens.
- **The inline parser has anonymous punctuation children** (`/`, `:`). Walk only named nodes, or text reaches `push` in fragments.
- **Puppeteer never downloads a browser at launch**; it throws `Could not find chrome-headless-shell`. Its config is read from the cwd, so `browser.lua` starts it in `render/`. Bumping puppeteer? Update the macOS headless shell `version` and `hash` in `nix/package.nix` to match.
- **npm may block puppeteer's postinstall** (`allowScripts`), so `build.lua` downloads the headless shell explicitly.
- **tmux needs `set -g allow-passthrough on`** for kitty graphics, and RGB in `terminal-features` for the attached TERM. Over ssh, `COLORTERM` is not forwarded, so tmux does not guess RGB.
- **Kitty placeholders need `termguicolors`**: the image id is the fg color.
- **Screenshot checks:** a headless Hyprland output (`hyprctl output create headless`) plus `grim -o` captures kitty without covering the real screen. Launch kitty with `-o confirm_os_window_close=0`.
- **`vim.fn.tempname()` + `XDG_CACHE_HOME`:** `test/run.lua` sets a private cache before requiring the plugin, because `browser.lua` prunes the cache on load.
- **Tree-sitter's `latex_block` swallows markup:** `$5 [a](b) $10` is one node; `inline.lua` re-parses after a rejected `$`. Markup spanning the second `$` (`**$10**`) still shows raw.
- **Renderer page must stay in standards mode** (`<!DOCTYPE html>`) for KaTeX; mermaid SVGs are `display:block` there to keep diagram sizes unchanged.
- **README shots come from `docs/demo.md`; the demo video from `docs/showcase.md`.** Launch kitty with `-o background_image=none -o background_opacity=1 -o cursor_trail=0` (transparent schemes show the wallpaper; the cursor trail draws wedges in video). The compositor pointer lands on the headless output; patch it out.
- **`WinScrolled` fires in the current window for any window that scrolled** (a mouse wheel over the preview). Check `v:event` for the window. `nvim -l` never fires it; test under `-c luafile` with `vim.defer_fn`.
- **Two-way scroll sync loops unless each side ignores its own echo:** `sync` records `S.top`, `follow` records `S.view`. The preview needs `scrolloff=0`, or it shifts the topline `sync` set.
- **The preview must never scroll sideways.** Image rows carry kitty diacritics on their first cell only; shift it off and every row shows row 0. `scrolled()` pins `leftcol` to 0. Headless never fires `WinScrolled`; check it in tmux.
- **Kitty ignores the source rectangle (`x,y,w,h`) on placeholder placements.** The zoom viewer crops by naming cells instead, so zoom stops where the image reaches 297 cells on a side.
- **tmux can drop a kitty placement command under a burst of redraws** (fast wheel zoom). The text is right but the picture keeps an old size. The zoom viewer re-sends its placement 100 ms after the last event.
- **herdr drops kitty images above about 5.9 MP without a word.** `max_pixels = 5.5e6` lowers big renders' scale under it. Chrome's screenshots carry no pHYs; the renderer adds one with the scale, read by `image.png_density()`.
- **Hyprland 0.56 takes Lua:** `hyprctl eval "hl.window_rule({ match = { class = 'x' }, workspace = 'name:t silent' })"`, `hyprctl dispatch "hl.dsp.window.move({ workspace = '11', window = 'address:…', follow = false })"`; `keyword` is refused. A headless output shows only its active workspace.
- **D2 lays text out with exact glyph widths;** Chrome on Linux rounds them unless `--font-render-hinting=none`. Compare PNG sizes across machines to catch it.
