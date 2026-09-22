// Mermaid → PNG server. Reads one JSON request per stdin line:
//   {"code": "...", "out": "/abs/file.png", "theme": {...themeVariables}}
// and answers one JSON line: {"out", "w", "h"} in CSS px, or {"out", "error"}.
// A real headless browser renders exactly what GitHub renders; a fake DOM
// mis-measures text and breaks class and gantt diagrams.
import { renameSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';

const SCALE = 2; // device pixels per CSS px; kitty downsamples, so text stays crisp

const browser = await puppeteer.launch({ headless: 'shell', args: ['--no-sandbox'] });
const page = await browser.newPage();
await page.setViewport({ width: 800, height: 800, deviceScaleFactor: SCALE });
await page.setContent(`<body style="margin:0;background:transparent">
  <div id="c" style="display:inline-block;padding:12px"></div></body>`);
await page.addScriptTag({ path: fileURLToPath(import.meta.resolve('mermaid/dist/mermaid.min.js')) });

let n = 0;
async function render({ code, out, theme }) {
  const res = await page.evaluate(async (code, id, theme) => {
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
  if (res) return { out, error: res };
  const el = await page.$('#c');
  const box = await el.boundingBox();
  // write then rename, so a killed process never leaves a half PNG in the cache
  await el.screenshot({ path: out + '.tmp.png', omitBackground: true });
  renameSync(out + '.tmp.png', out);
  return { out, w: Math.round(box.width), h: Math.round(box.height) };
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
