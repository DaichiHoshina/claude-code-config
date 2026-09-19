#!/usr/bin/env bash
# maintenance loop 週次 cron (launchd) install helper
#
# 目的: maintenance (/memory-clean --apply, /claude-update-fix push,
#   /serena-update-fix push) を毎週月曜 07:15 に headless 実行する
#   launchd plist を配置する。実体は scripts/maintenance-cron-run.sh。
#   hook-bench cron (月曜 07:00) と時刻をずらして直列衝突を避ける
#   (月曜朝の 15 分刻み配置は references/cron-jobs.md が canonical)。
#
# 安全性: default では plist 配置のみ、`launchctl bootstrap` は user 手動実行。
#   --enable で opt-in 自動 bootstrap (idempotent、bootout → bootstrap で再 load)。
#
# Usage:
#   ./scripts/install-maintenance-cron.sh                 # plist を生成して手順を表示
#   ./scripts/install-maintenance-cron.sh --enable        # plist 配置 + launchctl bootstrap まで自動
#   ./scripts/install-maintenance-cron.sh --dry-run       # plist 内容のみ表示
#   ./scripts/install-maintenance-cron.sh --repo /path    # repo root を明示指定 (worktree から install するとき必須)
set -euo pipefail

DETECTED_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/launchd-install.sh
source "${DETECTED_ROOT}/lib/launchd-install.sh"
REPO_ROOT=""
LABEL="com.daichi.ai-tools-maintenance.weekly"
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

# worktree 検出: REPO_ROOT が ai-tools-wt-* を含む場合は誤配置警告
# (bats など test 用途で意図的に許容したい場合は MAINTENANCE_CRON_ALLOW_WT=1)
launchd_check_worktree_repo_root MAINTENANCE_CRON_ALLOW_WT "$REPO_ROOT" "ai-tools-wt-" \
  "./scripts/install-maintenance-cron.sh --repo \$HOME/ghq/github.com/<owner>/ai-tools/claude-code" || exit $?

launchd_check_executable "${REPO_ROOT}/scripts/maintenance-cron-run.sh" "${REPO_ROOT}/scripts/maintenance-cron-run.sh" || exit $?

# launchd の bash -lc では ~/.local/bin が PATH に入らないので、install 時点で絶対 path を解決して plist に埋め込む
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || true)}"
if [[ -z "${CLAUDE_BIN}" || ! -x "${CLAUDE_BIN}" ]]; then
  echo "ERROR: claude CLI が見つかりません (PATH または CLAUDE_BIN で指定してください)" >&2
  exit 2
fi

CALENDAR_XML="$(launchd_calendar_interval_weekly 7 15)"
PLIST_CONTENT="$(launchd_render_plist "$LABEL" \
  "${LOG_DIR}/maintenance-cron.stdout.log" "${LOG_DIR}/maintenance-cron.stderr.log" "$CALENDAR_XML" \
  "/bin/bash" "-lc" "cd ${REPO_ROOT} &amp;&amp; CLAUDE_BIN=${CLAUDE_BIN} ./scripts/maintenance-cron-run.sh")"

launchd_preview_if_dry_run "$DRY_RUN" "$PLIST_PATH" "$PLIST_CONTENT" && exit 0

launchd_write_plist "$PLIST_DIR" "$LOG_DIR" "$PLIST_PATH" "$PLIST_CONTENT"

if [[ "$ENABLE" -eq 1 ]]; then
  launchd_bootstrap_enable "$LABEL" "$PLIST_PATH" 1 || exit 1
else
  launchd_print_enable_instructions "$LABEL" "$PLIST_PATH" 1
fi

cat <<EOF

スケジュール: 毎週月曜 07:15 / cd ${REPO_ROOT} && ./scripts/maintenance-cron-run.sh
log: ${LOG_DIR}/maintenance-cron-<ts>.log
cron stdout/stderr: ${LOG_DIR}/maintenance-cron.{stdout,stderr}.log

uninstall:
  launchctl bootout gui/\$(id -u)/${LABEL}
  rm "${PLIST_PATH}"
EOF
