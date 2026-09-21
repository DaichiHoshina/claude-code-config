#!/usr/bin/env node
'use strict';

// Mermaid flowchart の描画幅を依存なしで見積もる。markdown の ```mermaid fence を対象に、
// 1 図ごとに幅 (px) と段の構成を出力する。viewer の幅を超える図を、描画せずに見つけるために使う。
// 使い方:
//   node scripts/mermaid-width.js --estimate <file...> [--width 800]   超過があれば exit 1
//   node scripts/mermaid-width.js --stdin [--width 800]                標準入力を 1 図として扱う
//
// 見積もり式は 2026-09-17 に Mermaid 11 を Chrome で描画して SVG の viewBox 幅を測った値から決めた。
// LR 7 点は誤差 1% 以内、TB 8 点は最大 5% (tests/fixtures/mermaid-width/measured-2026-09-17.md)。
// Mermaid の版が変わって bats が fail したら、この定数を測り直す。
// `~~~` (不可視 link) を含む図は dagre が階段状に配置するため、この式の対象外にする。

const fs = require('fs');

// Mermaid 11 flowchart の既定値に対応する。text は wrappingWidth 200 で折り返され、
// それ以上は高さへ回るので幅の上限は 200 + padding になる
const CJK_PX = 16; // 全角 1 文字 (font-size 16px)
const ASCII_PX = 8; // 半角 1 文字
const TEXT_MAX_PX = 200; // wrappingWidth
const NODE_PADDING_PX = 60; // rect 幅 − text 幅 (実測 100 − 41、236 − 176)
const NODE_GAP_PX = 50; // nodeSpacing / rankSpacing
const DIAGRAM_MARGIN_PX = 16; // diagramPadding 8 × 2

function textWidthPx(label) {
  let w = 0;
  for (const ch of label) w += ch.codePointAt(0) > 0xff ? CJK_PX : ASCII_PX;
  return Math.min(w, TEXT_MAX_PX);
}

function nodeWidthPx(label) {
  return textWidthPx(label) + NODE_PADDING_PX;
}

// ```mermaid fence を抜き出す。line は fence 開始行 (1 始まり)
function extractMermaidBlocks(markdown) {
  const lines = markdown.split('\n');
  const blocks = [];
  let start = -1;
  let buf = [];
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].trim();
    if (start < 0) {
      if (/^```\s*mermaid\b/.test(t)) { start = i; buf = []; }
      continue;
    }
    if (/^```/.test(t)) {
      blocks.push({ line: start + 1, source: buf.join('\n') });
      start = -1;
      continue;
    }
    buf.push(lines[i]);
  }
  return blocks;
}

// 図形の記法。label を取るために長い記法から順に当てる
const SHAPES = [
  ['[[', ']]'], ['[(', ')]'], ['[/', '/]'], ['[\\', '\\]'], ['[/', '\\]'], ['[\\', '/]'],
  ['(((', ')))'], ['((', '))'], ['([', '])'], ['{{', '}}'], ['>', ']'],
  ['[', ']'], ['(', ')'], ['{', '}'],
];

function stripQuotes(s) {
  const t = s.trim();
  if (t.length >= 2 && ((t[0] === '"' && t[t.length - 1] === '"') || (t[0] === "'" && t[t.length - 1] === "'"))) {
    return t.slice(1, -1);
  }
  return t;
}

// `id["label"]` / `id[label]` / `id` を {id, label} にする。label が無い bare id は id を label にする
function parseNodeToken(token) {
  const t = token.trim();
  if (!t) return null;
  for (const [open, close] of SHAPES) {
    const oi = t.indexOf(open);
    if (oi > 0 && t.endsWith(close)) {
      const id = t.slice(0, oi).trim();
      const label = stripQuotes(t.slice(oi + open.length, t.length - close.length));
      if (id) return { id, label };
    }
  }
  return { id: t, label: t };
}

// `A --> B`, `A -->|text| B`, `A -- text --> B`, `A & B --> C`, `A ~~~ B`、chain `A --> B --> C` を扱う
const EDGE_RE = /\s*(?:<?-{2,3}>?|<?={2,3}>?|<?-\.{1,3}->?|~{3})(?:\|[^|]*\|)?\s*/;
const EDGE_TEXT_RE = /\s(?:--|==|-\.)\s[^-=.]*?\s(?:-->|==>|\.->)\s/g;

function parseFlowchart(source) {
  const nodes = new Map();
  const edges = [];
  let dir = 'TB';
  // 先に bare id で登場し、後で label 付きで定義される node は label 付きの方を採用する
  const addNode = (n) => {
    if (!n) return;
    if (!nodes.has(n.id) || n.label !== n.id) nodes.set(n.id, n.label);
  };

  for (const raw of source.split('\n')) {
    let line = raw.replace(/%%.*$/, '').trim();
    if (!line) continue;
    const head = line.match(/^(?:flowchart|graph)\s+(TB|TD|BT|LR|RL)?/);
    if (head) { dir = (head[1] || 'TB').replace('TD', 'TB'); continue; }
    if (/^(subgraph|end|classDef|class|style|linkStyle|click|direction)\b/.test(line)) continue;
    line = line.replace(EDGE_TEXT_RE, ' --> ');
    const parts = line.split(EDGE_RE).map((p) => p.trim()).filter(Boolean);
    if (parts.length === 1) { addNode(parseNodeToken(parts[0])); continue; }
    let prev = parts[0].split('&').map(parseNodeToken).filter(Boolean);
    prev.forEach(addNode);
    for (let i = 1; i < parts.length; i++) {
      const cur = parts[i].split('&').map(parseNodeToken).filter(Boolean);
      cur.forEach(addNode);
      for (const a of prev) for (const b of cur) edges.push([a.id, b.id]);
      prev = cur;
    }
  }
  return { dir, nodes, edges };
}

