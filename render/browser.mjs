// Headless-browser PNG renderer. Reads one JSON request per stdin line:
//   {"out": "/abs/file.png", "code": "...", "theme": {...}}   a mermaid diagram
//   {"out": "/abs/file.png", "d2": "...", "theme": {...}, "dir": "/abs/dir", "bin": "/abs/d2"}   a D2 diagram; local icons
//     resolve in dir; bin, the user's d2 command, renders it when given
//   {"out": "/abs/file.png", "image": "/abs/path or https://..."}   any image the browser can show
//   {"out": "/abs/file.png", "math": "\\frac{a}{b}", "color": "#rrggbb"}   display math, by KaTeX
//   {"out": "/abs/doc.pdf" or ".html", "markdown": "...", "dir": "/abs/dir", "kinds": {...}, "d2bin": "/abs/d2"}   a document export
// Each picture request may carry "maxPixels", a cap on the PNG's pixels.
// It answers one JSON line: {"out"} when the PNG is written, or {"out", "error"}.
// A real browser renders exactly what GitHub renders; a fake DOM mis-measures
// text and breaks class and gantt diagrams.
import { spawn } from 'node:child_process';
import { renameSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath, pathToFileURL } from 'node:url';
import puppeteer from 'puppeteer';
import { EXPORT_CSS, dataUrl, exporter, katexCss } from './document.mjs';

const SCALE = 2; // device pixels per CSS px; kitty downsamples, so text stays crisp
const VIEWPORT = { width: 800, height: 800 };
const MERMAID = fileURLToPath(import.meta.resolve('mermaid/dist/mermaid.min.js'));

// No font hinting: on Linux it rounds every glyph's advance to whole pixels,
// so text came out wider than D2 laid it out (code overflowed its boxes)
const browser = await puppeteer.launch({ headless: 'shell', args: ['--no-sandbox', '--font-render-hinting=none'] }).catch((e) => {
  // one short last line: the plugin shows it in place of each diagram
  console.error('cannot start the browser (run :Vellum build): ' + String(e.message).split('\n')[0]);
  process.exit(1);
});
// without Chrome every render would fail; exiting lets the plugin start a new one
browser.on('disconnected', () => process.exit(1));
const page = await browser.newPage();
await page.setViewport({ ...VIEWPORT, deviceScaleFactor: SCALE });
await page.setContent(`<!DOCTYPE html><body style="margin:0;background:transparent">
  <div id="c" style="display:inline-block;padding:12px"></div></body>`);
await page.addScriptTag({ path: MERMAID });
await page.addScriptTag({ path: fileURLToPath(import.meta.resolve('katex/dist/katex.min.js')) });
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

// D2 compiles to SVG in node (WebAssembly) and loads on the first D2 diagram,
// so documents without one pay nothing and an older build still draws mermaid.
// `theme` is { themeID, themeOverrides }; without it, D2's own light theme (exports).
// `bin` is the user's d2 command, if any: it renders then, else the bundled D2.
// Local icon paths resolve in `dir`.
let d2;
async function d2svg(code, theme, dir, bin) {
  d2 ??= await import('@terrastruct/d2').then((m) => new m.D2(), (e) => {
    throw new Error('D2 needs a rebuilt renderer (:Vellum build): ' + e.message);
  });
  const r = await d2.compile(code).catch((e) => {
    // newer syntax than the bundled D2 knows: the d2 command may still take it
    if (bin) return null;
    // compile errors arrive as JSON: [{"errmsg": "index:3:5: ..."}], index being the source
    let list;
    try { list = JSON.parse(e.message); } catch { throw e; }
    throw new Error(list.map((x) => x.errmsg.replace(/^index:/, 'line ')).join('\n'));
  });
  // the diagram's own d2-config wins: its padding, theme or theme-overrides.
  // The padding is the margin mermaid gets from #c; at 0, shapes on the edge
  // lose the outer half of their border
  const own = r?.diagram.config ?? {};
  const themed = theme && r && !own.themeID && !r.renderOptions.themeOverrides;
  if (bin) {
    // d2's flags would override the diagram's own d2-config, so ours go in as
    // d2-config after the code, for what it leaves unset; last keeps line numbers
    const config = {};
    if (r && own.pad == null) config.pad = 12;
    if (themed) Object.assign(config, { 'theme-id': theme.themeID, 'theme-overrides': theme.themeOverrides });
    return sized(await d2command(bin, Object.keys(config).length ? `${code}\nvars: { d2-config: ${d2map(config)} }\n` : code, dir));
  }
  const options = { ...r.renderOptions, pad: own.pad ?? 12, noXMLTag: true };
  if (themed) Object.assign(options, theme);
  for (const shape of r.diagram.shapes) {
    const icon = shape.icon; // a Go url.URL; data: URLs keep their payload in Opaque
    if (!icon || icon.Scheme || !dir) continue;
    const file = resolve(dir, icon.Path);
    let data;
    try { data = dataUrl(file); } catch { continue; } // missing: an empty icon, as D2 shows it
    shape.icon = { ...icon, Scheme: 'data', Opaque: data.slice('data:'.length), Path: '', RawPath: '' };
  }
  return sized(await d2.render(r.diagram, options));
}

