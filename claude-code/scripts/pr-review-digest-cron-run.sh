#!/usr/bin/env bash
# Usage: pr-review-digest-cron-run.sh [--repo <path>]
# 平日朝の pr-review-digest headless driver。plist から claude -p を直に叩いていたため
# log に run の区切りが無く、daily-report の digest が過去 run の PR 件数まで合算していた。
# 本 script は marker を stdout へ出力するだけで、claude の出力と exit code はそのまま通す。
# スリープ対策の retry は入れない (since-cursor を成功時しか進めないので、失敗した回の
# 範囲は次の成功実行が拾う。canonical: references/cron-jobs.md)。
# exit: 2=env error / それ以外は claude の exit code
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO="$(cd "${ROOT}/.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || true)}"
[[ -n "${CLAUDE_BIN}" ]] || { echo "ERROR: claude CLI が見つかりません" >&2; exit 2; }
# git 自体の実行可否と --repo 指定を分けて診断する。Xcode license 未同意で
# /usr/bin/git が全 subcommand を失敗させると、直後の rev-parse が「repo でない」
# として誤診されて job が cron から見えなくなる (2026-09-15 実踏)。
_git_ver="$(git --version 2>&1)"; _git_rc=$?
if [[ ${_git_rc} -ne 0 ]]; then
  echo "ERROR: git が実行できない (exit ${_git_rc}): ${_git_ver}" >&2
  echo "  Xcode license 未同意なら 'sudo xcodebuild -license' を実行する" >&2
  exit 2
fi
git -C "${REPO}" rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: --repo が git repo でない: ${REPO}" >&2; exit 2; }

# stdout はそのまま plist の StandardOutPath へ出力される。log path を script に含めないので
# plist 側で出力先を変えても同じ先へ出力する
_log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

PROMPT='/pr-review-digest を実行して、前回集計以降に付いた他者コメントを対象 doc に追記する。build.mjs が exit 0 なら done、fail なら snapshot から restore して報告する。'

_log "pr-review-digest start"
rc=0
(cd "${REPO}" && "${CLAUDE_BIN}" -p "${PROMPT}") || rc=$?
_log "pr-review-digest done (exit ${rc})"
exit "${rc}"
