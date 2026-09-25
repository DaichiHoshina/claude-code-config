#!/usr/bin/env node
// new-doc.mjs — quick doc generator (/ld の 3 手 flow の実体)
// Run from local-docs root: node _index/new-doc.mjs --type spec --out foo --title "..." --md -
// Deps: node:fs, node:path, node:child_process のみ
//
// ============================================================
// Markdown 方言 canonical (この comment が正本)
// ============================================================
// block:
//   ## / ### / ####          → h2 / h3 / h4
//   - item  /  1. item       → ul / ol (2 space 字下げで入れ子)
//   | a | b |                → table (2 行目の |---| が header 区切り。数値セルは右寄せ)
//   ```lang ... ```          → pre > code
//   > text                   → blockquote
//   ::: verify ... :::       → ul.verify   (✓ 付き確認項目)
//   ::: nonscope ... :::     → ul.nonscope (− 付き対象外)
//   ::: timeline ... :::     → div.timeline > .step (- 見出し / 続く行が本文)
//   ---                      → hr
// inline:
//   **強調**                 → <strong>
//   `code`                   → <code>
//   ==核心==                 → <mark>
//   [text](url)              → <a href>
//   [[ok:text]]              → <span class="pill ok">text</span>
//                              key は ok | warn | skip | new | mod
// ============================================================

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const ROOT = path.resolve(import.meta.dirname, '..');
const TEMPLATES = path.join(ROOT, '_templates');

const TYPES = ['spec', 'decision', 'report', 'investigation', 'postmortem', 'runbook', 'log', 'plan', 'guide'];
const DATE_META = {
  investigation: 'event-date',
  postmortem: 'event-date',
  report: 'data-window',
  log: 'observed-at',
};
const PILL_KEYS = new Set(['ok', 'warn', 'skip', 'new', 'mod']);

// ---------- arg parsing ----------

function parseArgs(argv) {
  const opts = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) die(`不明な引数: ${a}`);
    const key = a.slice(2);
    if (key === 'force') { opts.force = true; continue; }
    const val = argv[++i];
    if (val === undefined) die(`--${key} に値がない`);
    opts[key] = val;
  }
  return opts;
}

function die(msg) {
  console.error(`error: ${msg}`);
  process.exit(1);
}

const today = () => new Date().toLocaleDateString('sv-SE'); // YYYY-MM-DD (local)
// created / updated は一覧を分単位で並べるため、時刻まで刻む
const nowMinute = () => new Date().toLocaleString('sv-SE').slice(0, 16); // YYYY-MM-DD HH:MM (local)

// ---------- inline ----------

function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// ---------- code highlight (Go のみ。他言語は escape だけ) ----------

const GO_KEYWORDS = new Set(['break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else',
  'fallthrough', 'for', 'func', 'go', 'goto', 'if', 'import', 'interface', 'map', 'package', 'range',
  'return', 'select', 'struct', 'switch', 'type', 'var', 'nil', 'true', 'false', 'iota']);
const GO_TYPES = new Set(['bool', 'byte', 'error', 'int', 'int8', 'int16', 'int32', 'int64', 'uint',
  'uint8', 'uint16', 'uint32', 'uint64', 'float32', 'float64', 'rune', 'string', 'any']);
const GO_TOKEN = /(\/\/[^\n]*|\/\*[\s\S]*?\*\/)|("(?:\\.|[^"\\\n])*"|`[^`]*`|'(?:\\.|[^'\\\n])+')|\b(\d+(?:\.\d+)?)\b|\b([A-Za-z_]\w*)\b(\s*\()?/g;

function highlightGo(src) {
  let out = '';
  let last = 0;
  for (const m of src.matchAll(GO_TOKEN)) {
    out += escapeHtml(src.slice(last, m.index));
    last = m.index + m[0].length;
    const [all, comment, str, num, ident, call] = m;
    if (comment) out += `<span class="c">${escapeHtml(comment)}</span>`;
    else if (str) out += `<span class="s">${escapeHtml(str)}</span>`;
    else if (num) out += `<span class="n">${num}</span>`;
    else if (GO_KEYWORDS.has(ident)) out += `<span class="k">${ident}</span>${call ?? ''}`;
    else if (GO_TYPES.has(ident)) out += `<span class="t">${ident}</span>${call ?? ''}`;
    else if (call) out += `<span class="f">${ident}</span>${call}`;
    else out += escapeHtml(all);
  }
  return out + escapeHtml(src.slice(last));
}

function highlightCode(lang, src) {
  return lang === 'go' ? highlightGo(src) : escapeHtml(src);
}

