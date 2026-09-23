// Headless-browser PNG renderer. Reads one JSON request per stdin line:
//   {"out": "/abs/file.png", "code": "...", "theme": {...}}   a mermaid diagram
//   {"out": "/abs/file.png", "image": "/abs/path or https://..."}   any image the browser can show
//   {"out": "/abs/file.png", "math": "\\frac{a}{b}", "color": "#rrggbb"}   display math, by KaTeX
//   {"out": "/abs/doc.pdf" or ".html", "markdown": "...", "dir": "/abs/dir", "kinds": {...}}   a document export
// and answers one JSON line: {"out"} when the PNG is written, or {"out", "error"}.
// A real browser renders exactly what GitHub renders; a fake DOM mis-measures
// text and breaks class and gantt diagrams.
import { readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, extname, join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath, pathToFileURL } from 'node:url';
import puppeteer from 'puppeteer';

const SCALE = 2; // device pixels per CSS px; kitty downsamples, so text stays crisp
const MIME = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.bmp': 'image/bmp', '.avif': 'image/avif' };

const browser = await puppeteer.launch({ headless: 'shell', args: ['--no-sandbox'] }).catch((e) => {
  // one short last line: the plugin shows it in place of each diagram
  console.error('cannot start the browser (run :Lazy build vellum.nvim): ' + String(e.message).split('\n')[0]);
  process.exit(1);
});
// without Chrome every render would fail; exiting lets the plugin start a new one
browser.on('disconnected', () => process.exit(1));
const page = await browser.newPage();
await page.setViewport({ width: 800, height: 800, deviceScaleFactor: SCALE });
await page.setContent(`<!DOCTYPE html><body style="margin:0;background:transparent">
  <div id="c" style="display:inline-block;padding:12px"></div></body>`);
await page.addScriptTag({ path: fileURLToPath(import.meta.resolve('mermaid/dist/mermaid.min.js')) });
await page.addScriptTag({ path: fileURLToPath(import.meta.resolve('katex/dist/katex.min.js')) });
// KaTeX's fonts inlined: an about:blank page cannot fetch its relative font URLs
const katexDir = dirname(fileURLToPath(import.meta.resolve('katex/dist/katex.min.css')));
const katexCss = readFileSync(join(katexDir, 'katex.min.css'), 'utf8').replace(/src:[^;}]*/g, (src) => {
  const font = readFileSync(join(katexDir, /url\((fonts\/[^)]+\.woff2)\)/.exec(src)[1])).toString('base64');
  return `src:url(data:font/woff2;base64,${font}) format("woff2")`;
});
// standards mode (KaTeX needs it) puts an inline svg on a text baseline, with a gap below
await page.addStyleTag({ content: katexCss + '.katex-display{margin:0} #c > svg{display:block}' });

let n = 0;
const diagram = ({ code, theme }) => page.evaluate(async (code, id, theme) => {
  mermaid.initialize({
    startOnLoad: false,
    theme: 'base',
    // gantt fills the viewport width with 11px text; sized up so it survives scaling
    gantt: { fontSize: 15, sectionFontSize: 15, barHeight: 28, barGap: 6, leftPadding: 90, axisFormat: '%b %d' },
    themeCSS: '.tick text { font-size: 13px; }',
    themeVariables: { fontFamily: 'Inter, "SF Pro Display", system-ui, "Noto Sans", sans-serif', ...theme },
  });
  const c = document.getElementById('c');
  try {
    const { svg } = await mermaid.render(id, code);
    c.innerHTML = svg;
    // mermaid emits width="100%" + max-width, which collapses in a shrink-wrapped box
    const s = c.firstElementChild;
    s.style.width = s.style.maxWidth || '';
    s.style.maxWidth = 'none';
    // classDef/style often set a light fill but no text color, which is fine
    // on GitHub's light page and unreadable on a dark theme: pick dark or
    // light text wherever a label would not stand out from its box
    const lum = (css) => {
      const m = /^rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)/.exec(css);
      if (!m) return null;
      const [r, g, b] = m.slice(1).map((v) => (v /= 255) <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    };
    for (const node of s.querySelectorAll('g.node')) {
      const shape = node.querySelector('rect, polygon, circle, ellipse, path');
      const bg = shape && lum(getComputedStyle(shape).fill);
      if (bg == null) continue;
      for (const t of node.querySelectorAll('.nodeLabel, .nodeLabel *, text, tspan')) {
        const style = getComputedStyle(t);
        const fg = lum(t instanceof SVGElement ? style.fill : style.color);
        if (fg == null || (Math.max(fg, bg) + 0.05) / (Math.min(fg, bg) + 0.05) >= 3) continue;
        const ink = bg > 0.18 ? '#1b1b1f' : '#f2f2f5';
        t.style.setProperty('color', ink, 'important');
        t.style.setProperty('fill', ink, 'important');
      }
    }
    return null;
  } catch (e) {
    c.innerHTML = '';
    document.getElementById('d' + id)?.remove(); // mermaid leaves its error SVG behind
    return String(e?.message ?? e).slice(0, 600);
  }
}, code, 'm' + n++, theme ?? {});

