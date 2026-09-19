#!/usr/bin/env bash
# hook-bench 週次 cron (launchd) install helper
#
# 目的: hook latency 退化を継続検出するため、毎週月曜 09:00 に
#   `./scripts/hook-bench.sh --log --diff` を実行する launchd plist を配置する。
#
# 安全性: default では plist 配置のみ、`launchctl bootstrap` は user 手動実行。
#   --enable で opt-in 自動 bootstrap (idempotent、bootout → bootstrap で再 load)。
#
# Usage:
#   ./scripts/install-hook-bench-cron.sh                 # plist を生成して手順を表示
#   ./scripts/install-hook-bench-cron.sh --enable        # plist 配置 + launchctl bootstrap まで自動
#   ./scripts/install-hook-bench-cron.sh --dry-run       # plist 内容のみ表示
#   ./scripts/install-hook-bench-cron.sh --repo /path    # repo root を明示指定 (worktree から install するとき必須)
set -euo pipefail

DETECTED_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/launchd-install.sh
source "${DETECTED_ROOT}/lib/launchd-install.sh"
REPO_ROOT=""
LABEL="com.daichi.hook-bench.weekly"
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
# (bats など test 用途で意図的に許容したい場合は HOOK_BENCH_CRON_ALLOW_WT=1)
launchd_check_worktree_repo_root HOOK_BENCH_CRON_ALLOW_WT "$REPO_ROOT" "ai-tools-wt-" \
  "./scripts/install-hook-bench-cron.sh --repo \$HOME/ghq/github.com/<owner>/ai-tools/claude-code" || exit $?

launchd_check_executable "${REPO_ROOT}/scripts/hook-bench.sh" "${REPO_ROOT}/scripts/hook-bench.sh" || exit $?

# hook-bench.sh は連想配列 (declare -A) を使うため bash 4+ が必須。
# launchd の login shell から `env bash` を解決すると macOS 標準の 3.2 を拾い
# `declare: -A: invalid option` で失敗するため、install 時に 4+ の bash を
# 検出して plist の interpreter に絶対 path で固定する
BASH_BIN=""
for cand in /opt/homebrew/bin/bash /usr/local/bin/bash "$(command -v bash 2>/dev/null)"; do
  [[ -x "$cand" ]] || continue
  major="$("$cand" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)"
  if [[ "${major:-0}" -ge 4 ]]; then
    BASH_BIN="$cand"
    break
  fi
done
if [[ -z "$BASH_BIN" ]]; then
  echo "ERROR: bash 4+ が見つかりません (hook-bench.sh は declare -A 依存)。'brew install bash' してください" >&2
  exit 2
fi

CALENDAR_XML="$(launchd_calendar_interval_weekly 9 0)"
PLIST_CONTENT="$(launchd_render_plist "$LABEL" \
  "${LOG_DIR}/hook-bench-cron.stdout.log" "${LOG_DIR}/hook-bench-cron.stderr.log" "$CALENDAR_XML" \
  "$BASH_BIN" "-lc" "cd ${REPO_ROOT} &amp;&amp; ${BASH_BIN} ./scripts/hook-bench.sh --log --diff")"

launchd_preview_if_dry_run "$DRY_RUN" "$PLIST_PATH" "$PLIST_CONTENT" && exit 0

launchd_write_plist "$PLIST_DIR" "$LOG_DIR" "$PLIST_PATH" "$PLIST_CONTENT"

if [[ "$ENABLE" -eq 1 ]]; then
  launchd_bootstrap_enable "$LABEL" "$PLIST_PATH" 1 || exit 1
else
  launchd_print_enable_instructions "$LABEL" "$PLIST_PATH" 1
fi

cat <<EOF

スケジュール: 毎週月曜 09:00 / cd ${REPO_ROOT} && ./scripts/hook-bench.sh --log --diff
log: ${LOG_DIR}/hook-bench-<ts>.log
cron stdout/stderr: ${LOG_DIR}/hook-bench-cron.{stdout,stderr}.log

uninstall:
  launchctl bootout gui/\$(id -u)/${LABEL}
  rm "${PLIST_PATH}"
EOF
