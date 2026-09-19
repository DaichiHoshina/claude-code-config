#!/usr/bin/env bash
# 毎朝 7:00 に軽量 ping を打ち、Claude の 5 時間制限 window を 7-12 / 12-17 / 17-22 に固定する
set -euo pipefail

DETECTED_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/launchd-install.sh
source "${DETECTED_ROOT}/lib/launchd-install.sh"
LABEL="com.daichi.claude-morning-ping.daily"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${PLIST_DIR}/${LABEL}.plist"
LOG_DIR="${HOME}/.claude/logs"
DRY_RUN=0
ENABLE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --enable) ENABLE=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

launchd_check_worktree_script_root "${MORNING_PING_CRON_ALLOW_WT:-0}" "$DETECTED_ROOT" "worktree" \
  "main repo の scripts/install-morning-ping-cron.sh から実行してください" || exit $?

# launchd の PATH に ~/.local/bin が無いため、install 時に絶対 path を解決して plist に固定する
CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
if [[ -z "$CLAUDE_BIN" || ! -x "$CLAUDE_BIN" ]]; then
  echo "ERROR: claude binary が見つかりません (PATH に claude が必要)" >&2
  exit 2
fi

CALENDAR_XML="$(launchd_calendar_interval_daily 7 0)"
PLIST_CONTENT="$(launchd_render_plist "$LABEL" \
  "${LOG_DIR}/morning-ping-cron.stdout.log" "${LOG_DIR}/morning-ping-cron.stderr.log" "$CALENDAR_XML" \
  "$CLAUDE_BIN" "-p" "ping" "--model" "haiku")"

launchd_preview_if_dry_run "$DRY_RUN" "$PLIST_PATH" "$PLIST_CONTENT" && exit 0

launchd_write_plist "$PLIST_DIR" "$LOG_DIR" "$PLIST_PATH" "$PLIST_CONTENT"

if [[ "$ENABLE" -eq 1 ]]; then
  launchd_bootstrap_enable "$LABEL" "$PLIST_PATH" 1 || exit 1
else
  launchd_print_enable_instructions "$LABEL" "$PLIST_PATH" 1
fi

cat <<EOF

スケジュール: 毎日 07:00 / ${CLAUDE_BIN} -p "ping" --model haiku
cron stdout/stderr: ${LOG_DIR}/morning-ping-cron.{stdout,stderr}.log

uninstall:
  launchctl bootout gui/\$(id -u)/${LABEL}
  rm "${PLIST_PATH}"
EOF
