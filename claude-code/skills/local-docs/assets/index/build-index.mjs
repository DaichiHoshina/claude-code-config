#!/usr/bin/env node
// build-index.mjs — 置き場のトップページ (index.html) を doc から組み立てる
// Run from local-docs root: node _index/build-index.mjs
//
// guides/*.html と notes/*.md を読んで、title / リード / metadata を拾い、
// dir ごとの card 一覧にする。共有 CSS は _index/style.css をそのまま埋める。

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const CSS = fs.readFileSync(path.join(import.meta.dirname, 'style.css'), 'utf8').replace(/\n+$/, '');
const OUT = path.join(ROOT, 'index.html');

const GROUPS = [
  { dir: 'guides', label: '読み返すもの', note: '使い方・手順・まとめ' },
  { dir: 'notes', label: '書き捨てるもの', note: '調査メモ・試行錯誤・作業ログ' },
  { dir: 'archive', label: '古くなったもの', note: '別の置き場へ移した後の抜け殻' },
];

const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// 並べ替えは分単位で行うため、日付を「YYYY-MM-DD HH:MM」にそろえる。
// 時刻の無い日付はその日の 00:00 として扱い、表示では時刻を付けない (updatedHasTime)
const minute = v => {
  const m = String(v || '').trim().match(/^(\d{4}-\d{2}-\d{2})(?:[ T](\d{1,2}):(\d{2}))?/);
  if (!m) return { at: '', hasTime: false };
  return m[2] ? { at: `${m[1]} ${m[2].padStart(2, '0')}:${m[3]}`, hasTime: true } : { at: `${m[1]} 00:00`, hasTime: false };
};
// job が毎日追記する doc (since-cursor を持つ) は、中身が変わらない日も updated が今日になり、
// 更新順で常に先頭に来る。並べ替えには created を使い (sortUpdated)、カード一覧には表示しない
const stamps = (updated, created, recurring = false) => {
  const u = minute(updated), c = minute(created);
  return { updated: u.at, updatedHasTime: u.hasTime, created: c.at, recurring, sortUpdated: recurring ? c.at : u.at };
};