function inline(src) {
  // code span を先に退避し、他の inline 規則の対象外にする
  const spans = [];
  let s = src.replace(/`([^`]+)`/g, (_, code) => {
    spans.push(`<code>${escapeHtml(code)}</code>`);
    return `\u0000${spans.length - 1}\u0000`;
  });
  s = escapeHtml(s);
  s = s.replace(/\[\[([a-z]+):([^\]]+)\]\]/g, (m, key, text) =>
    PILL_KEYS.has(key) ? `<span class="pill ${key}">${text}</span>` : m);
  s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2">$1</a>');
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  s = s.replace(/==([^=]+)==/g, '<mark>$1</mark>');
  return s.replace(/\u0000(\d+)\u0000/g, (_, i) => spans[Number(i)]);
}

// ---------- table ----------

const NUMERIC_RE = /^[-+]?[\d,]+(\.\d+)?\s*(%|件|回|本|人|円|倍|ms|s|分|時間|KB|MB|GB|x)?$/;

function splitRow(line) {
  return line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(c => c.trim());
}

function renderTable(rows) {
  const hasHeader = rows.length > 1 && /^\|?[\s:|-]+\|[\s:|-]*$/.test(rows[1]);
  const header = hasHeader ? splitRow(rows[0]) : null;
  const bodyRows = (hasHeader ? rows.slice(2) : rows).map(splitRow);
  // 列ごとに「数値セルのみ」なら右寄せする
  const colCount = Math.max(header ? header.length : 0, ...bodyRows.map(r => r.length));
  const alignRight = [];
  for (let c = 0; c < colCount; c++) {
    const cells = bodyRows.map(r => r[c]).filter(v => v !== undefined && v !== '');
    alignRight[c] = cells.length > 0 && cells.every(v => NUMERIC_RE.test(v));
  }
  const td = (v, c, tag) => {
    const style = alignRight[c] ? ' style="text-align:right"' : '';
    return `<${tag}${style}>${inline(v ?? '')}</${tag}>`;
  };
  const out = ['<table>'];
  if (header) {
    out.push('<thead><tr>' + header.map((v, c) => td(v, c, 'th')).join('') + '</tr></thead>');
  }
  out.push('<tbody>');
  for (const r of bodyRows) {
    out.push('<tr>' + Array.from({ length: colCount }, (_, c) => td(r[c], c, 'td')).join('') + '</tr>');
  }
  out.push('</tbody>', '</table>');
  return out.join('\n');
}

// ---------- list ----------

function indentOf(line) {
  const m = line.match(/^(\s*)/);
  return Math.floor(m[1].replace(/\t/g, '  ').length / 2);
}

// items: [{ depth, ordered, text }]
function renderList(items) {
  const out = [];
  const stack = [];
  for (const item of items) {
    while (stack.length > item.depth + 1) { out.push(`</li></${stack.pop()}>`); }
    if (stack.length === item.depth + 1) {
      if (stack[stack.length - 1] !== (item.ordered ? 'ol' : 'ul')) {
        out.push(`</li></${stack.pop()}>`);
      } else {
        out.push('</li>');
      }
    }
    if (stack.length < item.depth + 1) {
      const tag = item.ordered ? 'ol' : 'ul';
      out.push(`<${tag}>`);
      stack.push(tag);
    }
    out.push(`<li>${inline(item.text)}`);
  }
  while (stack.length) out.push(`</li></${stack.pop()}>`);
  return out.join('\n');
}

// ---------- fenced block (::: verify / nonscope / timeline) ----------

function renderFenced(kind, lines) {
  const items = lines.filter(l => l.trim() !== '');
  if (kind === 'verify' || kind === 'nonscope') {
    const lis = items.map(l => `<li>${inline(l.replace(/^\s*-\s*/, ''))}</li>`);
    return `<ul class="${kind}">\n${lis.join('\n')}\n</ul>`;
  }
  // timeline: "- 見出し" で step 開始、続く行が本文
  const steps = [];
  for (const l of items) {
    if (/^\s*-\s+/.test(l)) steps.push({ head: l.replace(/^\s*-\s+/, ''), body: [] });
    else if (steps.length) steps[steps.length - 1].body.push(l.trim());
  }
  const html = steps.map((s, i) => {
    const body = s.body.length ? `\n<p>${inline(s.body.join(' '))}</p>` : '';
    return `<div class="step"><div class="num">${i + 1}</div><div class="body"><h3>${inline(s.head)}</h3>${body}</div></div>`;
  });
  return `<div class="timeline">\n${html.join('\n')}\n</div>`;
}

// ---------- markdown → html ----------

function mdToHtml(md) {
  const lines = md.replace(/\r\n/g, '\n').split('\n');
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const trimmed = line.trim();

    if (trimmed === '') { i++; continue; }

    // code fence
    if (/^```/.test(trimmed)) {
      const lang = trimmed.slice(3).trim();
      const buf = [];
      i++;
      while (i < lines.length && !/^```/.test(lines[i].trim())) buf.push(lines[i++]);
      i++; // 閉じ fence
      const cls = lang ? ` class="language-${lang}"` : '';
      out.push(`<pre><code${cls}>${highlightCode(lang, buf.join('\n'))}</code></pre>`);
      continue;
    }

    // ::: block
    if (/^:::/.test(trimmed)) {
      const kind = trimmed.slice(3).trim().split(/\s+/)[0];
      const buf = [];
      i++;
      while (i < lines.length && lines[i].trim() !== ':::') buf.push(lines[i++]);
      i++; // 閉じ :::
      out.push(renderFenced(kind, buf));
      continue;
    }

    // heading
    const h = trimmed.match(/^(#{1,4})\s+(.*)$/);
    if (h) {
      const level = Math.max(2, h[1].length); // h1 は script が hero に使うため本文では作らない
      out.push(`<h${level}>${inline(h[2])}</h${level}>`);
      i++;
      continue;
    }

    // hr
    if (/^-{3,}$/.test(trimmed)) { out.push('<hr>'); i++; continue; }

    // table
    if (/^\|.*\|$/.test(trimmed)) {
      const buf = [];
      while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) buf.push(lines[i++]);
      out.push(renderTable(buf));
      continue;
    }

    // blockquote
    if (/^>\s?/.test(trimmed)) {
      const buf = [];
      while (i < lines.length && /^\s*>\s?/.test(lines[i])) buf.push(lines[i++].replace(/^\s*>\s?/, ''));
      out.push(`<blockquote><p>${inline(buf.join(' '))}</p></blockquote>`);
      continue;
    }

    // list
    if (/^\s*([-*]|\d+\.)\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\s*([-*]|\d+\.)\s+/.test(lines[i])) {
        const l = lines[i];
        const m = l.match(/^\s*([-*]|\d+\.)\s+(.*)$/);
        items.push({ depth: indentOf(l), ordered: /\d/.test(m[1]), text: m[2] });
        i++;
      }
      out.push(renderList(items));
      continue;
    }

    // paragraph
    const buf = [];
    while (i < lines.length && lines[i].trim() !== '' &&
           !/^(#{1,4}\s|```|:::|>|\s*([-*]|\d+\.)\s|\s*\|)/.test(lines[i])) {
      buf.push(lines[i++].trim());
    }
    out.push(`<p>${inline(buf.join(' '))}</p>`);
  }
  return out.join('\n');
}

