#!/usr/bin/env bash
# warn-log-weekly.sh — hook / review skill が出力する warn log を pattern 別に週次集計する。
# 詳細: <repo-root>/claude-code/scripts/README-warn-log-weekly.md (canonical)

set -euo pipefail

LOG_DIR="${HOME}/.claude/logs"
OUT_DIR="${HOME}/.claude/logs"
TODAY="$(date +%Y%m%d)"
LAST_WEEK_START="$(date -v-14d +%Y-%m-%d)"
THIS_WEEK_START="$(date -v-7d +%Y-%m-%d)"
OUT_FILE="${OUT_DIR}/warn-log-weekly-${TODAY}.txt"

TARGET_LOGS=(
  "review-pattern-warn.log"
  "bundle-violation-warn.log"
  "sequential-fire-warn.log"
)

# log ごとに書き出し format が違うため、basename から種別判定して抽出方法を分岐する。
# 詳細は README-warn-log-weekly.md の集計対象 log 表を参照する
log_format() {
  case "$1" in
    bundle-violation-warn.log | sequential-fire-warn.log) echo "pipe_nobracket" ;;
    *) echo "bracket_pipe" ;;
  esac
}

_TS_PAT_EXTRACT='
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  function extract(   f) {
    if (fmt == "bracket_pipe") {
      split($0, f, "|")
      ts = substr($0, 2, 10)
      pat = trim(f[2])
    } else if (fmt == "pipe_nobracket") {
      split($0, f, "|")
      ts = substr(trim(f[1]), 1, 10)
      pat = trim(f[3])
      sub(/=.*/, "", pat)
    } else {
      ts = ""
      pat = "(unknown-format)"
    }
  }
'

count_by_pattern() {
  local log_path="$1" since="$2" until="$3" fmt="$4"
  [[ -f "$log_path" ]] || { echo "  (log not found)"; return; }
  awk -v since="$since" -v until="$until" -v fmt="$fmt" "
    $_TS_PAT_EXTRACT
    {
      extract()
      if (ts >= since && ts < until) {
        p = (pat == \"\") ? \"(no-pattern)\" : pat
        count[p]++
        total++
      }
    }
    END {
      if (total == 0) { print \"  (no entries)\"; exit }
      n = 0
      for (p in count) { arr[n++] = p }
      for (i = 0; i < n; i++) {
        for (j = i+1; j < n; j++) {
          if (count[arr[j]] > count[arr[i]]) { t = arr[i]; arr[i] = arr[j]; arr[j] = t }
        }
      }
      for (i = 0; i < n; i++) { printf \"  %-30s %d\n\", arr[i], count[arr[i]] }
      printf \"  %-30s %d\n\", \"(total)\", total
    }
  " "$log_path"
}

total_delta() {
  local log_path="$1" fmt="$2"
  [[ -f "$log_path" ]] || { echo "0 0"; return; }
  local last this
  last=$(awk -v s="$LAST_WEEK_START" -v u="$THIS_WEEK_START" -v fmt="$fmt" "
    $_TS_PAT_EXTRACT
    { extract(); if (ts >= s && ts < u) c++ } END { print c+0 }
  " "$log_path")
  this=$(awk -v s="$THIS_WEEK_START" -v fmt="$fmt" "
    $_TS_PAT_EXTRACT
    { extract(); if (ts >= s) c++ } END { print c+0 }
  " "$log_path")
  echo "$last $this"
}

{
  echo "=== warn-log weekly summary: $(date '+%Y-%m-%d %H:%M') ==="
  echo "period: this=${THIS_WEEK_START}〜today, last=${LAST_WEEK_START}〜${THIS_WEEK_START}"
  echo ""

  for log in "${TARGET_LOGS[@]}"; do
    log_path="${LOG_DIR}/${log}"
    fmt="$(log_format "$log")"
    read -r last this < <(total_delta "$log_path" "$fmt")
    delta=$((this - last))
    delta_sign=""
    [[ $delta -gt 0 ]] && delta_sign="+"
    echo "## ${log}  (this=${this} / last=${last} / Δ=${delta_sign}${delta})"
    echo "  [this week pattern breakdown]"
    count_by_pattern "$log_path" "$THIS_WEEK_START" "9999-99-99" "$fmt"
    echo ""
  done

  # hook-errors.log は各 hook の `exec 2>>` 先で、行に timestamp が無い raw stderr。
  # 週次の 集計対象の日付範囲に含められないので、現在 file の内容を message 別に数える snapshot として出す
  hook_errors_log="${LOG_DIR}/hook-errors.log"
  echo "## hook-errors.log  (snapshot: 日付が付与されないため累計。size rotation で切られるまでの分)"
  if [[ -f "$hook_errors_log" ]]; then
    echo "  total lines: $(wc -l < "$hook_errors_log" | tr -d ' ')"
    echo "  [message breakdown (top 10)]"
    sed 's|^/[^ ]*/||' "$hook_errors_log" \
      | sort | uniq -c | sort -rn | head -10 \
      | awk '{ c = $1; $1 = ""; sub(/^ /, ""); printf "  %-6s %s\n", c, $0 }'
  else
    echo "  (log not found)"
  fi
  echo ""

  echo "=== Interpretation hints ==="
  echo "- Δ が急増した pattern: hook / rule が新たに hit している。誤爆か有効かを 1 件抽出して目視確認する"
  echo "- Δ が 0 のまま 4 週続いた log: 死に log の可能性がある。原因を切り分けて剪定判断する"
  echo "- 特定 pattern が total の 80% 超: 単独 rule 化 / block 昇格の候補になる"
  echo "- hook-errors.log に同一 message が蓄積している: hook 側の実バグ。行数でなく message で潰す"
} > "$OUT_FILE"

cat "$OUT_FILE"
