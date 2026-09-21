#!/usr/bin/env bash
# 週次 maintenance loop 本体 (launchd から呼ばれる)
#
# claude CLI headless (-p) で maintenance command を順に実行し、
# 結果を ~/.claude/logs/maintenance-cron-<ts>.log に追記する。
# general-clean は候補表の提示まで (削除は翌朝 /sleep-review Step 0 で人手 triage)。
# memory-clean のみ --apply (trash + MEMORY.md prune + 表記揺れ修正まで実行、
# cluster / graduate 等の判断が要る操作は --apply でも提案止まり)。
# claude-update-fix / serena-update-fix は実際に apply + push + sync まで行う
# (push、user 指示 2026-08-07。argument-hint "[--dry-run] [push]" に合わせ、
# 対応する commands/*.md Phase 5 に headless push 手順を明記済み)。他は report-only
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${HOME}/.claude/logs"
WEBHOOK_FILE="${HOME}/.claude/secrets/slack-webhook"
mkdir -p "$LOG_DIR"

CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || true)}"
if [[ -z "$CLAUDE_BIN" ]]; then
  echo "ERROR: claude CLI が見つかりません (PATH または CLAUDE_BIN で指定してください)" >&2
  exit 2
fi

# 1 command ごとに上限を掛ける (全体 budget だと先頭の hang が後続を道連れにする)。
# 実測は 3 command 合計 7 分・単発最大 3 分 (2026-07-27〜08-17 の cron log)。
# /general-clean all は単発 452s (2026-09-05 手動計測) なので default は 900s にし、
# 最長 command に対して約 2 倍の余裕を確保する。値は CMD_MAX_SECONDS で上書きできる
CMD_MAX_SECONDS="${CMD_MAX_SECONDS:-900}"
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
# API に接続できず失敗した command は待って再試行する (2026-09-14 に 4 job 全部が失敗した実踏)。env で上書きできる
NET_RETRY_MAX="${NET_RETRY_MAX:-3}"
NET_RETRY_WAIT="${NET_RETRY_WAIT:-300}"

notify() {
  local text="$1" url=""
  [[ -f "${WEBHOOK_FILE}" ]] || return 0
  url="$(tr -d '\n\r ' < "${WEBHOOK_FILE}")"
  [[ "${url}" =~ ^https://hooks\.slack\.com/ ]] || return 0
  curl -sf --max-time 15 -X POST -H 'Content-Type: application/json' \
    -d "$(printf '%s' "${text}" | python3 -c 'import sys, json; print(json.dumps({"text": sys.stdin.read()}))')" \
    "${url}" >/dev/null || true
}

MAINTENANCE_COMMANDS=(
  "/memory-clean --apply"
  "/general-clean all"
  "/claude-update-fix push"
  "/serena-update-fix push"
)

ts="$(date +%Y%m%d-%H%M%S)"
log_file="${LOG_DIR}/maintenance-cron-${ts}.log"

cd "$REPO_ROOT"
[[ -n "$TIMEOUT_BIN" ]] || printf 'WARN: timeout / gtimeout が無いため無制限で実行する\n' >> "$log_file"
FAILED_COMMANDS=()
for cmd in "${MAINTENANCE_COMMANDS[@]}"; do
  printf '=== %s (%s) ===\n' "$cmd" "$(date '+%F %T')" >> "$log_file"
  attempt=0
  while :; do
    rc=0
    out_file="$(mktemp)"
    if [[ -n "$TIMEOUT_BIN" ]]; then
      "$TIMEOUT_BIN" "$CMD_MAX_SECONDS" "$CLAUDE_BIN" -p "$cmd" --fallback-model sonnet > "$out_file" 2>&1 || rc=$?
    else
      "$CLAUDE_BIN" -p "$cmd" --fallback-model sonnet > "$out_file" 2>&1 || rc=$?
    fi
    cat "$out_file" >> "$log_file"
    # スリープ復帰直後の DNS 不通は待てば直るので、その失敗だけ再試行する
    if [[ "$rc" -ne 0 && "$attempt" -lt "$NET_RETRY_MAX" ]] && grep -q -E "ENOTFOUND|Can't reach the API" "$out_file"; then
      attempt=$((attempt + 1))
      rm -f "$out_file"
      printf 'WARN: %s は API に接続できず失敗した。%s 秒待って再試行する (%s/%s)\n' "$cmd" "$NET_RETRY_WAIT" "$attempt" "$NET_RETRY_MAX" >> "$log_file"
      sleep "$NET_RETRY_WAIT"
      continue
    fi
    rm -f "$out_file"
    break
  done
  if [[ "$rc" -ne 0 ]]; then
    if [[ "$rc" -eq 124 ]]; then
      printf 'WARN: %s が %s 秒で timeout した\n' "$cmd" "$CMD_MAX_SECONDS" >> "$log_file"
    else
      printf 'WARN: %s が非 0 で終了した (exit %s)\n' "$cmd" "$rc" >> "$log_file"
    fi
    FAILED_COMMANDS+=("$cmd")
  fi
done

# first-ctx 床値の regression 検知 (claude CLI 不要の直接実行、warn は log で確認)
printf '=== first-ctx-check (%s) ===\n' "$(date '+%F %T')" >> "$log_file"
if ! "${REPO_ROOT}/scripts/first-ctx-check.sh" --log >> "$log_file" 2>&1; then
  printf 'WARN: first-ctx threshold 超過 session あり\n' >> "$log_file"
fi

# Verification 自動計測 (数値追記のみ、判断は retrospective に委ねる)
printf '=== verification-report (%s) ===\n' "$(date '+%F %T')" >> "$log_file"
"${REPO_ROOT}/scripts/verification-report.sh" >> "$log_file" 2>&1 \
  || printf 'WARN: verification-report failed\n' >> "$log_file"

printf '=== rule-recall-surface (%s) ===\n' "$(date '+%F %T')" >> "$log_file"
"${REPO_ROOT}/scripts/rule-recall-surface.sh" >> "$log_file" 2>&1 \
  || printf 'WARN: rule-recall-surface failed\n' >> "$log_file"

# 第 1 月曜のみ月次棚卸しを出す (weekly 月曜実行 × 日付 gate)
if [[ "$(date +%d | sed 's/^0//')" -le 7 ]]; then
  printf '=== toolchain-health-report (%s) ===\n' "$(date '+%F %T')" >> "$log_file"
  "${REPO_ROOT}/scripts/toolchain-health-report.sh" >> "$log_file" 2>&1 \
    || printf 'WARN: toolchain-health-report failed\n' >> "$log_file"
else
  printf 'skip: toolchain-health-report (第 1 月曜のみ)\n' >> "$log_file"
fi

status="OK"
[[ ${#FAILED_COMMANDS[@]} -eq 0 ]] || status="FAILED (${FAILED_COMMANDS[*]})"

notify "maintenance-cron [${status}] ($(date '+%F %H:%M'))
log: ${log_file}
--- claude-update-fix / serena-update-fix tail ---
$(grep -A 20 '^=== /claude-update-fix' "${log_file}" | tail -n 25)"

echo "done: ${log_file}"
