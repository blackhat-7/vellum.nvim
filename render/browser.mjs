// Headless-browser PNG renderer. Reads one JSON request per stdin line:
//   {"out": "/abs/file.png", "code": "...", "theme": {...}}   a mermaid diagram
//   {"out": "/abs/file.png", "image": "/abs/path or https://..."}   any image the browser can show
//   {"out": "/abs/file.png", "math": "\\frac{a}{b}", "color": "#rrggbb"}   display math, by KaTeX
// and answers one JSON line: {"out"} when the PNG is written, or {"out", "error"}.
// A real browser renders exactly what GitHub renders; a fake DOM mis-measures
// text and breaks class and gantt diagrams.
import { readFileSync, renameSync } from 'node:fs';
import { dirname, extname, join } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';

const SCALE = 2; // device pixels per CSS px; kitty downsamples, so text stays crisp
const MIME = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.bmp': 'image/bmp', '.avif': 'image/avif' };

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

async function render(req) {
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