// D2's root svg has only a viewBox; unsized, it collapses in a shrink-wrapped box
function sized(svg) {
  const [, , w, h] = /viewBox="([^"]+)"/.exec(svg)[1].split(/[\s,]+/);
  return svg.replace('<svg ', `<svg width="${w}" height="${h}" `);
}

// An object as a D2 map: { pad: 12; theme-overrides: { N1: "#000000" } }
const d2map = (o) => `{ ${Object.entries(o).map(([k, v]) => `${k}: ${typeof v === 'object' ? d2map(v) : JSON.stringify(v)}`).join('; ')} }`;

// D2 source → SVG with the d2 command, in `dir` so relative icons resolve; it
// bundles icons into the SVG. Its errors read "err: failed to compile -: -:3:5: ...".
function d2command(bin, source, dir) {
  return new Promise((done, fail) => {
    const p = spawn(bin, ['--no-xml-tag', '-', '-'], { cwd: dir, timeout: 30000 });
    const out = [], err = [];
    p.stdout.on('data', (b) => out.push(b));
    p.stderr.on('data', (b) => err.push(b));
    p.on('error', fail);
    p.on('close', (code, signal) => {
      if (code === 0) return done(Buffer.concat(out).toString());
      const lines = Buffer.concat(err).toString().split('\n').filter((l) => l.startsWith('err: '));
      fail(new Error(signal ? 'd2 took longer than 30 s'
        : lines.map((l) => l.slice(5).replace(/^failed to compile -: -:/, 'line ')).join('\n') || `d2 exited with ${code}`));
    });
    p.stdin.end(source);
  });
}

const d2diagram = async ({ d2: code, theme, dir, bin }) => {
  let svg;
  try {
    svg = await d2svg(code, theme, dir, bin);
  } catch (e) {
    return String(e?.message ?? e).slice(0, 600);
  }
  return page.evaluate(async (svg) => {
    const c = document.getElementById('c');
    c.innerHTML = svg;
    // icons load after the svg is in; listening in this same task misses none.
    // One that fails or hangs leaves its space empty, the diagram still shows
    const icons = [...c.querySelectorAll('image')].map((i) => new Promise((done) => {
      i.addEventListener('load', done);
      i.addEventListener('error', done);
      setTimeout(done, 10000);
    }));
    await Promise.all(icons);
    await document.fonts.ready; // D2 embeds its fonts; a shot before they load shows fallback glyphs
    return null;
  }, svg);
};

