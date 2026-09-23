# Plan

One line per task, ordered. Top unchecked line is next. `[ ]` open · `[~]` in progress · `[x]` done.
Each line carries its own done-check.

- [x] Core: `:Vellum` split preview, tree-sitter renderer, block cache, scroll sync. Done: `nvim --clean -l test/run.lua` green.
- [x] Mermaid as images through kitty Unicode placeholders, in tmux. Done: screenshot in kitty 0.48 + tmux 3.7 shows the diagram and it scrolls with text.
- [x] Performance on a 5,000-line doc. `nvim --clean -l test/perf.lua`: 25 → 6.1 ms median per keystroke (target was 5; parse is 0.6, the rest is a linear tree walk). A README re-renders in 0.23 ms.
- [x] Install from GitHub with lazy.nvim in a clean config. Done: `Lazy! sync` ran `build.lua`; a sequence diagram rendered to the cache; a syntax error came back as a message.
- [x] Every mermaid type readable in dark and light schemes (`test/diagrams.md`). Fixed: gantt text size and axis, black mindmap/timeline boxes (cScale colors).
- [x] README screenshot of the preview (`docs/screenshot.png`). H1 became a three-row band while checking it.
- [x] Footnotes: `[^1]` → `¹`, definitions render in place as muted notes (tree-sitter parses them as paragraphs or, for one word, link definitions). Tests + fuzz vocabulary.
- [x] Non-PNG and remote images via the browser renderer (jpg, gif, webp, svg, http(s)). Seen in kitty: `test/sample.md` Images section.
- [x] Split `render.lua` (737 lines) into `inline.lua`, `media.lua`, `code.lua`. Done: each file < 500 lines, tests green, perf unchanged.
- [x] Inline images inside text (badge rows): small ones sit in the line, big ones break out as block pictures. Done: badge row in `test/sample.md` renders as images in kitty.
- [x] `<details>`/`<summary>`: summary shows as "▾ summary", body renders as normal markdown. Done: test + sample.
- [x] Start the renderer when `:Vellum` opens. First diagram 840 → 220 ms (headless, 1.5 s after open).
- [x] Cap the PNG cache (`stdpath('cache')/vellum`) at 100 MB, least recently used out first. Done: test fills a temp cache past the cap.
- [x] README showcase: `docs/hero.png`, `docs/light.png`, `docs/carbonfox.png`, shot from `docs/demo.md` in kitty at font size 14, framed with ImageMagick.
- [x] Smooth pane resizing: images fit the width, pixels sent once, redraw after the drag settles. Done: 80-column drag in kitty + tmux on a 4-diagram doc, nvim CPU 47 → 10 ticks, no blank diagram.
- [x] README demo GIF (`docs/demo.gif`): open, scroll, live typing with a diagram, resize. Done: recorded in kitty + tmux from `docs/demo.md`, checked frame by frame.
