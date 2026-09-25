#!/usr/bin/env node
// sync-style.mjs — _index/style.css を、共有 CSS を持つ全 file へ反映する
// Run from local-docs root: node _index/sync-style.mjs [--check]
//
// 共有 CSS は <style id="local-docs-style"> の中だけを正本と差し替える。
// 本文 / script には触らない。--check は差分の有無だけ返す (書き込まない)。

import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const CSS = path.join(import.meta.dirname, 'style.css');
const OPEN = '<style id="local-docs-style">';
const CLOSE = '</style>';
const SKIP_DIRS = new Set(['node_modules', '.git', '_index']);

if (!fs.existsSync(CSS)) {
  console.error(`正本が無い: ${path.relative(ROOT, CSS)}`);
  process.exit(1);
}
const css = fs.readFileSync(CSS, 'utf8').replace(/\n+$/, '');
const checkOnly = process.argv.includes('--check');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) {
      if (!SKIP_DIRS.has(e.name)) walk(path.join(dir, e.name), out);
    } else if (e.isFile() && e.name.endsWith('.html')) {
      out.push(path.join(dir, e.name));
    }
  }
  return out;
}

let changed = 0, same = 0, skipped = 0;
for (const file of walk(ROOT)) {
  const src = fs.readFileSync(file, 'utf8');
  const start = src.indexOf(OPEN);
  if (start < 0) { skipped++; continue; }
  const end = src.indexOf(CLOSE, start);
  if (end < 0) { skipped++; continue; }

  const next = src.slice(0, start + OPEN.length) + '\n' + css + '\n' + src.slice(end);
  const rel = path.relative(ROOT, file);
  if (next === src) { same++; continue; }
  changed++;
  console.log(`${checkOnly ? 'diff' : 'update'}: ${rel}`);
  if (!checkOnly) fs.writeFileSync(file, next);
}

console.log(`${checkOnly ? '差分' : '反映'} ${changed} / 一致 ${same} / 対象外 ${skipped}`);
if (checkOnly && changed > 0) process.exit(1);