// ---------- output path ----------

function resolveOut(opts) {
  let out = opts.out;
  if (!out) die('--out が無い');
  if (!out.endsWith('.html')) out += '.html';

  if (out.includes('/')) return path.join(ROOT, out);

  if (opts.project) {
    const dir = path.join(ROOT, 'projects');
    const prefix = `${opts.project}-`;
    const hit = fs.existsSync(dir)
      ? fs.readdirSync(dir, { withFileTypes: true })
          .filter(e => e.isDirectory() && e.name.startsWith(prefix))
          .map(e => e.name)[0]
      : undefined;
    if (hit) return path.join(dir, hit, out);
    if (!opts.slug) die(`projects/${prefix}* が無い。新規 PJ なら --slug <topic> を添える`);
    return path.join(dir, `${opts.project}-${opts.slug}`, out);
  }

  return path.join(ROOT, 'guides', out);
}

// ---------- template ----------

function buildMetaHeader(type, opts) {
  const day = nowMinute();
  const meta = [
    `<!-- type: ${type} -->`,
    `<!-- status: ${opts.status || 'active'} -->`,
    `<!-- created: ${day} -->`,
    `<!-- updated: ${day} -->`,
  ];
  const key = DATE_META[type];
  if (key) {
    const val = opts[key];
    if (!val) die(`type: ${type} には --${key} が必須`);
    meta.push(`<!-- ${key}: ${val} -->`);
  }
  return meta.join('\n');
}