const picture = ({ image }) => {
  // local files go in as data URLs: an about:blank page may not read file://
  const src = /^https?:\/\//.test(image) ? image
    : `data:${MIME[extname(image).toLowerCase()] ?? 'application/octet-stream'};base64,${readFileSync(image).toString('base64')}`;
  return page.evaluate(async (src) => {
    const c = document.getElementById('c');
    c.innerHTML = '';
    const img = new Image();
    img.src = src;
    img.style.cssText = 'display:block;max-width:1200px';
    try {
      await Promise.race([img.decode(), new Promise((_, no) => setTimeout(() => no(new Error('timed out')), 10000))]);
    } catch (e) {
      return 'cannot load image: ' + (e?.message ?? e);
    }
    c.appendChild(img);
    return null;
  }, src);
};

const formula = ({ math, color }) => page.evaluate(async (tex, color) => {
  const c = document.getElementById('c');
  c.innerHTML = '<div id="m" style="display:inline-block;padding:2px 4px"></div>';
  const m = c.firstElementChild;
  m.style.color = color;
  try {
    katex.render(tex, m, { displayMode: true, throwOnError: true, strict: 'ignore' });
  } catch (e) {
    c.innerHTML = '';
    return String(e?.message ?? e).slice(0, 600);
  }
  await document.fonts.ready; // fonts load on first use; a shot before then shows fallback glyphs
  return null;
}, math, color);

// Exports: GitHub-flavored markdown with footnotes and math as HTML, then
// mermaid and alerts done in the page, printed light like GitHub. Math
// follows the preview's rule (inline.lua): "$…$" hugs its text and no digit
// follows, so "$5 and $10" stays text. The libraries load on the first
// export, so a renderer built before export existed still draws diagrams.
let markdown;
async function exporter() {
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
}

const EXPORT_CSS = `
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
img, .mermaid svg { max-width: 100%; }
.mermaid { text-align: center; }
pre, table, img, .mermaid, .katex-display { break-inside: avoid; }
`;