const picture = ({ image }) => {
  // local files go in as data URLs: an about:blank page may not read file://
  const src = /^https?:\/\//.test(image) ? image : dataUrl(image);
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

// Exports: the HTML comes from document.mjs; the page adds alerts, heading
// ids and diagram SVGs, then prints the result.
async function exportDoc({ markdown: text, dir, out, kinds, d2bin }) {
  const md = await exporter().catch((e) => {
    throw new Error('export needs a rebuilt renderer (:Vellum build): ' + e.message);
  });
  // a file:// page may load the document's relative images; about:blank may not
  const tmp = join(tmpdir(), `vellum-export-${process.pid}-${n++}.html`);
  writeFileSync(tmp, `<!DOCTYPE html><html><head><meta charset="utf-8"><base href="${pathToFileURL(dir + '/').href}">
    <style>${katexCss}${EXPORT_CSS}</style></head><body><article>${md.parse(text)}</article></body></html>`);
  const doc = await browser.newPage();
  try {
    await doc.goto(pathToFileURL(tmp).href, { waitUntil: 'load' });
    await doc.addScriptTag({ path: MERMAID });
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
    // D2 compiles in node, in its own light theme; a broken diagram, or a
    // build without D2, stays as its source
    const sources = await doc.$$eval('pre > code.language-d2', (codes) => codes.map((c) => c.textContent));
    if (sources.length) {
      const svgs = [];
      for (const code of sources) svgs.push(await d2svg(code, undefined, dir, d2bin).catch(() => null));
      await doc.evaluate(async (svgs) => {
        const codes = [...document.querySelectorAll('pre > code.language-d2')];
        svgs.forEach((svg, i) => {
          if (!svg) return;
          const box = document.createElement('div');
          box.className = 'diagram';
          box.innerHTML = svg;
          codes[i].parentElement.replaceWith(box);
        });
        await document.fonts.ready;
      }, svgs);
    }
    if (out.endsWith('.pdf')) {
      await doc.pdf({ path: out, format: 'A4', printBackground: true, margin: { top: '12mm', bottom: '12mm', left: '10mm', right: '10mm' } });
    } else {
      // local images go in as data, so the file stands alone; links stay
      // relative beside the source, and elsewhere point back at it
      const images = await doc.evaluate(() => [...document.images].map((i) => i.src).filter((s) => s.startsWith('file:')));
      const data = {};
      for (const url of images) {
        try {
          data[url] = dataUrl(fileURLToPath(url));
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

// Device pixels per CSS px for a shot of width x height CSS px: SCALE, or
// less when the PNG would hold more than maxPixels. Some terminal
// multiplexers silently drop big images (herdr: over about 5.9 megapixels).
// A pixel more each way covers the clip's rounding to whole CSS px.
const scaleFor = (width, height, maxPixels) =>
  maxPixels ? Math.min(SCALE, Math.sqrt(maxPixels / ((Math.ceil(width) + 1) * (Math.ceil(height) + 1)))) : SCALE;

// CRC-32 of a PNG chunk's type and data, by hand: zlib.crc32 needs Node 22.2.
const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  for (let k = 0; k < 8; k++) n = n & 1 ? 0xedb88320 ^ (n >>> 1) : n >>> 1;
  return n >>> 0;
});
const crc32 = (bytes) => ~bytes.reduce((c, b) => CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8), ~0) >>> 0;

// `png` with a pHYs chunk after its IHDR recording `scale` pixels per CSS px
// (CSS has 96 px per inch), so the plugin shows a capped PNG at its CSS size.
function withDensity(png, scale) {
  const ppm = Math.round(scale * 96 / 0.0254);
  const chunk = Buffer.alloc(21);
  chunk.writeUInt32BE(9, 0);
  chunk.write('pHYs', 4, 'latin1');
  chunk.writeUInt32BE(ppm, 8);
  chunk.writeUInt32BE(ppm, 12);
  chunk[16] = 1; // the unit is the metre
  chunk.writeUInt32BE(crc32(chunk.subarray(4, 17)), 17);
  const ihdrEnd = 33; // 8-byte signature, then IHDR: length, type, 13 bytes, CRC
  return Buffer.concat([png.subarray(0, ihdrEnd), chunk, png.subarray(ihdrEnd)]);
}

async function render(req) {
  if (req.markdown != null) return exportDoc(req);
  // mermaid keeps the container's padding; D2 pads itself; images and math are shot at their own size
  const [draw, shot] = req.image ? [picture, '#c img'] : req.math != null ? [formula, '#m'] : req.d2 != null ? [d2diagram, '#c > svg'] : [diagram, '#c'];
  const error = await draw(req);
  if (error) return { out: req.out, error };
  const element = await page.$(shot);
  const { width, height } = await element.boundingBox();
  // set for every shot: the page is shared, so a capped scale must not stick
  const scale = scaleFor(width, height, req.maxPixels);
  await page.setViewport({ ...VIEWPORT, deviceScaleFactor: scale });
  const png = Buffer.from(await element.screenshot({ omitBackground: true }));
  // write then rename, so a killed process never leaves a half PNG in the cache
  writeFileSync(req.out + '.tmp.png', withDensity(png, scale));
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
