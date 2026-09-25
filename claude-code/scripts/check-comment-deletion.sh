#!/usr/bin/env bash
# check-comment-deletion.sh — PR 前 gate: diff で削除された comment / godoc 行を検出する
#
# レビュー往復の最頻出 pattern (既存 comment / godoc の意図しない削除への指摘) を
# PR 作成前に機械検出する。導入根拠: docs/reports/dev-workflow-base-first-improvement-20260810.md
#
# Usage: check-comment-deletion.sh [<base-ref>] [<head-ref>]
#   base-ref 省略時は origin/main → main の順で存在する方を使う
#   head-ref 省略時は HEAD
# Env:
#   SKIP_COMMENT_CHECK=1  検査を skip する (意図的な comment 削除時の bypass)
# Exit code:
#   0 = 検出なし / 1 = 削除 comment あり / 2 = 実行環境 error
set -euo pipefail

if [ "${SKIP_COMMENT_CHECK:-0}" = "1" ]; then
  echo "SKIP_COMMENT_CHECK=1 のため comment 削除検査を skip した"
  exit 0
fi

base="${1:-}"
head="${2:-HEAD}"

if [ -z "$base" ]; then
  if git rev-parse --verify -q origin/main > /dev/null; then
    base="origin/main"
  elif git rev-parse --verify -q main > /dev/null; then
    base="main"
  else
    echo "base branch (origin/main / main) が見つからない。第 1 引数で base-ref を指定する" >&2
    exit 2
  fi
fi

# three-dot (merge-base 起点) + unified=0 で hunk header から変更前の file の行番号を追跡する
diff_output=$(git diff --unified=0 "${base}...${head}" -- '*.go')
if [ -z "$diff_output" ]; then
  exit 0
fi

# 削除行のうち comment 形式 (// と /* */ block の枠) のみ対象。
# 同一内容 (前後空白を除く) が追加行にも現れる場合は「移動」とみなし検出の対象外にする
findings=$(awk '
  /^--- / { old_file = substr($2, 3); next }
  /^\+\+\+ / { next }
  /^@@ / {
    split($2, a, ",")
    old_line = substr(a[1], 2) + 0
    next
  }
  /^-/ {
    line = substr($0, 2)
    if (line ~ /^[[:space:]]*(\/\/|\/\*|\*\/|\*([[:space:]]|$))/) {
      text = line
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", text)
      n_del++
      del_pos[n_del] = old_file ":" old_line
      del_line[n_del] = line
      del_text[n_del] = text
    }
    old_line++
    next
  }
  /^\+/ {
    line = substr($0, 2)
    if (line ~ /^[[:space:]]*(\/\/|\/\*|\*\/|\*([[:space:]]|$))/) {
      text = line
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", text)
      added[text] = 1
    }
    next
  }
  END {
    for (i = 1; i <= n_del; i++) {
      if (!(del_text[i] in added)) print del_pos[i] ": " del_line[i]
    }
  }
' <<< "$diff_output")

if [ -z "$findings" ]; then
  exit 0
fi

echo "diff で既存 comment / godoc の削除を検出した (${base}...${head}):"
echo "$findings"
cat << 'MSG'

対応:
  - レビュー指摘往復の頻出 pattern のため、削除が意図的か PR 前に確認する
  - 意図的な削除 (冗長 comment の整理等) なら SKIP_COMMENT_CHECK=1 を付けて再実行して通す
MSG
exit 1