function readHtmlDoc(file) {
  const src = fs.readFileSync(file, 'utf8');
  const meta = k => (src.match(new RegExp(`<!--\\s*${k}:\\s*([^>]*?)\\s*-->`)) || [])[1] || '';
  const title = (src.match(/<title[^>]*>([^<]+)<\/title>/i) || [])[1]
    || (src.match(/<h1[^>]*>([^<]+)<\/h1>/i) || [])[1] || path.basename(file);
  const body = src.slice(src.indexOf('<body>'));
  const lead = (body.match(/<h1[^>]*>[^<]*<\/h1>\s*<p>([\s\S]*?)<\/p>/i) || [])[1] || '';
  const headings = [...body.matchAll(/<h2[^>]*>([\s\S]*?)<\/h2>/gi)]
    .map(m => m[1].replace(/<[^>]*>/g, '').replace(/#\s*$/, '').trim())
    .filter(Boolean);
  return {
    title: title.trim(),
    lead: lead.replace(/<[^>]*>/g, '').trim(),
    type: meta('type'), ...stamps(meta('updated') || meta('created'), meta('created') || meta('updated'), !!meta('since-cursor')),
    headings,
  };
}

function readMdDoc(file) {
  const src = fs.readFileSync(file, 'utf8');
  const fm = (src.match(/^---\n([\s\S]*?)\n---/) || [])[1] || '';
  const fmv = k => (fm.match(new RegExp(`^${k}:\\s*(.+)$`, 'm')) || [])[1] || '';
  const bodyStart = fm ? src.indexOf('---', 3) + 4 : 0;
  const body = src.slice(bodyStart);
  const title = (body.match(/^#\s+(.+)$/m) || [])[1] || path.basename(file, '.md');
  const lines = body.split('\n').map(l => l.trim()).filter(Boolean);
  const lead = (lines.find(l => !l.startsWith('#') && !l.startsWith('-'))
    || (lines.find(l => l.startsWith('- ')) || '').replace(/^-\s*/, '')
    || '').replace(/[*`]/g, '');
  return {
    title: title.trim(), lead,
    type: fmv('type'), ...stamps(fmv('updated') || fmv('created'), fmv('created') || fmv('updated'), !!fmv('since-cursor')),
    // md は browser 上で見出しの anchor を持たないので、入れ子のリンクは作らない
    headings: [],
  };
}

// guides/projects/<issue>/ のような入れ子の dir も一覧に含める。
// `_` / `.` で始まる dir は asset 置き場なので対象外にする
function collect(dir) {
  const full = path.join(ROOT, dir);
  if (!fs.existsSync(full)) return [];
  return fs.readdirSync(full, { withFileTypes: true })
    .flatMap(e => {
      const rel = `${dir}/${e.name}`;
      if (e.isDirectory()) return /^[_.]/.test(e.name) || e.name === 'node_modules' ? [] : collect(rel);
      if (!(e.name.endsWith('.html') || e.name.endsWith('.md'))) return [];
      const file = path.join(ROOT, rel);
      const doc = e.name.endsWith('.md') ? readMdDoc(file) : readHtmlDoc(file);
      return [{ ...doc, href: rel, name: e.name }];
    })
    .sort((a, b) => (b.sortUpdated || '').localeCompare(a.sortUpdated || ''));
}

const groups = GROUPS.map(g => ({ ...g, docs: collect(g.dir) }));
const total = groups.reduce((n, g) => n + g.docs.length, 0);

// sidebar: 分類 → dir → doc。JS を使わず details で開閉する。
// doc の見出しまで並べると 200 本で 1500 行を超えて読めないため、doc は 1 行のリンクにする。
// 長い title は 1 行で省略し、全文は title 属性で hover 時に表示する
const isEntry = d => /^(README|index)\.(html|md)$/.test(d.name);
const navDoc = d => `        <a class="nav-link${isEntry(d) ? ' nav-link-entry' : ''}" href="${esc(d.href)}" title="${esc(d.title)}" data-q="${esc(`${d.title} ${d.lead} ${d.href}`.toLowerCase())}" data-lead="${esc(d.lead)}" data-path="${esc(d.href)}" data-updated="${esc(d.sortUpdated || '')}" data-created="${esc(d.created || '')}"><span class="nav-label">${esc(isEntry(d) ? '概要' : d.title)}</span></a>`;

// dir の表示名は README の title を使う (dir 名は 30472-oripa-... のような slug で読みにくい)
const dirLabel = (name, node) => {
  const entry = node.docs.find(isEntry);
  const t = entry ? entry.title.replace(/\s*(概要|README)\s*$/, '').trim() : '';
  return t && t !== name ? t : name;
};
const buildTree = (docs, base) => {
  const root = { dirs: new Map(), docs: [] };
  for (const d of docs) {
    const parts = d.href.slice(base.length + 1).split('/').slice(0, -1);
    let node = root;
    for (const p of parts) {
      if (!node.dirs.has(p)) node.dirs.set(p, { dirs: new Map(), docs: [] });
      node = node.dirs.get(p);
    }
    node.docs.push(d);
  }
  return root;
};
const countDocs = n => n.docs.length + [...n.dirs.values()].reduce((s, c) => s + countDocs(c), 0);
// 分類直下の dir (projects / domain-specs 等) だけ最初から開き、2 段目の一覧が見える状態にする
// dir の日付は中の doc の最新日付とする (更新順 / 作成順で dir ごと並べ替えるため)
const latest = (n, key) => [...n.docs.map(d => d[key] || ''), ...[...n.dirs.values()].map(c => latest(c, key))]
  .reduce((a, b) => (a > b ? a : b), '');
// 既定は更新日の新しい順。doc と dir を混ぜて並べ、README / index (概要) だけ先頭に固定する。
// JS が動かない環境でもこの順で表示され、sidebar の切り替えは browser 側で同じ規則で並べ替える
const navTree = (n, depth = 0) => [
  ...n.docs.map(d => ({ entry: isEntry(d), date: d.sortUpdated || '', html: navDoc(d) })),
  ...[...n.dirs.entries()].map(([name, child]) => ({ entry: false, date: latest(child, 'sortUpdated'), html: `        <details class="nav-dir"${depth === 0 ? ' open' : ''} data-updated="${esc(latest(child, 'sortUpdated'))}" data-created="${esc(latest(child, 'created'))}">
          <summary title="${esc(name)}"><span class="nav-dir-name">${esc(dirLabel(name, child))}</span><span class="nav-dir-count">${countDocs(child)}</span></summary>
          <div class="nav-dir-body">
${navTree(child, depth + 1)}
          </div>
        </details>` })),
].sort((a, b) => (b.entry - a.entry) || b.date.localeCompare(a.date)).map(x => x.html).join('\n');

const navGroup = g => `      <div class="nav-group">
        <p class="nav-group-label">${esc(g.label)}</p>
${g.docs.length ? navTree(buildTree(g.docs, g.dir)) : '        <p class="nav-empty">まだ無い</p>'}
      </div>`;

// カードの上に所属する dir を sidebar と同じ表示名で並べる (例: projects 一覧 › サイズ選択 › release)
const dirLabels = (node, base, out = new Map()) => {
  for (const [name, child] of node.dirs) {
    const rel = `${base}/${name}`;
    out.set(rel, dirLabel(name, child));
    dirLabels(child, rel, out);
  }
  return out;
};
const crumbsOf = (d, g, labels) => {
  const parts = d.href.split('/').slice(1, -1);
  return parts.map((_, i) => labels.get([g.dir, ...parts.slice(0, i + 1)].join('/')));
};
// 時刻を持つ doc は分まで、日付だけの doc は日付だけを表示する
const day = v => (v || '').slice(0, 10);
// 00:00 は時刻が分からない doc に入れた仮の値なので、日付だけを表示する
const shown = d => (d.updatedHasTime && !d.updated.endsWith(' 00:00') ? d.updated : day(d.updated));

// doc の種類ごとのラベル色 [背景, 文字]。文字色は背景に対して WCAG AA (4.5:1) 以上の濃さにする。
// ここに無い種類は灰色 (doc-type-other) で表示する
const TYPE_COLORS = {
  report: ['#E8F0FE', '#1A56DB'],
  spec: ['#F1EBFF', '#6D28D9'],
  guide: ['#E6F6EC', '#11693A'],
  investigation: ['#FFF1E6', '#C2410C'],
  plan: ['#E0F5F4', '#0F766E'],
  log: ['#E6F4FA', '#0369A1'],
  decision: ['#FCE8F3', '#BE185D'],
  runbook: ['#FEF6DC', '#8A5A00'],
  postmortem: ['#FDECEC', '#B91C1C'],
  index: ['#F1F3F5', '#495057'],
};
const typeColorCss = Object.entries(TYPE_COLORS)
  .map(([t, [bg, fg]]) => `.doc-type-${t} { background: ${bg}; color: ${fg}; }`)
  .join('\n');

// path のコピーボタンは a の中に置けない (入れ子の操作要素になる) ため、カードと並べて wrapper に置く
const card = (d, crumbs) => `      <div class="doc-card-wrap">
      <a class="doc-card" href="${esc(d.href)}" data-q="${esc(`${d.title} ${d.lead} ${d.href}`.toLowerCase())}">
        ${crumbs.length ? `<span class="doc-card-crumbs">${crumbs.map(esc).join('<span class="doc-card-sep">›</span>')}</span>` : ''}
        <span class="doc-card-title">${esc(d.title)}</span>
        ${d.lead ? `<span class="doc-card-lead">${esc(d.lead)}</span>` : ''}
        <span class="doc-card-meta">${d.type ? `<span class="pill doc-type ${TYPE_COLORS[d.type] ? `doc-type-${esc(d.type)}` : 'doc-type-other'}">${esc(d.type)}</span>` : ''}${d.updated ? `<span>更新 ${esc(shown(d))}</span>` : ''}</span>
      </a>
      <button type="button" class="doc-card-copy" data-href="${esc(d.href)}" title="file の path をコピー (Raycast / Finder に貼る)">path をコピー</button>
      </div>`;

// 200 本を 1 面に並べると区切りが無く目で追えないため、更新月ごとに見出しを置く
const monthLabel = m => (m ? `${m.slice(0, 4)}年${Number(m.slice(5, 7))}月` : '日付なし');
const section = g => {
  const labels = dirLabels(buildTree(g.docs, g.dir), g.dir);
  const months = new Map();
  for (const d of g.docs.filter(x => !x.recurring)) {
    const m = day(d.updated).slice(0, 7);
    if (!months.has(m)) months.set(m, []);
    months.get(m).push(d);
  }
  const body = [...months.entries()].map(([m, docs]) => `      <div class="doc-month">
        <h3 class="doc-month-label">${monthLabel(m)}<span class="doc-month-count">${docs.length} 件</span></h3>
        <div class="doc-grid">
${docs.map(d => card(d, crumbsOf(d, g, labels))).join('\n')}
        </div>
      </div>`).join('\n');
  return `    <section class="doc-group">
      <h2>${esc(g.label)}<span class="doc-group-note">${esc(g.note)}</span></h2>
${g.docs.length ? body : '      <p class="doc-empty">まだ無い</p>'}
    </section>`;
};

// 検索: 入力した語をすべて含む doc だけを sidebar とカード一覧に残し、一致した語を mark で強調する。
// title 以外 (本文の冒頭 / path) で一致した doc は、sidebar の title の下に一致した箇所を 1 行で表示する。
// 一致した doc を含む dir は開き、検索欄を空にすると最初の開閉状態へ戻す
// build 時の template literal に直接書くと ${} と \ が解釈されるため、関数として書いて toString() で埋め込む
function clientSearch() {
  const input = document.getElementById('doc-search');
  const status = document.getElementById('doc-search-status');
  const dirs = [...document.querySelectorAll('.nav-dir')];
  const initialOpen = dirs.map(d => d.open);
  const escHtml = t => t.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
  const reEsc = w => w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const mark = (text, words) => words.length
    ? escHtml(text).replace(new RegExp(words.map(w => reEsc(escHtml(w))).join('|'), 'gi'), m => `<mark>${m}</mark>`)
    : escHtml(text);
  // 一致した語の前後 24 字を切り出す
  const snippet = (text, words) => {
    const lower = text.toLowerCase();
    const at = Math.min(...words.map(w => lower.indexOf(w)).filter(i => i >= 0));
    const from = Math.max(0, at - 24);
    return (from > 0 ? '…' : '') + text.slice(from, at + 48);
  };
  const origin = new Map();
  const keep = el => { if (!origin.has(el)) origin.set(el, el.textContent); return origin.get(el); };

  const run = () => {
    const words = input.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
    const hit = el => words.every(w => el.dataset.q.includes(w));
    let count = 0;
    document.querySelectorAll('.nav-link[data-q]').forEach(a => {
      const ok = !words.length || hit(a);
      a.classList.toggle('is-hidden', !ok);
      a.querySelector('.nav-hit')?.remove();
      const label = a.querySelector('.nav-label');
      const text = keep(label);
      label.innerHTML = mark(text, words);
      if (!ok || !words.length) return;
      count++;
      const title = a.title.toLowerCase();
      const rest = words.filter(w => !title.includes(w));
      if (!rest.length) return;
      const lead = a.dataset.lead || '';
      const inLead = rest.some(w => lead.toLowerCase().includes(w));
      const src = inLead ? lead : a.dataset.path;
      a.insertAdjacentHTML('beforeend',
        `<span class="nav-hit"><span class="nav-hit-kind">${inLead ? '本文' : 'path'}</span>${mark(snippet(src, rest), words)}</span>`);
    });
    [...dirs].reverse().forEach((d, i) => {
      const visible = d.querySelector('.nav-link:not(.is-hidden)');
      d.classList.toggle('is-hidden', !visible);
      d.open = words.length ? !!visible : initialOpen[dirs.length - 1 - i];
      // 検索中は dir の本数を一致した本数に差し替える
      const badge = d.querySelector(':scope > summary .nav-dir-count');
      const total = keep(badge);
      badge.textContent = words.length ? d.querySelectorAll('.nav-link:not(.is-hidden)').length : total;
    });
    document.querySelectorAll('.doc-card[data-q]').forEach(c => {
      c.classList.toggle('is-hidden', !!words.length && !hit(c));
      c.querySelectorAll('.doc-card-title, .doc-card-lead').forEach(el => { el.innerHTML = mark(keep(el), words); });
    });
    document.querySelectorAll('.doc-month').forEach(m => m.classList.toggle('is-hidden', !!words.length && !m.querySelector('.doc-card:not(.is-hidden)')));
    document.querySelectorAll('.doc-group').forEach(g => g.classList.toggle('is-hidden', !!words.length && !g.querySelector('.doc-card:not(.is-hidden)')));
    status.hidden = !words.length;
    status.innerHTML = count ? `<strong>${count}</strong> 件が一致` : '一致する doc はありません';
  };
  input.addEventListener('input', run);
  // 検索中は一致した doc を含む dir (非表示でない dir) だけを対象にする
  // 並び順: 各階層 (分類直下と dir の中) で、doc と dir を選んだ日付の新しい順に並べ替える。概要は先頭に固定する
  const SORT_KEY = 'local-docs-nav-sort';
  const sortButtons = [...document.querySelectorAll('.nav-sort button')];
  const applySort = key => {
    sortButtons.forEach(b => b.setAttribute('aria-pressed', String(b.dataset.sort === key)));
    document.querySelectorAll('.nav-group, .nav-dir-body').forEach(box => {
      const items = [...box.children].filter(el => el.matches('.nav-link, .nav-dir'));
      if (!items.length) return;
      const anchor = items[items.length - 1].nextSibling;
      items
        .sort((a, b) => (b.classList.contains('nav-link-entry') - a.classList.contains('nav-link-entry'))
          || (b.dataset[key] || '').localeCompare(a.dataset[key] || ''))
        .forEach(el => box.insertBefore(el, anchor));
    });
  };
  sortButtons.forEach(b => b.addEventListener('click', () => {
    applySort(b.dataset.sort);
    try { localStorage.setItem(SORT_KEY, b.dataset.sort); } catch {}
  }));
  try { const saved = localStorage.getItem(SORT_KEY); if (saved === 'created') applySort(saved); } catch {}

  // path のコピー: 個人の path を HTML に書かないよう、開いている page の URL から絶対 path を組み立てる
  const copyText = async text => {
    try { await navigator.clipboard.writeText(text); return true; } catch {}
    const ta = Object.assign(document.createElement('textarea'), { value: text });
    document.body.append(ta); ta.select();
    const ok = document.execCommand('copy'); ta.remove(); return ok;
  };
  document.querySelectorAll('.doc-card-copy').forEach(btn => btn.addEventListener('click', async () => {
    const path = decodeURIComponent(new URL(btn.dataset.href, location.href).pathname);
    const ok = await copyText(path);
    btn.textContent = ok ? 'コピーしました' : 'コピーできません';
    btn.classList.toggle('is-done', ok);
    clearTimeout(btn.timer);
    btn.timer = setTimeout(() => { btn.textContent = 'path をコピー'; btn.classList.remove('is-done'); }, 1500);
  }));

  const toggleAll = open => dirs.forEach(d => { if (!d.classList.contains('is-hidden')) d.open = open; });
  document.getElementById('nav-open-all').addEventListener('click', () => toggleAll(true));
  document.getElementById('nav-close-all').addEventListener('click', () => toggleAll(false));

  // sidebar の幅: 境目のドラッグで 200-600px の範囲で変え、localStorage に保存する。
  // 保存できない環境 (private window 等) でも既定の 300px で表示されるよう、読み書きは try で囲む
  const root = document.documentElement;
  const resizer = document.getElementById('nav-resizer');
  const KEY = 'local-docs-nav-width';
  const setWidth = w => root.style.setProperty('--nav-width', `${Math.min(600, Math.max(200, w))}px`);
  try { const saved = Number(localStorage.getItem(KEY)); if (saved) setWidth(saved); } catch {}
  let dragging = false;
  resizer.addEventListener('pointerdown', e => {
    e.preventDefault();
    dragging = true;
    try { resizer.setPointerCapture(e.pointerId); } catch {}
    resizer.classList.add('is-dragging');
    document.body.classList.add('is-resizing');
  });
  resizer.addEventListener('pointermove', e => { if (dragging) setWidth(e.clientX); });
  resizer.addEventListener('pointerup', e => {
    if (!dragging) return;
    dragging = false;
    try { resizer.releasePointerCapture(e.pointerId); } catch {}
    resizer.classList.remove('is-dragging');
    document.body.classList.remove('is-resizing');
    try { localStorage.setItem(KEY, parseInt(getComputedStyle(root).getPropertyValue('--nav-width'), 10)); } catch {}
  });
  resizer.addEventListener('dblclick', () => {
    root.style.removeProperty('--nav-width');
    try { localStorage.removeItem(KEY); } catch {}
  });
  document.addEventListener('keydown', e => {
    if (e.key === '/' && document.activeElement !== input) { e.preventDefault(); input.focus(); }
    if (e.key === 'Escape' && document.activeElement === input) { input.value = ''; run(); input.blur(); }
  });
}

// tab で他の page と見分けるための icon。file を増やさないよう SVG を data URI で埋め込む
const FAVICON = 'data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 64 64%22%3E%3Crect width=%2264%22 height=%2264%22 rx=%2214%22 fill=%22%230070F3%22/%3E%3Crect x=%2221%22 y=%2212%22 width=%2228%22 height=%2236%22 rx=%224%22 fill=%22%23fff%22 opacity=%22.45%22/%3E%3Crect x=%2215%22 y=%2217%22 width=%2228%22 height=%2236%22 rx=%224%22 fill=%22%23fff%22/%3E%3Crect x=%2221%22 y=%2226%22 width=%2216%22 height=%223.5%22 rx=%221.75%22 fill=%22%230070F3%22/%3E%3Crect x=%2221%22 y=%2233%22 width=%2216%22 height=%223.5%22 rx=%221.75%22 fill=%22%230070F3%22/%3E%3Crect x=%2221%22 y=%2240%22 width=%2210%22 height=%223.5%22 rx=%221.75%22 fill=%22%230070F3%22/%3E%3C/svg%3E';

const html = `<!-- type: index -->
<!-- status: active -->
<!-- generated: ${new Date().toLocaleDateString('sv-SE')} -->
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>local-docs</title>
<link rel="icon" href="${FAVICON}">
<style id="local-docs-style">
${CSS}
</style>
<style id="local-docs-index-style">
body { padding: 0; }

/* 2 カラム: 左に追従 sidebar、右に一覧 */
.index-layout { display: grid; grid-template-columns: var(--nav-width, 300px) 1fr; align-items: start; }
.nav-resizer {
  position: fixed; top: 0; bottom: 0; left: calc(var(--nav-width, 300px) - 3px); width: 6px;
  cursor: col-resize; z-index: 10;
}
.nav-resizer:hover, .nav-resizer.is-dragging { background: var(--primary-soft); box-shadow: inset -2px 0 0 var(--primary); }
body.is-resizing { cursor: col-resize; user-select: none; }
.index-nav {
  position: sticky; top: 0; height: 100vh; overflow-y: auto;
  border-right: 1px solid var(--border); background: var(--surface-card);
  padding: 24px 16px 40px;
}
.nav-home {
  display: flex; align-items: center; gap: 10px; color: var(--grey-800);
  text-decoration: none; padding: 0 8px; margin-bottom: 24px;
}
.nav-logo { flex: none; display: block; border-radius: 7px; }
.nav-wordmark { font-size: 17px; font-weight: 700; letter-spacing: -0.02em; line-height: 1; }
.nav-wordmark-sub { color: var(--primary); }
.nav-search {
  display: block; width: 100%; box-sizing: border-box; margin: 0 0 20px; padding: 8px 12px;
  font: inherit; font-size: 13px; color: var(--grey-800); background: var(--surface-card);
  border: 1px solid var(--border); border-radius: 8px; outline: none;
}
.nav-search:focus { border-color: var(--primary); box-shadow: 0 0 0 3px var(--primary-soft); }
.nav-search-status { font-size: 12px; color: var(--grey-500); margin: -12px 0 16px; padding: 0 8px; }
.nav-search-status strong { color: var(--primary); }
mark { background: #fde68a; color: inherit; border-radius: 2px; padding: 0 1px; }
.nav-label { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.nav-hit {
  display: block; font-size: 11px; color: var(--grey-500); font-style: normal;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.nav-hit-kind { color: var(--grey-400); margin-right: 4px; }
.is-hidden { display: none !important; }
.nav-sort { display: flex; margin: 0 0 8px; border: 1px solid var(--border); border-radius: 6px; overflow: hidden; }
.nav-sort button {
  flex: 1; padding: 5px 8px; font: inherit; font-size: 12px; color: var(--grey-500);
  background: var(--surface-card); border: none; cursor: pointer;
}
.nav-sort button + button { border-left: 1px solid var(--border); }
.nav-sort button[aria-pressed="true"] { background: var(--primary-soft); color: var(--primary); font-weight: 600; }
.nav-toggle { display: flex; gap: 6px; margin: 0 0 16px; }
.nav-toggle button {
  flex: 1; padding: 5px 8px; font: inherit; font-size: 12px; color: var(--grey-600);
  background: var(--surface-card); border: 1px solid var(--border); border-radius: 6px; cursor: pointer;
}
.nav-toggle button:hover { border-color: var(--primary); color: var(--primary); background: var(--primary-soft); }
.nav-group { margin-bottom: 20px; }
.nav-group-label {
  font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: .08em;
  color: var(--grey-400); margin: 0 0 6px; padding: 0 8px;
}
.nav-doc > summary {
  list-style: none; cursor: pointer; display: flex; align-items: center; gap: 6px;
  padding: 7px 8px; border-radius: 8px; font-size: 13px; color: var(--grey-700);
  transition: background-color .12s ease;
}
.nav-doc > summary::-webkit-details-marker { display: none; }
.nav-doc > summary::before {
  content: "›"; color: var(--grey-400); font-size: 14px; line-height: 1;
  transition: transform .12s ease; transform-origin: center;
}
.nav-doc[open] > summary::before { transform: rotate(90deg); }
.nav-doc > summary:hover { background: var(--grey-50); }
.nav-doc > summary a { color: inherit; text-decoration: none; }
.nav-doc ul { list-style: none; margin: 2px 0 6px; padding: 0 0 0 22px; }
.nav-doc li { margin: 0; max-width: none; }
.nav-doc li a {
  display: block; padding: 5px 8px; border-radius: 6px;
  font-size: 12px; line-height: 1.5; color: var(--grey-500); text-decoration: none;
  transition: background-color .12s ease, color .12s ease;
}
.nav-doc li a:hover { background: var(--primary-soft); color: var(--primary); }
.nav-flat {
  display: block; padding: 7px 8px; border-radius: 8px;
  font-size: 13px; color: var(--grey-700); text-decoration: none;
}
.nav-flat:hover { background: var(--grey-50); }
.nav-flat-doc { font-size: 13px; padding-left: 22px; }
.nav-dir { margin: 1px 0; }
.nav-dir > summary {
  list-style: none; cursor: pointer; display: flex; align-items: center; gap: 6px;
  padding: 6px 8px; border-radius: 6px; font-size: 13px; font-weight: 600; color: var(--grey-800);
}
.nav-dir > summary::-webkit-details-marker { display: none; }
.nav-dir > summary::before {
  content: "▸"; flex: none; width: 12px; color: var(--grey-500); font-size: 12px; line-height: 1;
  transition: transform .12s ease; transform-origin: center;
}
.nav-dir[open] > summary::before { transform: rotate(90deg); }
.nav-dir > summary:hover { background: var(--grey-50); }
.nav-dir-name { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.nav-dir-count {
  margin-left: auto; flex: none; font-size: 11px; font-weight: 500; color: var(--grey-500);
  background: var(--grey-50); border-radius: 999px; padding: 1px 7px;
}
.nav-dir-body { padding-left: 8px; border-left: 1px solid var(--border); margin: 2px 0 6px 13px; }
.nav-link {
  display: block; padding: 4px 8px; border-radius: 6px;
  font-size: 12.5px; line-height: 1.5; color: var(--grey-600); text-decoration: none;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.nav-link:hover { background: var(--primary-soft); color: var(--primary); }
.nav-link-entry { color: var(--grey-500); font-style: italic; }
.nav-empty { font-size: 12px; color: var(--grey-400); margin: 0; padding: 4px 8px; }

.index-main { padding: 40px 40px 80px; max-width: 1100px; }
.index-head { margin-bottom: 40px; }
.index-head h1 { font-size: 24px; font-weight: 600; letter-spacing: -0.02em; margin: 0 0 8px; }
.index-head p { font-size: 14px; color: var(--grey-500); margin: 0; }
.doc-group { background: none; border: none; padding: 0; margin: 0 0 32px; }
.doc-group h2 {
  font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: .08em;
  color: var(--grey-500); margin: 0 0 16px; display: flex; align-items: baseline; gap: 10px;
}
.doc-group-note { font-size: 11px; font-weight: 400; letter-spacing: 0; text-transform: none; color: var(--grey-400); }
.doc-month { margin: 0 0 28px; }
.doc-month-label {
  display: flex; align-items: baseline; gap: 8px; margin: 0 0 12px; padding-bottom: 6px;
  font-size: 14px; font-weight: 600; color: var(--grey-700); border-bottom: 1px solid var(--border);
}
.doc-month-count { font-size: 12px; font-weight: 400; color: var(--grey-400); }
.doc-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 12px; }
.doc-card-wrap { position: relative; display: flex; }
.doc-card-wrap:has(> .doc-card.is-hidden) { display: none; }
.doc-card-wrap > .doc-card { flex: 1; }
.doc-card-copy {
  position: absolute; right: 12px; bottom: 12px;
  padding: 3px 9px; font: inherit; font-size: 11px; color: var(--grey-500);
  background: var(--surface-card); border: 1px solid var(--border); border-radius: 6px; cursor: pointer;
  opacity: 0; transition: opacity .12s ease;
}
.doc-card-wrap:hover .doc-card-copy, .doc-card-copy:focus-visible, .doc-card-copy.is-done { opacity: 1; }
.doc-card-copy:hover { border-color: var(--primary); color: var(--primary); }
.doc-card-copy.is-done { border-color: var(--primary); color: var(--primary); background: var(--primary-soft); }
.doc-card {
  display: flex; flex-direction: column; gap: 6px;
  border: 1px solid var(--border); border-radius: 10px; background: var(--surface-card);
  padding: 16px 18px; text-decoration: none; color: inherit;
  transition: border-color .12s ease, background-color .12s ease, box-shadow .12s ease;
}
.doc-card:hover { border-color: var(--primary); box-shadow: 0 2px 8px rgba(0, 0, 0, .06); }
.doc-type { font-weight: 600; }
.doc-type-other { background: var(--grey-50); color: var(--grey-600); }
${typeColorCss}
.doc-card-crumbs {
  font-size: 11px; color: var(--grey-500);
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.doc-card-sep { margin: 0 5px; color: var(--grey-300, var(--grey-400)); }
.doc-card-title {
  font-size: 15px; font-weight: 600; line-height: 1.5; color: var(--grey-800);
  display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
}
.doc-card-lead {
  font-size: 13px; line-height: 1.65; color: var(--grey-600);
  display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
}
.doc-card-meta { display: flex; align-items: center; gap: 8px; font-size: 11px; color: var(--grey-500); margin-top: auto; padding-top: 4px; }
.doc-empty { font-size: 13px; color: var(--grey-400); margin: 0; }

@media (max-width: 900px) {
  .index-layout { grid-template-columns: 1fr; }
  .nav-resizer { display: none; }
  .index-nav { position: static; height: auto; border-right: none; border-bottom: 1px solid var(--border); }
  .index-main { padding: 24px 20px 60px; }
}
</style>
</head>
<body>
<div class="index-layout">
  <aside class="index-nav">
    <a class="nav-home" href="index.html" aria-label="local-docs トップ">
      <img class="nav-logo" src="${FAVICON}" alt="" width="28" height="28">
      <span class="nav-wordmark">local<span class="nav-wordmark-sub">-docs</span></span>
    </a>
    <input class="nav-search" id="doc-search" type="search" placeholder="doc を検索 (title / 本文の冒頭 / path)" autocomplete="off">
    <p class="nav-search-status" id="doc-search-status" hidden></p>
    <div class="nav-sort" role="group" aria-label="並び順">
      <button type="button" data-sort="updated" aria-pressed="true">更新順</button>
      <button type="button" data-sort="created" aria-pressed="false">作成順</button>
    </div>
    <div class="nav-toggle">
      <button type="button" id="nav-open-all">すべて開く</button>
      <button type="button" id="nav-close-all">すべて閉じる</button>
    </div>
${groups.map(navGroup).join('\n')}
    <div class="nav-group">
      <p class="nav-group-label">置き場について</p>
      <a class="nav-flat" href="README.html">規約と索引の作り</a>
    </div>
  </aside>
  <div class="nav-resizer" id="nav-resizer" title="ドラッグで幅を変更 (ダブルクリックで元の幅)"></div>
  <main class="index-main">
    <header class="index-head">
      <h1>local-docs</h1>
      <p>自分だけが読む置き場。いま ${total} 件。</p>
    </header>
${groups.map(section).join('\n')}
  </main>
</div>
<script>
(${clientSearch.toString()})();
</script>
</body>
</html>
`;

fs.writeFileSync(OUT, html);
console.log(`index: ${total} 件 (${groups.map(g => `${g.dir} ${g.docs.length}`).join(' / ')})`);

// 規約「個人名 / 会社名 / credential を記載しない」の後追い検査。
// file 単体で渡せる形式なので、書いた時点で個人用のつもりでもそのまま外部へ渡る。
// 検出語をこの script に literal で記載すると script 自身が違反するため、
// 実行時の環境 (user 名) と一般形 (絶対 path / 鍵の接頭辞) から組み立てる。
const user = os.userInfo().username.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const PATTERNS = [
  [new RegExp(`\\b${user}\\b`, 'i'), '実行 user 名'],
  [/\/Users\/[A-Za-z0-9._-]+/, '個人の絶対 path'],
  [/ghq\/github\.com\/[A-Za-z0-9-]+/, 'github account 名'],
  [/\b(ghp_|github_pat_|sk-|AKIA|ASIA)[A-Za-z0-9_-]{8,}/, 'credential らしき文字列'],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, '秘密鍵'],
];

// 走査は置き場全体を再帰でたどる。dir を列挙する形にすると、index に並ばない
// _templates (新しい doc の元になる) や、後から作る sub dir が対象から抜ける。
const hits = [];
const scan = dir => {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) { scan(file); continue; }
    if (!entry.isFile() || !/\.(html|md)$/.test(entry.name)) continue;
    const rel = path.relative(ROOT, file);
    fs.readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
      for (const [re, label] of PATTERNS) {
        if (re.test(line)) hits.push(`  ${rel}:${i + 1} (${label})`);
      }
    });
  }
};
scan(ROOT);

if (hits.length) {
  console.error(`\n▲ 規約に反する記載が ${hits.length} 件あります (個人名 / 個人 path / credential):`);
  console.error(hits.join('\n'));
  console.error('該当箇所を書き換えてから配布してください。');
}