function fillTemplate(tpl, { type, title, lead, body, opts }) {
  // 1. metadata header を先頭から差し替える (<!DOCTYPE html> の前が canonical 位置)
  const doctypeAt = tpl.indexOf('<!DOCTYPE html>');
  if (doctypeAt < 0) die('template に <!DOCTYPE html> が無い');
  let html = buildMetaHeader(type, opts) + '\n' + tpl.slice(doctypeAt);

  // 2. title
  html = html.replace(/<title>[\s\S]*?<\/title>/, `<title>${escapeHtml(title)}</title>`);

  // 3. body: <body> と <script id="local-docs-script"> の間を丸ごと差し替える
  //    (style / script は template の資産なので触らない)
  const bodyStart = html.indexOf('<body>');
  const scriptStart = html.indexOf('<script id="local-docs-script">');
  if (bodyStart < 0 || scriptStart < 0) die('template の <body> / <script id="local-docs-script"> が見つからない');
  const head = `<h1>${escapeHtml(title)}</h1>`;
  const leadHtml = lead ? `\n<p>${inline(lead)}</p>` : '';
  return html.slice(0, bodyStart + '<body>'.length) +
    `\n${head}${leadHtml}\n${body}\n` +
    html.slice(scriptStart);
}

// ---------- main ----------

const opts = parseArgs(process.argv.slice(2));

const type = opts.type;
if (!type) die('--type が無い');
if (!TYPES.includes(type)) die(`--type は ${TYPES.join(' | ')} のいずれか (指定: ${type})`);
if (!opts.title) die('--title が無い');

const tplPath = path.join(TEMPLATES, `${type}.html`);
if (!fs.existsSync(tplPath)) die(`template が無い: ${path.relative(ROOT, tplPath)}`);

// 本文: --md (file か '-' で stdin) / --body (HTML fragment file)
let body;
if (opts.md !== undefined) {
  const md = opts.md === '-' ? fs.readFileSync(0, 'utf8') : fs.readFileSync(opts.md, 'utf8');
  body = mdToHtml(md);
} else if (opts.body !== undefined) {
  body = fs.readFileSync(opts.body, 'utf8').trim();
} else {
  die('--md か --body が無い');
}

const outPath = resolveOut(opts);
if (fs.existsSync(outPath) && !opts.force) {
  die(`既に存在する: ${path.relative(ROOT, outPath)} (上書きは --force)`);
}

const html = fillTemplate(fs.readFileSync(tplPath, 'utf8'), {
  type, title: opts.title, lead: opts.lead, body, opts,
});

fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, html);

// placeholder 残数 (style / script を除いた範囲で数える)
const scanned = html.slice(html.indexOf('<body>'), html.indexOf('<script id="local-docs-script">'));
const left = (scanned.match(/\{[^}\n]{2,}\}/g) || []).length;

console.log(`created: ${path.relative(ROOT, outPath)}`);
console.log(`placeholder 残 ${left}`);

// 生成直後の構造 self-check (skill `local-docs` Step 6 相当をここで吸収する)
const checks = [
  ['metadata type 先頭', /^<!-- type: [\w-]+ -->/.test(html)],
  ['metadata status', /<!-- status: [\w-]+ -->/.test(html)],
  ['metadata created', /<!-- created: \d{4}-\d{2}-\d{2} \d{2}:\d{2} -->/.test(html)],
  ['style 保持', html.includes('<style id="local-docs-style">')],
  ['script 保持', html.includes('<script id="local-docs-script">')],
];
const failed = checks.filter(([, ok]) => !ok).map(([name]) => name);
if (failed.length) {
  console.error(`self-check NG: ${failed.join(' / ')}`);
  process.exit(1);
}
console.log('self-check: ok');

const buildScript = path.join(ROOT, '_index', 'build-index.mjs');
if (fs.existsSync(buildScript)) {
  const built = spawnSync(process.execPath, [buildScript], { cwd: ROOT, encoding: 'utf8' });
  if (built.status !== 0) {
    console.error('build-index.mjs 失敗:');
    console.error(built.stderr || built.stdout);
    process.exit(1);
  }
  console.log('build: ok');
} else {
  console.log('build: skip (build-index.mjs なし)');
}

// トップページ (index.html) を再生成して、起こした doc を一覧へ載せる
const indexScript = path.join(ROOT, '_index', 'build-index.mjs');
if (fs.existsSync(indexScript)) {
  const built = spawnSync(process.execPath, [indexScript], { cwd: ROOT, encoding: 'utf8' });
  if (built.status !== 0) {
    console.error('build-index.mjs 失敗:');
    console.error(built.stderr || built.stdout);
    process.exit(1);
  }
  console.log(built.stdout.trim());
  // build-index は規約違反の走査を exit 0 のまま stderr へ出力する。
  // doc を起こした直後は違反を新しく記載した瞬間なので、ここで必ず転送する。
  if (built.stderr && built.stderr.trim()) console.error(built.stderr.trimEnd());
}
