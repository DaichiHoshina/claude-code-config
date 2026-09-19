#!/usr/bin/env bash
# loop.sh 定期実行 (launchd) install helper
#
# 目的: /loop cron の実体。指定 loop を launchd で定期実行する plist を配置する。
#
# MVL 順序 enforcement: state.md に `- Status: done` (= manual run の exit 0 実績) が
#   ない loop の cron 化は拒否する (manual run reliable → loop-ify → schedule)。
#   意図的に skip する場合のみ LOOP_CRON_FORCE=1。
#
# 安全性: default では plist 配置のみ、`launchctl bootstrap` は user 手動実行。
#   --enable で opt-in 自動 bootstrap (idempotent、bootout → bootstrap で再 load)。
#
# Usage:
#   ./scripts/install-loop-cron.sh --name <name> --gate "<cmd>" --schedule "<5-field cron>" [options]
#
# Options:
#   --name <name>        loop ID (必須)
#   --gate "<cmd>"       objective gate (必須)
#   --schedule "<cron>"  "min hour dom mon dow" 形式。数値と * のみ対応 (必須)
#   --repo <path>        loop.sh に渡す作業 repo (default: このスクリプトの repo root)
#   --loop-args "<args>" loop.sh への追加 flag をそのまま渡す (例: "--max-iter 5 --review")
#   --enable             launchctl bootstrap まで自動
#   --dry-run            plist 内容のみ表示
set -euo pipefail

DETECTED_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/launchd-install.sh
source "${DETECTED_ROOT}/lib/launchd-install.sh"
NAME=""
GATE=""
SCHEDULE=""
REPO=""
LOOP_ARGS=""
DRY_RUN=0
ENABLE=0
PLIST_DIR="${HOME}/Library/LaunchAgents"
LOG_DIR="${HOME}/.claude/logs"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --gate) GATE="$2"; shift 2 ;;
    --schedule) SCHEDULE="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --loop-args) LOOP_ARGS="$2"; shift 2 ;;
    --enable) ENABLE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$NAME" && -n "$GATE" && -n "$SCHEDULE" ]] || {
  echo "ERROR: --name / --gate / --schedule は必須" >&2
  exit 2
}
[[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "ERROR: --name は英数と . _ - のみ" >&2; exit 2; }
[[ -n "$REPO" ]] || REPO="$DETECTED_ROOT"

LABEL="com.daichi.loop.${NAME}"
PLIST_PATH="${PLIST_DIR}/${LABEL}.plist"
LOOP_SH="${DETECTED_ROOT}/scripts/loop.sh"
STATE="${HOME}/.claude/loops/${NAME}/state.md"

# worktree 検出: cron 実行時に worktree が消えている可能性がある (hook-bench-cron と同じ guard)
launchd_check_worktree_script_root "${LOOP_CRON_ALLOW_WT:-0}" "$DETECTED_ROOT" "worktree" \
  "main repo の scripts/install-loop-cron.sh から実行してください" || exit $?

[[ -x "$LOOP_SH" ]] || { echo "ERROR: ${LOOP_SH} が見つかりません" >&2; exit 2; }

# MVL 順序 enforcement: manual run の成功実績 (Status: done) を要求
if [[ "${LOOP_CRON_FORCE:-0}" -ne 1 ]]; then
  if ! grep -q '^- Status: done' "$STATE" 2>/dev/null; then
    cat >&2 <<EOF
ERROR: loop '${NAME}' に manual run の成功実績 (Status: done) がありません。
  先に手動で green を確認してください: ${LOOP_SH} --name ${NAME} --gate "<cmd>"
  (manual run reliable → loop-ify → schedule。強行は LOOP_CRON_FORCE=1)
EOF
    exit 2
  fi
fi

CALENDAR_XML="$(launchd_calendar_interval_from_cron5 "$SCHEDULE")" || exit $?

# loop.sh は連想配列非依存だが、launchd の PATH は最小構成のため
# claude / jq を解決できる login shell 経由 (-lc) で起動する
BASH_BIN="$(command -v bash)"

PLIST_CONTENT="$(launchd_render_plist "$LABEL" \
  "${LOG_DIR}/loop-cron-${NAME}.stdout.log" "${LOG_DIR}/loop-cron-${NAME}.stderr.log" "$CALENDAR_XML" \
  "$BASH_BIN" "-lc" "${LOOP_SH} --name ${NAME} --repo ${REPO} --gate '${GATE}' --notify ${LOOP_ARGS}")"

launchd_preview_if_dry_run "$DRY_RUN" "$PLIST_PATH" "$PLIST_CONTENT" && exit 0

launchd_write_plist "$PLIST_DIR" "$LOG_DIR" "$PLIST_PATH" "$PLIST_CONTENT"

if [[ "$ENABLE" -eq 1 ]]; then
  launchd_bootstrap_enable "$LABEL" "$PLIST_PATH" 0 || exit 1
else
  launchd_print_enable_instructions "$LABEL" "$PLIST_PATH" 0
  cat <<EOF

uninstall:
  launchctl bootout gui/\$(id -u)/${LABEL}
  rm "${PLIST_PATH}"
EOF
fi