async function exportDoc({ markdown: text, dir, out, kinds }) {
  markdown ??= await exporter().catch((e) => {
    throw new Error('export needs a rebuilt renderer (:Lazy build vellum.nvim): ' + e.message);
  });
  // a file:// page may load the document's relative images; about:blank may not
  const tmp = join(tmpdir(), `vellum-export-${process.pid}-${n++}.html`);
  writeFileSync(tmp, `<!DOCTYPE html><html><head><meta charset="utf-8"><base href="${pathToFileURL(dir + '/').href}">
    <style>${katexCss}${EXPORT_CSS}</style></head><body><article>${markdown.parse(text)}</article></body></html>`);
  const doc = await browser.newPage();
  try {
    await doc.goto(pathToFileURL(tmp).href, { waitUntil: 'load' });
    await doc.addScriptTag({ path: fileURLToPath(import.meta.resolve('mermaid/dist/mermaid.min.js')) });
    await doc.evaluate(async (kinds) => {
      // callout types and colors come from the preview (render.lua ALERTS)
      for (const q of document.querySelectorAll('blockquote')) {
        const p = q.firstElementChild;
        const m = p?.tagName === 'P' && /^\[!(\w+)\][+-]?[ \t]*([^\n]*)\n?/.exec(p.innerHTML);
        if (!m || !kinds[m[1].toLowerCase()]) continue;
        q.classList.add('alert', kinds[m[1].toLowerCase()]);
        p.innerHTML = p.innerHTML.slice(m[0].length);
        if (!p.innerHTML.trim()) p.remove();
        const title = m[2] || m[1][0].toUpperCase() + m[1].slice(1).toLowerCase();
        q.insertAdjacentHTML('afterbegin', `<p class="title">${title}</p>`);
      }
      // GitHub's heading ids, so "#heading" links work; same rule as links.lua slug
      const seen = {};
      for (const h of document.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
        const id = h.textContent.trim().toLowerCase().replace(/[^\p{L}\p{M}\p{N}\s_-]/gu, '').replace(/ /g, '-');
        h.id = seen[id] ? `${id}-${seen[id]}` : id;
        seen[id] = (seen[id] ?? 0) + 1;
      }
      // a printed page cannot be clicked open
      for (const d of document.querySelectorAll('details')) d.open = true;
      mermaid.initialize({ startOnLoad: false, theme: 'default' });
      let i = 0;
      for (const code of document.querySelectorAll('pre > code.language-mermaid')) {
        const box = document.createElement('div');
        box.className = 'mermaid';
        const id = 'export' + i++;
        try {
          box.innerHTML = (await mermaid.render(id, code.textContent)).svg;
          code.parentElement.replaceWith(box);
        } catch {
          document.getElementById('d' + id)?.remove(); // a broken diagram stays as its source
        }
      }
      await document.fonts.ready;
    }, kinds);
    if (out.endsWith('.pdf')) {
      await doc.pdf({ path: out, format: 'A4', printBackground: true, margin: { top: '12mm', bottom: '12mm', left: '10mm', right: '10mm' } });
    } else {
      // local images go in as data, so the file stands alone; links stay
      // relative beside the source, and elsewhere point back at it
      const images = await doc.evaluate(() => [...document.images].map((i) => i.src).filter((s) => s.startsWith('file:')));
      const data = {};
      for (const url of images) {
        try {
          const file = fileURLToPath(url);
          data[url] = `data:${MIME[extname(file).toLowerCase()] ?? 'application/octet-stream'};base64,${readFileSync(file).toString('base64')}`;
        } catch {} // a missing image stays a broken link, as in the browser
      }
      const html = await doc.evaluate((data, beside) => {
        for (const img of document.images) if (data[img.src]) img.src = data[img.src];
        if (!beside) {
          for (const a of document.querySelectorAll('a[href]')) {
            const href = a.getAttribute('href');
            if (!href.startsWith('#') && !/^[a-z][\w+.-]*:/i.test(href)) a.href = a.href;
          }
        }
        document.querySelectorAll('base, script').forEach((e) => e.remove());
        return '<!DOCTYPE html>\n' + document.documentElement.outerHTML;
      }, data, resolve(dirname(out)) === resolve(dir));
      writeFileSync(out, html);
    }
    return { out };
  } finally {
    await doc.close();
    rmSync(tmp, { force: true });
  }
}

async function render(req) {
  if (req.markdown != null) return exportDoc(req);
  // diagrams keep the container's padding; images and math are shot at their own size
  const [draw, shot] = req.image ? [picture, '#c img'] : req.math != null ? [formula, '#m'] : [diagram, '#c'];
  const error = await draw(req);
  if (error) return { out: req.out, error };
  // write then rename, so a killed process never leaves a half PNG in the cache
  await (await page.$(shot)).screenshot({ path: req.out + '.tmp.png', omitBackground: true });
  renameSync(req.out + '.tmp.png', req.out);
  return { out: req.out };
}

// One page, so requests run one at a time, in order. A queued request can be
// cancelled with {"cancel": out}: while typing in a diagram only the newest
// version matters. Cancelled requests get no answer.
const waiting = [];
let running = null;
function work() {
  running ??= (async () => {
    while (waiting.length) {
      const req = waiting.shift();
      const reply = await render(req).catch((e) => ({ out: req.out, error: String(e?.message ?? e) }));
      process.stdout.write(JSON.stringify(reply) + '\n');
    }
    running = null;
  })();
}
createInterface({ input: process.stdin }).on('line', (line) => {
  const req = JSON.parse(line);
  if (req.cancel) {
    const i = waiting.findIndex((r) => r.out === req.cancel);
    if (i >= 0) waiting.splice(i, 1);
  } else {
    waiting.push(req);
    work();
  }
}).on('close', async () => {
  await running;
  await browser.close();
});
