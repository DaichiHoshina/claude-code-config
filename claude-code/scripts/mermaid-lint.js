#!/usr/bin/env node
'use strict';

// Mermaid の構文ミスを依存なしで検査する。markdown の ```mermaid fence /
// <pre class="mermaid"> block / .mmd file を対象に、頻出の誤りだけを報告する。
// 使い方: node scripts/mermaid-lint.js <file...>  (--stdin で標準入力を 1 図として検査)

const fs = require('fs');

const DIAGRAM_TYPES = [
  'flowchart', 'graph', 'sequenceDiagram', 'classDiagram', 'stateDiagram-v2',
  'stateDiagram', 'erDiagram', 'journey', 'gantt', 'pie', 'gitGraph', 'mindmap',
  'timeline', 'quadrantChart', 'requirementDiagram', 'sankey-beta', 'xychart-beta',
  'block-beta', 'packet-beta', 'architecture-beta', 'kanban', 'radar-beta',
  'treemap-beta', 'C4Context', 'C4Container', 'C4Component', 'C4Dynamic', 'C4Deployment',
];

const BLOCK_OPENERS = ['subgraph', 'alt', 'opt', 'loop', 'par', 'critical', 'break', 'rect', 'box'];

const ER_CARDINALITY = /^(\|o|\|\||\}o|\}\||o\||o\{)(--|\.\.)(o\||\|\||o\{|\|\{|\|o|\}o|\}\|)$/;

// 図形の記法。label の中身を得るために長い記法から順に当てる
const SHAPES = [
  { open: '[(', close: ')]' },
  { open: '[[', close: ']]' },
  { open: '[/', close: '/]' },
  { open: '[/', close: '\\]' },
  { open: '[\\', close: '\\]' },
  { open: '[\\', close: '/]' },
  { open: '(((', close: ')))' },
  { open: '((', close: '))' },
  { open: '([', close: '])' },
  { open: '{{', close: '}}' },
  { open: '>', close: ']' },
  { open: '[', close: ']' },
  { open: '(', close: ')' },
  { open: '{', close: '}' },
];

function stripQuoted(text) {
  return text.replace(/"[^"]*"/g, (m) => ' '.repeat(m.length));
}

// label の中で使う <br> 等の HTML tag。`>` を旗形 node の開始と誤認しないよう空白へ置き換える
function stripHtmlTags(text) {
  return text.replace(/<[^<>]*>/g, (m) => ' '.repeat(m.length));
}

// 行の中の node label を返す。戻り値は {body, index} の配列
function extractLabels(line) {
  const labels = [];
  let i = 0;
  while (i < line.length) {
    const shape = SHAPES.find((s) => line.startsWith(s.open, i));
    // `>` 開始の旗形は node id の直後にしか来ない。矢印 `-->` の `>` を label と誤認しない
    if (!shape || (shape.open === '>' && !/[\w぀-ヿ一-鿿)\]}]/.test(line[i - 1] || ''))) {
      i += 1;
      continue;
    }
    const close = line.indexOf(shape.close, i + shape.open.length);
    if (close === -1) {
      i += 1;
      continue;
    }
    labels.push({ body: line.slice(i + shape.open.length, close), index: i });
    i = close + shape.close.length;
  }
  return labels;
}

function extractPipeLabels(line) {
  const labels = [];
  const re = /\|([^|]*)\|/g;
  let m;
  while ((m = re.exec(line)) !== null) {
    labels.push({ body: m[1], index: m.index });
  }
  return labels;
}

