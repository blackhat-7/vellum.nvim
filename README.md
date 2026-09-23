# vellum.nvim

A markdown preview for Neovim. It renders in a split beside your buffer, inside the terminal. GitHub-flavored markdown, with mermaid diagrams and display math as real images.

![Demo on docs/showcase.md: open the preview, edit a label in a large architecture diagram, zoom and pan it, scroll the preview with the mouse through KaTeX math and a saga sequence diagram, a state machine, resize the split](docs/demo.webp)

- **Live.** Every keystroke re-renders. Unchanged blocks come from a cache, so long documents stay fast.
- **Scroll sync, both ways.** The preview follows your cursor. Scrolling the preview scrolls the source.
- **Diagrams.** Mermaid renders in a headless Chrome and shows as an image, sized to your terminal font. Each one renders once and is cached on disk (capped at 100 MB).
- **Zoom.** Open any diagram or image full-screen, then zoom and pan with keys or the mouse.
- **Math.** Inline `$…$` becomes Unicode text; display math renders with KaTeX.
- **Styled.** Heading bands, code with syntax colors, tables, GitHub alerts, task lists, `<details>` blocks, inline badges. Colors come from your colorscheme.

![vellum.nvim: markdown source on the left, live preview on the right, with badges, a mermaid flowchart, a table and code](docs/hero.png)

Colors follow your colorscheme, light or dark, diagrams included:

<p>
  <img src="docs/light.png" width="49%" alt="The preview in rose-pine dawn: task list, warning alert, sequence diagram, details block">
  <img src="docs/carbonfox.png" width="49%" alt="The same document in carbonfox">
</p>

## Requirements

- Neovim ≥ 0.12 with `termguicolors`
- Node.js ≥ 20 (for mermaid diagrams and non-PNG images)
- For images: [kitty](https://sw.kovidgoyal.net/kitty/) or [Ghostty](https://ghostty.org). Works over ssh. In tmux, add:
  ```tmux
  set -g allow-passthrough on
  set -as terminal-features ',xterm-256color:RGB'   # your outer $TERM; ssh drops COLORTERM
  ```
- A [Nerd Font](https://www.nerdfonts.com) for the alert and checkbox icons

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'blackhat-7/vellum.nvim',
  ft = 'markdown',
  keys = { { '<leader>mp', '<cmd>Vellum<cr>', desc = 'Markdown preview' } },
  opts = {},
}
```

lazy runs `build.lua` on install. It installs the diagram renderer: `npm ci` and a small headless Chrome download.

If diagrams don't show, run `:checkhealth vellum`. It checks Node, renders a test diagram, and says what your terminal or tmux setup is missing.

## Use

`:Vellum` toggles the preview. It also closes once no window shows the markdown file.

In the preview, `q` closes it and `<CR>` on a diagram or image opens it full-screen. There:

- `+` / `-` zoom. Ctrl+wheel zooms toward the mouse pointer.
- `hjkl`, the arrow keys or the mouse wheel pan.
- `0` fits the image to the screen.
- `q` or `<Esc>` closes it.

To zoom without leaving the markdown buffer, map `require('vellum').zoom()`. It opens the image at your cursor:

```lua
vim.keymap.set('n', '<leader>mz', function() require('vellum').zoom() end)
```

Options (the defaults):

```lua
require('vellum').setup({
  max_width = 100, -- widest text column in the preview
})
```

## Supported

| Markdown | Rendering |
|---|---|
| Headings | H1 band, H2 rule, colored levels |
| Emphasis, strike, `code`, links, bare URLs | styled inline |
| Lists, task lists, ordered lists | bullets per depth, checkboxes |
| Quotes and `> [!NOTE]` alerts | colored bar and title |
| Tables | aligned, wrapped to fit, zebra rows |
| Fenced code | tree-sitter syntax colors, language label |
| ` ```mermaid ` | image (text fallback outside kitty/Ghostty) |
| Footnotes | superscript refs, muted notes |
| Math: `$…$`, `$$…$$`, ` ```math ` | inline as Unicode text (`x²`, `α ≤ β`); display math as a KaTeX image (Unicode text elsewhere) |
| Images: PNG, JPG, GIF, WebP, SVG, local or http(s) | image (alt text elsewhere) |
| Front matter, HTML blocks | shown as YAML / text; comments hidden |

## License

MIT