// 最長経路で段を決める。dagre の rank 割り当てと、このような木に近い DAG では一致する
function layerNodes(nodes, edges) {
  const rank = new Map([...nodes.keys()].map((id) => [id, 0]));
  const indeg = new Map([...nodes.keys()].map((id) => [id, 0]));
  const out = new Map([...nodes.keys()].map((id) => [id, []]));
  for (const [a, b] of edges) {
    if (!out.has(a) || !indeg.has(b)) continue;
    out.get(a).push(b);
    indeg.set(b, indeg.get(b) + 1);
  }
  // 処理フローの図は閉路を含むことがある (選び直しで前の段へ戻る辺など)。
  // Kahn の位相ソートは閉路があると queue が空のまま終わり、全 node が段 0 に残って
  // 幅を 3 倍前後に見積もる (2026-09-20 実測: 6 node の図で 394px が 1218px)。
  // queue が空になっても未処理の node があれば、入次数が最小のものを段の先頭として再開する
  const done = new Set();
  const queue = [...indeg].filter(([, d]) => d === 0).map(([id]) => id);
  queue.forEach((id) => done.add(id));
  for (;;) {
    while (queue.length) {
      const a = queue.shift();
      for (const b of out.get(a)) {
        rank.set(b, Math.max(rank.get(b), rank.get(a) + 1));
        indeg.set(b, indeg.get(b) - 1);
        if (indeg.get(b) === 0 && !done.has(b)) { done.add(b); queue.push(b); }
      }
    }
    const rest = [...indeg].filter(([id]) => !done.has(id));
    if (!rest.length) break;
    const [seed] = rest.reduce((min, cur) => (cur[1] < min[1] ? cur : min));
    done.add(seed);
    queue.push(seed);
  }
  const ranks = [];
  for (const [id, r] of rank) {
    (ranks[r] = ranks[r] || []).push(id);
  }
  return ranks.filter(Boolean);
}

// TB は最も広い段の Σ node 幅、LR は各段の max node 幅の Σ。どちらも間隔と余白を足す
function estimateWidth(chart) {
  const ranks = layerNodes(chart.nodes, chart.edges);
  const widths = ranks.map((ids) => ids.map((id) => nodeWidthPx(chart.nodes.get(id))));
  const horizontal = chart.dir === 'LR' || chart.dir === 'RL';
  let width;
  let widest = 0;
  if (horizontal) {
    width = widths.reduce((s, ws) => s + Math.max(...ws), 0) + NODE_GAP_PX * (widths.length - 1) + DIAGRAM_MARGIN_PX;
    widest = Math.max(...widths.map((ws) => ws.length));
  } else {
    const rankWidths = widths.map((ws) => ws.reduce((s, w) => s + w, 0) + NODE_GAP_PX * (ws.length - 1));
    width = Math.max(...rankWidths) + DIAGRAM_MARGIN_PX;
    widest = widths[rankWidths.indexOf(Math.max(...rankWidths))].length;
  }
  return { width: Math.round(width), dir: chart.dir, rankCount: ranks.length, widestRankNodes: widest, nodeCount: chart.nodes.size };
}

function formatEstimate(label, est, limit) {
  const verdict = limit ? (est.width > limit ? `超過 (+${est.width - limit}px)` : '以内') : '';
  return `${label}  ${est.dir}  ${est.width}px  段 ${est.rankCount}  最大段 ${est.widestRankNodes} node  計 ${est.nodeCount} node  ${verdict}`.trimEnd();
}

function main(argv) {
  const args = argv.slice(2);
  let mode = null;
  let limit = 0;
  const files = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--estimate' || a === '--stdin') mode = a;
    else if (a === '--width') limit = Number(args[++i]) || 0;
    else files.push(a);
  }
  if (!mode) {
    process.stderr.write('usage: mermaid-width.js --estimate <file...> [--width 800] | --stdin [--width 800]\n');
    return 2;
  }
  if (mode === '--stdin') {
    const est = estimateWidth(parseFlowchart(fs.readFileSync(0, 'utf8')));
    process.stdout.write(formatEstimate('stdin', est, limit) + '\n');
    return limit && est.width > limit ? 1 : 0;
  }
  let over = 0;
  for (const f of files) {
    const md = fs.readFileSync(f, 'utf8');
    for (const b of extractMermaidBlocks(md)) {
      if (!/^\s*(flowchart|graph)\b/m.test(b.source)) continue;
      const est = estimateWidth(parseFlowchart(b.source));
      if (limit && est.width > limit) over++;
      process.stdout.write(formatEstimate(`${f}:L${b.line}`, est, limit) + '\n');
    }
  }
  return over ? 1 : 0;
}

if (require.main === module) process.exit(main(process.argv));

module.exports = { textWidthPx, nodeWidthPx, extractMermaidBlocks, parseFlowchart, layerNodes, estimateWidth };
