// Headless-browser PNG renderer. Reads one JSON request per stdin line:
//   {"out": "/abs/file.png", "code": "...", "theme": {...}}   a mermaid diagram
//   {"out": "/abs/file.png", "image": "/abs/path or https://..."}   any image the browser can show
// and answers one JSON line: {"out"} when the PNG is written, or {"out", "error"}.
// A real browser renders exactly what GitHub renders; a fake DOM mis-measures
// text and breaks class and gantt diagrams.
import { readFileSync, renameSync } from 'node:fs';
import { extname } from 'node:path';
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
const page = await browser.newPage();
await page.setViewport({ width: 800, height: 800, deviceScaleFactor: SCALE });
await page.setContent(`<body style="margin:0;background:transparent">
  <div id="c" style="display:inline-block;padding:12px"></div></body>`);
await page.addScriptTag({ path: fileURLToPath(import.meta.resolve('mermaid/dist/mermaid.min.js')) });

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

async function render(req) {
  const error = await (req.image ? picture(req) : diagram(req));
  if (error) return { out: req.out, error };
  // write then rename, so a killed process never leaves a half PNG in the cache
  await (await page.$('#c')).screenshot({ path: req.out + '.tmp.png', omitBackground: true });
  renameSync(req.out + '.tmp.png', req.out);
  return { out: req.out };
}

// One page, so requests run strictly in order.
let queue = Promise.resolve();
createInterface({ input: process.stdin }).on('line', (line) => {
  queue = queue.then(async () => {
    const req = JSON.parse(line);
    const reply = await render(req).catch((e) => ({ out: req.out, error: String(e?.message ?? e) }));
    process.stdout.write(JSON.stringify(reply) + '\n');
  });
}).on('close', () => queue.then(() => browser.close()));
