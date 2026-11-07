# Contributing

Thanks for helping. This page has what you need: setup, checks, the code map and the rules.

## Setup

- Neovim 0.12 or newer. Node 20 or newer, for the renderer only.
- Build the renderer once: `:Vellum build`, or `(cd render && npm ci && npx puppeteer browsers install chrome-headless-shell)`.
- Try it: `nvim --clean -u test/init.lua test/sample.md -c Vellum`.

## Checks

Run these before you open a pull request:

```sh
nvim --clean -l test/run.lua      # all assertions, ~3 s
nvim --clean -l test/perf.lua     # keystroke cost on 5,000 lines; keep it near 2–3 ms
nvim --clean -l test/render.lua   # real renderer: every test diagram, math, images, export; ~7 s
```

- `test/render.lua` compares picture sizes with `test/render.sizes`. If you change how pictures look on purpose, run it with `--update` and say why in the commit.
- Changes you can see need a look in kitty or Ghostty (and tmux if they touch images). `test/d2.md` and `test/diagrams.md` hold big diagrams for this.
- A bug fix comes with a check that fails without it.

## Code map

- `lua/vellum/init.lua`: the preview window, autocmds, scroll sync, `setup()`.
- `lua/vellum/render.lua`: markdown blocks (tree-sitter) to styled lines. Caches each block.
- `lua/vellum/inline.lua`: inline markdown and word wrap.
- `lua/vellum/code.lua`: code panels and diagrams.
- `lua/vellum/latex.lua`: math as Unicode text, or a KaTeX picture.
- `lua/vellum/media.lua`: images.
- `lua/vellum/mdx.lua`: MDX files.
- `lua/vellum/theme.lua`: colors, all taken from the colorscheme.
- `lua/vellum/image.lua`: kitty graphics through Unicode placeholders.
- `lua/vellum/browser.lua` and `render/browser.mjs`: one headless Chrome that turns diagrams, display math and non-PNG images into cached PNGs.
- `lua/vellum/build.lua` and `build.lua`: install the renderer.
- `flake.nix` and `nix/package.nix`: the Nix package.

## Rules

- **Typing never waits.** Unchanged blocks come from the cache. Pictures render in the background.
- **The preview never lies.** Everything renders, or shows as its dimmed source. Only HTML comments, link definitions and MDX statements are hidden.
- **Colors come from the colorscheme.** No fixed colors in Lua; add a group in `theme.lua`.
- **Keep files small.** Split a file that grows past about 500 lines.
- **No new dependency** without an entry in `docs/decisions.md`.
- **Never weaken a test to make it pass.** If an assertion must change, say why in the commit.
- **Comments say why**, not what.
- **Commits say what changed and why.**

`docs/decisions.md` explains why things are the way they are. Read it before you undo something. Add an entry when you make a choice someone might later undo.

## Gotchas

- `node:start()` returns three values. As the last argument of a call, wrap it in parentheses.
- Footnote definitions are not a tree-sitter node: they parse as paragraphs or link definitions.
- A setext underline can sit inside a list item. Never assume a heading's marker is its first or last child.
- The inline parser has unnamed punctuation children. Walk only named nodes.
- Tree-sitter's `latex_block` swallows markup: `$5 [a](b) $10` is one node.
- `WinScrolled` fires in the current window for any window that scrolled. Check `v:event`. Headless Neovim never fires it.
- Scroll sync goes both ways, so each side ignores its own echo (`S.top`, `S.view`).
- The preview must never scroll sideways: image rows mark only their first cell.
- Kitty placeholders need `termguicolors`: the image id is the text color.
- tmux needs `set -g allow-passthrough on` and RGB in `terminal-features`.
- Puppeteer only downloads a browser at install, never at launch. The renderer runs in `render/`, where it reads `.puppeteerrc.cjs`.
- `test/run.lua` sets a private cache before loading the plugin, because loading prunes the cache.
