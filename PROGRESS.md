# Progress

## Where things stand

Working plugin, public at github.com/blackhat-7/vellum.nvim. `:Vellum` opens the preview; it re-renders on every edit and follows the cursor. Keystroke cost: 0.23 ms for a README, 6.1 ms median at 5,000 lines (`test/perf.lua`). Rendered: headings (H1 band + gradient edge, H2 rule), paragraphs with bold/italic/strike/code/links/bare URLs/escapes/entities, lists (nested, ordered, tasks, loose), quotes, GitHub alerts, tables (alignment, wrapping, zebra), code with tree-sitter syntax colors, front matter, HTML blocks (tags stripped, comments hidden), local PNG images, mermaid diagrams as images.

Verified by eye in kitty 0.48.2 inside tmux 3.7c. `nvim --clean -l test/run.lua`: 30 checks green.

## What's next

Top of `PLAN.md`: install from GitHub with lazy.nvim in a clean config.

## Gotchas

- **`node:start()` returns three values.** As a last call argument they spill into later parameters; wrap in parens.
- **npm may block puppeteer's postinstall** (`allowScripts`), so `build.lua` downloads the headless shell explicitly.
- **tmux needs `set -g allow-passthrough on`** for kitty graphics.
- **Kitty placeholders need `termguicolors`**: the image id is the fg color.
- **Screenshot checks:** a headless Hyprland output (`hyprctl output create headless`) plus `grim -o` captures kitty without covering the real screen. Launch kitty with `-o confirm_os_window_close=0`.
