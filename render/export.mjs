// HTML export without a browser (setup's chromium = false). Reads one JSON
// request from stdin:
//   {"out": "/abs/doc.html", "markdown": "...", "dir": "/abs/dir", "kinds": {...}}
// It answers one JSON line: {"out"} when the file is written, or {"out", "error"}.
// marked, KaTeX and the document's images are all handled in node; mermaid and
// D2 fences stay as code.
import { writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createInterface } from 'node:readline';
import { EXPORT_CSS, dataUrl, exporter, katexCss } from './document.mjs';

const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' };
const escapeHtml = (s) => s.replace(/[&<>"]/g, (c) => ESC[c]);
const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', '#39': "'", apos: "'", nbsp: ' ' };
const decode = (s) => s.replace(/&(#39|amp|lt|gt|quot|apos|nbsp);/g, (_, e) => ENTITIES[e]);
const stripTags = (html) => decode(html.replace(/<[^>]*>/g, ''));

// GitHub's heading ids, so "#heading" links work; same rule as browser.mjs
const slug = (text) => text.trim().toLowerCase().replace(/[^\p{L}\p{M}\p{N}\s_-]/gu, '').replace(/ /g, '-');

function headings(html) {
  const seen = new Map();
  return html.replace(/<h([1-6])([^>]*)>([\s\S]*?)<\/h\1>/g, (m, level, attrs, inner) => {
    const base = slug(stripTags(inner));
    const count = seen.get(base) ?? 0;
    seen.set(base, count + 1);
    const id = count ? `${base}-${count}` : base;
    return `<h${level}${attrs.replace(/\sid="[^"]*"/, '')} id="${escapeHtml(id)}">${inner}</h${level}>`;
  });
}

// Callout types and classes come from the preview (render.lua ALERTS).
function alerts(html, kinds) {
  return html.replace(/<blockquote>\n<p>\[!(\w+)\][+-]?[ \t]*([^\n]*?)(\n|<\/p>)/g, (m, type, title, end) => {
    const cls = kinds[type.toLowerCase()];
    if (!cls) return m;
    const name = title.trim() || type[0].toUpperCase() + type.slice(1).toLowerCase();
    return `<blockquote class="alert ${cls}">\n<p class="title">${name}</p>` + (end === '\n' ? '\n<p>' : '');
  });
}

// Local images go in as data, so the file stands alone.
function images(html, dir) {
  const cache = new Map();
  const local = (src) => {
    if (/^[a-z][\w+.-]*:/i.test(src) || src.startsWith('//')) return null;
    const [path] = src.split(/[?#]/);
    let decoded;
    try { decoded = decodeURIComponent(path); } catch { decoded = path; }
    const file = resolve(dir, decoded);
    if (!cache.has(file)) {
      let url = null;
      try { url = dataUrl(file); } catch {} // a missing image stays a broken link
      cache.set(file, url);
    }
    return cache.get(file);
  };
  return html.replace(/<img\b[^>]*>/gi, (tag) => {
    const m = /\bsrc=(?:"([^"]*)"|'([^']*)')/i.exec(tag);
    if (!m) return tag;
    const data = local(decode(m[1] ?? m[2]));
    return data ? tag.replace(m[0], `src="${data}"`) : tag;
  });
}

// Links stay relative beside the source, and elsewhere point back at it.
function links(html, dir, beside) {
  if (beside) return html;
  return html.replace(/<a\b[^>]*>/gi, (tag) => {
    const m = /\bhref=(?:"([^"]*)"|'([^']*)')/i.exec(tag);
    if (!m) return tag;
    const href = decode(m[1] ?? m[2]);
    if (href.startsWith('#') || /^[a-z][\w+.-]*:/i.test(href) || href.startsWith('//')) return tag;
    const [path, fragment] = href.split('#');
    let decoded;
    try { decoded = decodeURIComponent(path); } catch { decoded = path; }
    const url = pathToFileURL(resolve(dir, decoded)).href + (fragment ? '#' + fragment : '');
    return tag.replace(m[0], `href="${escapeHtml(url)}"`);
  });
}

// A printed page cannot be clicked open, and a standalone file has no base or scripts.
function details(html) {
  return html.replace(/<details([^>]*)>/gi, (m, attrs) => (/\bopen\b/.test(attrs) ? m : `<details${attrs} open>`));
}

function clean(html) {
  return html.replace(/<base\b[^>]*>/gi, '').replace(/<script\b[\s\S]*?<\/script>/gi, '');
}

async function exportHtml({ out, markdown: text, dir, kinds = {} }) {
  const md = await exporter().catch((e) => {
    throw new Error('export needs a rebuilt renderer (:Vellum build): ' + e.message);
  });
  let html = md.parse(text);
  html = headings(html);
  html = alerts(html, kinds);
  html = images(html, dir);
  html = links(html, dir, resolve(dirname(out)) === resolve(dir));
  html = details(html);
  html = clean(html);
  writeFileSync(out, `<!DOCTYPE html>\n<html><head><meta charset="utf-8"><style>${katexCss}${EXPORT_CSS}</style></head><body><article>${html}</article></body></html>`);
}

let line = '';
for await (const l of createInterface({ input: process.stdin })) {
  line = l;
  break;
}
let req = {};
try {
  req = JSON.parse(line);
  await exportHtml(req);
  process.stdout.write(JSON.stringify({ out: req.out }) + '\n');
} catch (e) {
  process.stdout.write(JSON.stringify({ out: req.out, error: String(e?.message ?? e).slice(0, 600) }) + '\n');
}
