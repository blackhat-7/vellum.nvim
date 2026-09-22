# Plan

One line per task, ordered. Top unchecked line is next. `[ ]` open · `[~]` in progress · `[x]` done.
Each line carries its own done-check.

- [x] Core: `:Vellum` split preview, tree-sitter renderer, block cache, scroll sync. Done: `nvim --clean -l test/run.lua` green.
- [x] Mermaid as images through kitty Unicode placeholders, in tmux. Done: screenshot in kitty 0.48 + tmux 3.7 shows the diagram and it scrolls with text.
- [x] Performance on a 5,000-line doc. `nvim --clean -l test/perf.lua`: 25 → 6.1 ms median per keystroke (target was 5; parse is 0.6, the rest is a linear tree walk). A README re-renders in 0.23 ms.
- [ ] Install from GitHub with lazy.nvim in a clean config. Done when `build.lua` runs and a diagram renders.
- [ ] Every mermaid type (flowchart, sequence, class, state, ER, gantt, pie, mindmap, timeline, git) readable in dark and light schemes. Done: screenshots checked.
- [ ] README screenshot of the preview. Done when README shows it.
- [ ] Footnotes (`[^1]`) render as superscript refs plus a notes section. Done: test in `test/run.lua`.
- [ ] Non-PNG local images (jpg, gif, svg) via the browser renderer. Done: test doc shows each.