// lines: [{ text, lineNo }]
function lintDiagram(lines, file, findings) {
  const add = (lineNo, rule, message) => findings.push({ file, lineNo, rule, message });

  const first = lines.find(({ text }) => {
    const t = text.trim();
    return t !== '' && !t.startsWith('%%') && t !== '---';
  });
  if (!first) return;
  const head = first.text.trim().split(/[\s;{]/)[0];
  const type = DIAGRAM_TYPES.find((t) => head === t) || null;
  if (!type) {
    add(first.lineNo, 'diagram-type', `図種の宣言が読み取れない (先頭語: ${head})。flowchart / sequenceDiagram 等を 1 行目に書く`);
  }
  const isFlowchart = type === 'flowchart' || type === 'graph';
  const isSequence = type === 'sequenceDiagram';
  const isEr = type === 'erDiagram';
  const isState = type === 'stateDiagram' || type === 'stateDiagram-v2';

  let openBlocks = 0;
  let endCount = 0;
  let firstUnbalancedLine = first.lineNo;

  for (const { text, lineNo } of lines) {
    const trimmed = text.trim();
    if (trimmed === '' || trimmed.startsWith('%%')) continue;
    const bare = stripQuoted(text);

    if (/　/.test(bare)) {
      add(lineNo, 'ideographic-space', '全角空白が引用符の外にある。半角空白に直すか label を "..." で囲む');
    }

    const commentAt = bare.indexOf('%%');
    if (commentAt > 0 && bare.slice(0, commentAt).trim() !== '') {
      add(lineNo, 'inline-comment', '%% の注記は行頭にしか書けない。行を分ける');
    }

    // `note right of X: 本文` と `note for X "本文"` は 1 行で閉じる。本文を持たない note だけが end note まで続く
    const isMultilineNote = /^note\b/i.test(trimmed) && !trimmed.includes(':') && !trimmed.includes('"');
    if (isMultilineNote || BLOCK_OPENERS.some((k) => new RegExp(`^${k}\\b`).test(trimmed))) {
      openBlocks += 1;
      if (openBlocks === 1) firstUnbalancedLine = lineNo;
    }
    if (/^end\b/.test(trimmed)) endCount += 1;

    if (/^subgraph\s+[^\s[({]*(\[[([\\/]|\(|\{)/.test(stripQuoted(trimmed))) {
      add(lineNo, 'subgraph-shape', 'subgraph の title に使えるのは [...] だけで、[(...)] や (...) は構文エラーになる');
    }

    if (isFlowchart) {
      if (/->>/.test(bare)) {
        add(lineNo, 'arrow-kind', 'flowchart に ->> は無い。--> / -.-> / ==> を使う');
      }
      if (/(^|[^-.=<>])->(?!>)/.test(bare)) {
        add(lineNo, 'arrow-kind', 'flowchart の矢印は 2 文字以上必要。-> でなく --> を使う');
      }
    }

    if (isSequence && /(^|[^-.=<])==>/.test(bare)) {
      add(lineNo, 'arrow-kind', 'sequenceDiagram に ==> は無い。->> / -->> / -x / -) を使う');
    }

    if (isEr) {
      const m = trimmed.match(/^(\S+)\s+(\S+)\s+(\S+)\s*:/);
      if (m && /^[|o}.\-{]+$/.test(m[2]) && !ER_CARDINALITY.test(m[2])) {
        add(lineNo, 'er-cardinality', `関係の記号 ${m[2]} が既定の組み合わせに無い。||--o{ のように左右の端と線種をそろえる`);
      }
    }

    if (isFlowchart || isState) {
      const forLabels = stripHtmlTags(bare);
      for (const { body } of [...extractLabels(forLabels), ...extractPipeLabels(forLabels)]) {
        if (/[()[\]]/.test(body)) {
          add(lineNo, 'label-quote', `label 内の括弧は引用符が要る。"${body.trim()}" のように囲む`);
        }
      }
      if (/(^|[\s;>])end([\s;[(]|$)/.test(bare) && !/^end\b/.test(trimmed)) {
        add(lineNo, 'reserved-id', 'node の id に小文字の end は使えない。End や node_end に変える');
      }
    }
  }

  if (openBlocks !== endCount) {
    add(firstUnbalancedLine, 'block-balance', `block の開きが ${openBlocks} 件、end が ${endCount} 件で対応しない`);
  }
}

// markdown / HTML の中の mermaid block を返す
function extractDiagrams(source, file) {
  const isRaw = /\.(mmd|mermaid)$/.test(file);
  const lines = source.split('\n');
  if (isRaw) {
    return [lines.map((text, i) => ({ text, lineNo: i + 1 }))];
  }
  const diagrams = [];
  let current = null;
  let closer = null;
  lines.forEach((text, i) => {
    const lineNo = i + 1;
    if (current === null) {
      if (/^\s*(```+|~~~+)\s*mermaid\s*$/.test(text)) {
        current = [];
        closer = /^\s*(```+|~~~+)\s*$/;
      } else if (/<pre[^>]*class="[^"]*\bmermaid\b[^"]*"[^>]*>/.test(text)) {
        current = [];
        closer = /<\/pre>/;
      }
      return;
    }
    if (closer.test(text)) {
      diagrams.push(current);
      current = null;
      return;
    }
    current.push({ text, lineNo });
  });
  if (current !== null) diagrams.push(current);
  return diagrams;
}

function lintSource(source, file) {
  const findings = [];
  for (const diagram of extractDiagrams(source, file)) {
    if (diagram.length === 0) continue;
    lintDiagram(diagram, file, findings);
  }
  return findings;
}

function main(argv) {
  const files = argv.filter((a) => a !== '--stdin');
  const useStdin = argv.includes('--stdin');
  if (!useStdin && files.length === 0) {
    process.stderr.write('usage: node scripts/mermaid-lint.js <file...> | --stdin\n');
    return 2;
  }
  const findings = [];
  if (useStdin) {
    findings.push(...lintSource(fs.readFileSync(0, 'utf8'), 'stdin.mmd'));
  }
  for (const file of files) {
    findings.push(...lintSource(fs.readFileSync(file, 'utf8'), file));
  }
  for (const f of findings) {
    process.stdout.write(`${f.file}:${f.lineNo}: [${f.rule}] ${f.message}\n`);
  }
  if (findings.length > 0) {
    process.stdout.write(`\n${findings.length} 件の記法ミスを検出した\n`);
    return 1;
  }
  return 0;
}

if (require.main === module) {
  process.exit(main(process.argv.slice(2)));
}

module.exports = { lintSource, extractDiagrams };
