#!/usr/bin/env bash
# review-member skill の run 記録と reviewer 指摘との突き合わせを 1 file に記録する
# log: ~/.claude/logs/review-member-runs.jsonl (1 行 = 1 event)
#
# Usage:
#   ./scripts/review-member-log.sh append < run.json         # run を 1 行追記 (stdin に JSON)
#   ./scripts/review-member-log.sh reconcile <target> --caught N --missed-lens N --no-lens N [--note "..."]
#   ./scripts/review-member-log.sh list [--since YYYY-MM-DD] # run と reconcile を時系列で表示
#   ./scripts/review-member-log.sh pending                   # 事前 run のうち reconcile が無いもの
#
# append の JSON (必須 key): target / kind (事前|事後|backtest) / files / findings / verdict
#   findings は [{"lens": <番号>, "file": "path", "line": <n>, "confidence": "normal|low"}] の配列
#   definition (ai-tools の commit) と ts は script が補う
set -euo pipefail

LOG="${REVIEW_MEMBER_LOG:-$HOME/.claude/logs/review-member-runs.jsonl}"
AI_TOOLS="${AI_TOOLS_DIR:-$HOME/ai-tools}"

usage() { sed -n '2,13p' "$0"; exit 1; }
need_jq() { command -v jq >/dev/null || { echo "jq が必要" >&2; exit 1; }; }

definition_rev() {
  git -C "$AI_TOOLS" rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

cmd_append() {
  need_jq
  local input
  input="$(cat)"
  local key
  for key in target kind files findings verdict; do
    jq -e --arg k "$key" 'has($k)' <<<"$input" >/dev/null 2>&1 \
      || { echo "append: key '$key' が無い" >&2; exit 1; }
  done
  jq -e '.kind | IN("事前","事後","backtest")' <<<"$input" >/dev/null 2>&1 \
    || { echo "append: kind は 事前 / 事後 / backtest のいずれか" >&2; exit 1; }
  mkdir -p "$(dirname "$LOG")"
  jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg rev "$(definition_rev)" \
    '. + {event: "run", ts: $ts, definition: $rev,
          needs_fix: ([.findings[] | select(.confidence != "low")] | length),
          low: ([.findings[] | select(.confidence == "low")] | length)}' <<<"$input" >>"$LOG"
  echo "appended: $LOG"
}

cmd_reconcile() {
  need_jq
  local target="${1:-}"; shift || usage
  [[ -n "$target" ]] || usage
  local caught="" missed="" nolens="" note=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --caught) caught="$2"; shift 2 ;;
      --missed-lens) missed="$2"; shift 2 ;;
      --no-lens) nolens="$2"; shift 2 ;;
      --note) note="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  local v
  for v in "$caught" "$missed" "$nolens"; do
    [[ "$v" =~ ^[0-9]+$ ]] || { echo "reconcile: --caught / --missed-lens / --no-lens は整数で 3 つとも必須" >&2; exit 1; }
  done
  mkdir -p "$(dirname "$LOG")"
  jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg t "$target" --arg note "$note" \
    --argjson c "$caught" --argjson m "$missed" --argjson n "$nolens" \
    '{event: "reconcile", ts: $ts, target: $t, caught: $c, missed_lens: $m, no_lens: $n, note: $note}' >>"$LOG"
  echo "appended: $LOG"
}

cmd_list() {
  need_jq
  local since="0000-00-00"
  [[ "${1:-}" == "--since" ]] && since="$2"
  [[ -f "$LOG" ]] || { echo "log なし: $LOG"; return 0; }
  printf '%-10s %-9s %-10s %-8s %s\n' "date" "event" "target" "kind" "summary"
  jq -r --arg since "$since" 'select(.ts[:10] >= $since) |
    if .event == "run" then
      [.ts[:10], "run", .target, .kind, "needs-fix \(.needs_fix) / low \(.low) / files \(.files) / def \(.definition)"]
    else
      [.ts[:10], "reconcile", .target, "-", "caught \(.caught) / missed-lens \(.missed_lens) / no-lens \(.no_lens) \(.note)"]
    end | @tsv' "$LOG" | awk -F'\t' '{printf "%-10s %-9s %-10s %-8s %s\n", $1, $2, $3, $4, $5}'
}

cmd_pending() {
  need_jq
  [[ -f "$LOG" ]] || { echo "log なし: $LOG"; return 0; }
  jq -rs '
    (map(select(.event == "reconcile")) | map(.target)) as $done
    | map(select(.event == "run" and .kind == "事前" and (.target as $t | $done | index($t) | not)))
    | .[] | "\(.ts[:10]) \(.target) needs-fix \(.needs_fix) / low \(.low)"' "$LOG"
}

case "${1:-}" in
  append) cmd_append ;;
  reconcile) shift; cmd_reconcile "$@" ;;
  list) shift; cmd_list "$@" ;;
  pending) cmd_pending ;;
  *) usage ;;
esac
