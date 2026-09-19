#!/usr/bin/env bash
set -euo pipefail

DETECTED_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/launchd-install.sh
source "${DETECTED_ROOT}/lib/launchd-install.sh"
REPO_ROOT=""
LABEL="com.daichi.flow-baseline-summary.weekly"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${PLIST_DIR}/${LABEL}.plist"
LOG_DIR="${HOME}/.claude/logs"
DRY_RUN=0
ENABLE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --enable) ENABLE=1; shift ;;
    --repo) REPO_ROOT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$DETECTED_ROOT"
fi

launchd_check_worktree_repo_root FLOW_BASELINE_SUMMARY_CRON_ALLOW_WT "$REPO_ROOT" "ai-tools-wt-" \
  "./scripts/install-flow-baseline-summary-cron.sh --repo \$HOME/ghq/github.com/<owner>/ai-tools/claude-code" || exit $?

launchd_check_executable "${REPO_ROOT}/scripts/flow-baseline-summary-cron.sh" "${REPO_ROOT}/scripts/flow-baseline-summary-cron.sh" || exit $?

CALENDAR_XML="$(launchd_calendar_interval_weekly 9 40)"
PLIST_CONTENT="$(launchd_render_plist "$LABEL" \
  "${LOG_DIR}/flow-baseline-summary-cron.stdout.log" "${LOG_DIR}/flow-baseline-summary-cron.stderr.log" "$CALENDAR_XML" \
  "/bin/bash" "-lc" "cd ${REPO_ROOT} &amp;&amp; ./scripts/flow-baseline-summary-cron.sh --diff")"

launchd_preview_if_dry_run "$DRY_RUN" "$PLIST_PATH" "$PLIST_CONTENT" && exit 0

launchd_write_plist "$PLIST_DIR" "$LOG_DIR" "$PLIST_PATH" "$PLIST_CONTENT"

if [[ "$ENABLE" -eq 1 ]]; then
  launchd_bootstrap_enable "$LABEL" "$PLIST_PATH" 1 || exit 1
else
  launchd_print_enable_instructions "$LABEL" "$PLIST_PATH" 1
fi

cat <<EOF

スケジュール: 毎週月曜 09:40 / cd ${REPO_ROOT} && ./scripts/flow-baseline-summary-cron.sh --diff
log: ${LOG_DIR}/flow-baseline-summary-<date>.log
cron stdout/stderr: ${LOG_DIR}/flow-baseline-summary-cron.{stdout,stderr}.log

uninstall:
  launchctl bootout gui/\$(id -u)/${LABEL}
  rm "${PLIST_PATH}"
EOF
