#!/usr/bin/env bash
# Usage: install-sleep-cron.sh [--schedule "<5-field cron>"] [--repo <path>] [--enable] [--dry-run]
# sleep-cron-run.sh を launchd で毎晩実行する plist を配置する。default は 03:30。
# 手動 run 実績 (state.md の Status: done) がなければ拒否する (強行は SLEEP_CRON_FORCE=1)
set -euo pipefail

DETECTED_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/launchd-install.sh
source "${DETECTED_ROOT}/lib/launchd-install.sh"
SCHEDULE="30 3 * * *"
REPO=""
DRY_RUN=0
ENABLE=0
PLIST_DIR="${HOME}/Library/LaunchAgents"
LOG_DIR="${HOME}/.claude/logs"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --schedule) SCHEDULE="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --enable) ENABLE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "${REPO}" ]] || REPO="$(cd "${DETECTED_ROOT}/.." && pwd)"

LABEL="com.daichi.sleep-pipeline.daily"
PLIST_PATH="${PLIST_DIR}/${LABEL}.plist"
RUN_SH="${DETECTED_ROOT}/scripts/sleep-cron-run.sh"
STATE="${SLEEP_STATE_DIR:-${HOME}/.claude/sleep}/state.md"

launchd_check_worktree_script_root "${SLEEP_CRON_ALLOW_WT:-0}" "${DETECTED_ROOT}" "worktree" \
  "main repo の scripts/install-sleep-cron.sh から実行してください" || exit $?

[[ -x "${RUN_SH}" ]] || { echo "ERROR: ${RUN_SH} が見つかりません" >&2; exit 2; }

if [[ "${SLEEP_CRON_FORCE:-0}" -ne 1 ]]; then
  if ! grep -q '^- Status: done' "${STATE}" 2>/dev/null; then
    cat >&2 <<EOF
ERROR: sleep pipeline に manual run の成功実績 (Status: done) がありません。
  先に手動で確認してください: ${RUN_SH}
  (manual run reliable → loop-ify → schedule。強行は SLEEP_CRON_FORCE=1)
EOF
    exit 2
  fi
fi

CALENDAR_XML="$(launchd_calendar_interval_from_cron5 "${SCHEDULE}")" || exit $?

BASH_BIN="$(command -v bash)"

PLIST_CONTENT="$(launchd_render_plist "$LABEL" \
  "${LOG_DIR}/sleep-cron.stdout.log" "${LOG_DIR}/sleep-cron.stderr.log" "$CALENDAR_XML" \
  "$BASH_BIN" "-lc" "${RUN_SH} --repo ${REPO}")"

launchd_preview_if_dry_run "${DRY_RUN}" "${PLIST_PATH}" "$PLIST_CONTENT" && exit 0

launchd_write_plist "${PLIST_DIR}" "${LOG_DIR}" "${PLIST_PATH}" "$PLIST_CONTENT"

if [[ "${ENABLE}" -eq 1 ]]; then
  launchd_bootstrap_enable "$LABEL" "${PLIST_PATH}" 0 || exit 1
else
  launchd_print_enable_instructions "$LABEL" "${PLIST_PATH}" 0
  cat <<EOF

uninstall:
  launchctl bootout gui/\$(id -u)/${LABEL}
  rm "${PLIST_PATH}"
EOF
fi
