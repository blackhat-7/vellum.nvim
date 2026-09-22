# Decisions

Why things are the way they are. Append only. One entry, one to three lines.

- **Preview is a real buffer, rendered in Lua.** (2026-09-22) No external process for text: tree-sitter's bundled markdown parsers are fast and always there. Extmarks carry all styling.
- **Mermaid runs in a real headless browser, not a fake DOM.** (2026-09-22) happy-dom + resvg (tried first, from mdtui) mis-measures text: flowcharts overlap and class/gantt diagrams fail. Puppeteer's `chrome-headless-shell` renders exactly like GitHub. One process stays alive; PNGs are cached on disk by hash of theme + code.
- **Images use kitty Unicode placeholders.** (2026-09-22) The image is sent once; the buffer holds placeholder text colored with the image id. It scrolls, clips and works in tmux with no redraw code. Requires kitty or Ghostty; elsewhere diagrams show as code.
- **Colors derive from the active colorscheme.** (2026-09-22) Headings use Function/Statement/String/Type/Constant/Special colors; tints are blends toward Normal bg. Diagrams get matching mermaid themeVariables.
- **Blocks are cached by (type, width, depth, source text).** (2026-09-22) A keystroke re-renders only the changed block. Output that is still pending (a diagram being rendered) bumps `volatile` and is never cached.
- **Requires Neovim 0.12.** (2026-09-22) `nvim_ui_send` is the clean way to send graphics escapes from the server; no compatibility layer for older versions.
- **Diagram size targets terminal text size.** (2026-09-22) Scale = cell height / 24 per CSS px, so 16px diagram text lands near the terminal font. Capped at the content width.
