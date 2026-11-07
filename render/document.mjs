// Markdown → HTML and KaTeX setup shared by both exports: the browser one
// (browser.mjs) and the one that runs without a browser (export.mjs).
import { readFileSync } from 'node:fs';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const MIME = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.bmp': 'image/bmp', '.avif': 'image/avif' };

export const dataUrl = (file) => `data:${MIME[extname(file).toLowerCase()] ?? 'application/octet-stream'};base64,${readFileSync(file).toString('base64')}`;

// KaTeX's fonts inlined: an about:blank page cannot fetch its relative font URLs,
// and a standalone HTML file may sit anywhere.
export const katexCss = (() => {
  const dir = dirname(fileURLToPath(import.meta.resolve('katex/dist/katex.min.css')));
  return readFileSync(join(dir, 'katex.min.css'), 'utf8').replace(/src:[^;}]*/g, (src) => {
    const font = readFileSync(join(dir, /url\((fonts\/[^)]+\.woff2)\)/.exec(src)[1])).toString('base64');
    return `src:url(data:font/woff2;base64,${font}) format("woff2")`;
  });
})();

// GitHub-flavored markdown with footnotes and math as HTML. Math follows the
// preview's rule (inline.lua): "$…$" hugs its text and no digit follows, so
// "$5 and $10" stays text. The libraries load on the first export, so a
// renderer built before export existed still draws diagrams.
let markdown;
export function exporter() {
  return (markdown ??= (async () => {
    const [{ Marked }, { default: footnote }, { default: katex }] = await Promise.all([
      import('marked'), import('marked-footnote'), import('katex'),
    ]);
    const tex = (text, displayMode) => katex.renderToString(text, { displayMode, throwOnError: false });
    const inline = {
      name: 'math',
      level: 'inline',
      start: (src) => src.indexOf('$'),
      tokenizer(src) {
        const m = /^\$\$([^$]+?)\$\$/.exec(src) ?? /^\$(?!\s)((?:\\.|[^$\\])+?)(?<!\s)\$(?!\d)/.exec(src);
        if (m) return { type: 'math', raw: m[0], text: m[1], display: m[0].startsWith('$$') };
      },
      renderer: (t) => tex(t.text, t.display),
    };
    const block = {
      name: 'mathBlock',
      level: 'block',
      start: (src) => /^\$\$/m.exec(src)?.index,
      tokenizer(src) {
        const m = /^\$\$([\s\S]+?)\$\$[ \t]*(?:\n|$)/.exec(src);
        if (m) return { type: 'mathBlock', raw: m[0], text: m[1] };
      },
      renderer: (t) => tex(t.text, true),
    };
    const code = ({ text, lang }) => (lang === 'math' ? tex(text, true) : false); // false: the usual code block
    return new Marked({ gfm: true }).use(footnote(), { extensions: [inline, block], renderer: { code } });
  })());
}

export const EXPORT_CSS = `
body { margin: 0; color: #1f2328; font: 16px/1.6 -apple-system, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif; }
article { max-width: 860px; margin: 0 auto; padding: 32px; }
h1, h2 { padding-bottom: .3em; border-bottom: 1px solid #d1d9e0; }
a { color: #0969da; }
code, pre { font: 85% ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; background: #f6f8fa; border-radius: 6px; }
code { padding: .2em .4em; }
pre { padding: 16px; white-space: pre-wrap; overflow-wrap: anywhere; tab-size: 4; }
pre code { padding: 0; font-size: 100%; background: none; }
table { border-collapse: collapse; }
th, td { padding: 6px 13px; border: 1px solid #d1d9e0; }
tr:nth-child(2n) { background: #f6f8fa; }
blockquote { margin: 0; padding: 0 1em; color: #59636e; border-left: .25em solid #d1d9e0; }
blockquote.alert { color: inherit; }
.alert > .title { font-weight: 600; }
.note { border-color: #0969da; } .note > .title { color: #0969da; }
.tip { border-color: #1a7f37; } .tip > .title { color: #1a7f37; }
.important { border-color: #8250df; } .important > .title { color: #8250df; }
.warning { border-color: #9a6700; } .warning > .title { color: #9a6700; }
.caution { border-color: #d1242f; } .caution > .title { color: #d1242f; }
li:has(> input[type=checkbox]) { list-style: none; }
img, .mermaid svg, .diagram svg { max-width: 100%; }
.diagram svg { height: auto; }
.mermaid, .diagram { text-align: center; }
pre, table, img, .mermaid, .diagram, .katex-display { break-inside: avoid; }
`;
