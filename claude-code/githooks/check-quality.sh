#!/bin/bash
# 共通品質チェック: skill / agent / command / メタファイルの劣化を検出
# pre-commit と pre-push から呼ばれる。単独実行も可。
#
# セットアップ: git config core.hooksPath claude-code/githooks
# 一時迂回: git commit --no-verify  /  git push --no-verify （恒常使用は避ける）

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

failed=0

# check_size <file> <目安> [<上限>]
# 目安 を超えたら warn、上限 を超えたら fail。上限 を省略すると 目安 がそのまま上限になる。
# 目安 を上限として扱うと、意味を削って行数に合わせる圧縮が起きる
# (CLAUDE.repo.md 「Definition File Token Saving」。2026-09-17 実測: 150 超の command が 0 本で、ちょうど 150 が 4 本だった)
check_size() {
  local file="$1"
  local target="$2"
  local limit="${3:-$2}"
  [ -f "$file" ] || return 0
  local lines
  lines=$(wc -l < "$file" | tr -d ' ')
  if [ "$lines" -gt "$limit" ]; then
    echo "✗ $file: $lines lines (上限 $limit)"
    return 1
  fi
  if [ "$lines" -gt "$target" ]; then
    echo "▲ $file: $lines lines (目安 $target)。重複説明と詳細 usage が残存していないか 1 度確認する"
  fi
  return 0
}

# 1. skill-lint --strict (description 形式・トリガー語句・ディレクトリ名一致)
if [ -x "./claude-code/scripts/skill-lint.sh" ]; then
  if ! ./claude-code/scripts/skill-lint.sh --strict 2>&1; then
    echo "✗ skill-lint failed"
    failed=1
  fi
fi

# 2. メタファイル肥大検出 (リファクタ後の現状値+α を上限)
# CLAUDE.global.md の cap は 2026-09-21 に 200 から 220 へ上げた。自然文 trigger の表を
# 本文に置く設計にしたため、今後も行が増える (198 行で残り 2 行だった)
check_size "claude-code/CLAUDE.global.md" 220         || failed=1
check_size "claude-code/README.md" 300         || failed=1

# 3. skill body 行数 (目安 130 / 上限 150。canonical: CLAUDE.repo.md)
for f in claude-code/skills/*/SKILL.md; do
  check_size "$f" 130 150 || failed=1
done

# 4. agent 行数 (目安 300 / 上限 360)
for f in claude-code/agents/*.md; do
  check_size "$f" 300 360 || failed=1
done

# 5. command 行数 (目安 150 / 上限 180)
for f in claude-code/commands/*.md; do
  check_size "$f" 150 180 || failed=1
done

# 6. review-history.jsonl 同位置3回以上 (Compounding Engineering: hook化推奨閾値)
# warn のみ (failed には影響しない)。既存問題への気付き材料、新規commit強制ブロックしない
# line は 5刻みで丸めて範囲一致 (analytics の ±3 と同程度の感度。line 128 と 131 を同グループ集約)
# 同一 base commit 内の review/followup/re-review は1回扱い。異なる commit で再発した位置のみ構造的問題と判定
HIST=".claude/review-history.jsonl"
if [ -f "$HIST" ] && command -v jq >/dev/null 2>&1; then
  recurring=$(jq -c '.' "$HIST" 2>/dev/null \
    | jq -s 'group_by(.file + ":" + (((.line // 0) / 5) | floor | tostring) + ":" + .focus)
            | map(unique_by((.commit // "unknown") | split("-")[0]))
            | map(select(length >= 3)) | length' 2>/dev/null \
    || echo "0")
  if [ "${recurring:-0}" != "0" ] && [ "${recurring:-0}" != "" ]; then
    echo "⚠ review-history.jsonl: 異なるコミットで同位置3回以上の指摘 ${recurring} 件 → hook化推奨"
    jq -c '.' "$HIST" 2>/dev/null \
      | jq -s -r 'group_by(.file + ":" + (((.line // 0) / 5) | floor | tostring) + ":" + .focus)
                | map(unique_by((.commit // "unknown") | split("-")[0]))
                | map(select(length >= 3)) | sort_by(-length)
                | .[] | "  " + .[0].file + ":~" + (.[0].line // 0 | tostring) + " [" + .[0].focus + "] (" + (length | tostring) + " commits)"' 2>/dev/null
  fi
fi

# 7. writing 規範 doc を触ったら contract bats を逆引きで実行する
# 意味を保つ書き換えで assert の文字列だけが古くなり、fail を 3 commit 連続で見落とした
# (5fd8228e / edcf5e18 / 9ca67f9d。2026-09-21 に 4 件まとめて修正した)。実行は 4 秒
changed=$(git diff --cached --name-only 2>/dev/null || true)
[ -n "$changed" ] || changed=$(git diff --name-only origin/main...HEAD 2>/dev/null || true)
if printf '%s\n' "$changed" | grep -qE '^claude-code/(skills/|guidelines/writing/)' \
   && command -v npx >/dev/null 2>&1; then
  out=$(cd claude-code && npx bats tests/unit/writing-policy-contract-*.bats 2>&1) || true
  if printf '%s\n' "$out" | grep -q '^not ok'; then
    echo "✗ writing-policy-contract が fail した (規範 doc の文言と assert がずれている)"
    printf '%s\n' "$out" | grep -A2 '^not ok' | sed 's/^/  /'
    failed=1
  fi
fi

if [ "$failed" -ne 0 ]; then
  echo ""
  echo "Quality check failed."
  echo "  - 行数を削減するか --no-verify で意図的に迂回"
  exit 1
fi

echo "✓ Quality checks passed"
