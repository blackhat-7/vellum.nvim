# Decisions

Why things are the way they are. Append only. One entry, one to three lines.

- **Preview is a real buffer, rendered in Lua.** (2026-09-22) No external process for text: tree-sitter's bundled markdown parsers are fast and always there. Extmarks carry all styling.
- **Mermaid runs in a real headless browser, not a fake DOM.** (2026-09-22) happy-dom + resvg (tried first, from mdtui) mis-measures text: flowcharts overlap and class/gantt diagrams fail. Puppeteer's `chrome-headless-shell` renders exactly like GitHub. One process stays alive; PNGs are cached on disk by hash of theme + code.
- **Images use kitty Unicode placeholders.** (2026-09-22) The image is sent once; the buffer holds placeholder text colored with the image id. It scrolls, clips and works in tmux with no redraw code. Requires kitty or Ghostty; elsewhere diagrams show as code.
- **PNG bytes are sent inline, in 4 KB chunks, never as a file path (`t=f`).** (2026-09-23) Over ssh + tmux the terminal is on another machine and cannot read our cache; images silently never appeared.
- **Under tmux, check the client has RGB before showing images.** (2026-09-23) The placeholder's 24-bit color is the image id; tmux downgrades it to 256 colors unless `terminal-features` says RGB (ssh drops `COLORTERM`). The diagram panel then says the exact tmux.conf line.
- **Wide tables and wide diagrams scroll sideways rather than shrink past readable.** (2026-09-23) Found by sweeping real files: a 19-column table split words mid-word, an 8992px flowchart shrank to unreadable text. Tables stop shrinking at their longest word; images stop at 75% of natural size. Every placeholder cell carries its column, so a scrolled image stays aligned.
- **Low-contrast node labels are recolored.** (2026-09-23) `classDef` fills written for GitHub's light page leave light-on-light text on a dark theme; labels under 3:1 contrast switch to dark or light ink.
- **Colors derive from the active colorscheme.** (2026-09-22) Headings use Function/Statement/String/Type/Constant/Special colors; tints are blends toward Normal bg. Diagrams get matching mermaid themeVariables.
- **Blocks are cached by (type, width, depth, source text).** (2026-09-22) A keystroke re-renders only the changed block. Output that is still pending (a diagram being rendered) bumps `volatile` and is never cached.
- **Requires Neovim 0.12.** (2026-09-22) `nvim_ui_send` is the clean way to send graphics escapes from the server; no compatibility layer for older versions.
- **Diagram size targets terminal text size.** (2026-09-22) Scale = cell height / 24 per CSS px, so 16px diagram text lands near the terminal font. Capped at the content width.
- **Highlights go through a decoration provider, not stored extmarks.** (2026-09-22) Setting 15k extmarks per keystroke cost 9.6 ms on a 5,000-line doc; ephemeral marks on drawn lines cost nothing. Flattened lines are memoized on the cached line tables (`line.flat`).
- **Remote images are fetched by the headless browser and re-fetched daily.** (2026-09-23) GitHub shows them too; badges and screenshots are common in READMEs. The cache key is URL + date; local files key on mtime + size.
- **Gantt defaults differ from GitHub: `axisFormat: '%b %d'`, 15px labels.** (2026-09-22) Gantt fills the 800px viewport, then scales down to the pane; GitHub's full dates overlapped. A diagram's own `axisFormat` still wins.
