#!/usr/bin/env bash
# Usage: retrospective-cron-run.sh [--repo <path>] [--max-seconds N]
# 週次 retrospective の headless driver。claude -p を timeout + tracked file guard で包み、
# 無人実行が repo 管理 file を直接変更したら復元 / 隔離して warn flag を設定する
# (mine と同じ guard。retrospective は Bash / Write が必要なため tool 遮断では守れない)。
# exit: 0=完走 (違反は復元済) / 2=env error / 5=claude 失敗かつ成果物なし
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/tracked-guard.sh
source "${ROOT}/lib/tracked-guard.sh"

REPO="$(cd "${ROOT}/.." && pwd)"
MAX_SECONDS=1800

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --max-seconds) MAX_SECONDS="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || true)}"
[[ -n "${CLAUDE_BIN}" ]] || { echo "ERROR: claude CLI が見つかりません" >&2; exit 2; }
git -C "${REPO}" rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: --repo が git repo でない: ${REPO}" >&2; exit 2; }

STATE_DIR="${SLEEP_STATE_DIR:-${HOME}/.claude/sleep}"
LOG_DIR="${HOME}/.claude/logs"
LOG="${LOG_DIR}/retrospective-cron.log"
WARN_FLAG="${STATE_DIR}/tracked-change-warn"
DATE="$(date '+%F')"
mkdir -p "${STATE_DIR}" "${LOG_DIR}"
tracked_guard_cleanup_quarantine "${STATE_DIR}"

_log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "${LOG}"; }

TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
[[ -n "${TIMEOUT_BIN}" ]] || _log "WARN: timeout / gtimeout が無いため無制限で実行する (brew install coreutils を推奨)"

PROMPT='/retrospective を実行して過去 1 週間の session を分析し、skill / config 改善提案を staging する。headless 分岐 (retrospective.md 冒頭) に従い、実装はせず staging のみ行う。翌朝 /sleep-review triage で読める形にする。'

before_fp="$(tracked_guard_fingerprint "${REPO}")"
before_paths="$(tracked_guard_changed_paths "${REPO}")"
_log "retrospective start (max ${MAX_SECONDS}s)"

rc=0
# prompt は stdin で渡す。--disallowedTools が可変長引数のため、直後に positional で
# 置くと prompt 全体が deny rule として食われる (2026-08-16/23 に 2 週連続で全滅)
if [[ -n "${TIMEOUT_BIN}" ]]; then
  (cd "${REPO}" && printf '%s' "${PROMPT}" | "${TIMEOUT_BIN}" "${MAX_SECONDS}" "${CLAUDE_BIN}" -p --disallowedTools "Task") >> "${LOG}" 2>&1 || rc=$?
else
  (cd "${REPO}" && printf '%s' "${PROMPT}" | "${CLAUDE_BIN}" -p --disallowedTools "Task") >> "${LOG}" 2>&1 || rc=$?
fi
[[ "${rc}" -eq 0 ]] || _log "WARN: claude が exit ${rc} で終了した (124 = timeout)"

after_fp="$(tracked_guard_fingerprint "${REPO}")"
if [[ "${before_fp}" != "${after_fp}" ]]; then
  tracked_guard_revert_new_paths "${REPO}" "${before_paths}" "${STATE_DIR}/quarantine-${DATE}-retrospective" \
    | while IFS= read -r line; do _log "guard: ${line}"; done
  printf "%s retrospective\n" "${DATE}" >> "${WARN_FLAG}"
  _log "guard: retrospective が repo 管理 file を変更したため復元した (要確認)"
fi

# gate C は guard 判定の後に置く (auto-adopt の正当な commit を guard が誤検知しないため)
retro_stage="$(ls "${REPO}/memory/sleep-proposals-${DATE}-retrospective"*.md 2>/dev/null | grep -vE '\.(adopted|rejected)\.md$' | head -1 || true)"
if [[ -n "${retro_stage}" ]]; then
  _log "gate C: self-review (auto-adopt)"
  if self_review_out="$("${SCRIPT_DIR}/sleep-self-review.sh" "${retro_stage}" 2>>"${LOG}")"; then
    _log "self-review: ${self_review_out}"
  else
    _log "WARN: self-review 失敗 (exit $?)、staging のみで継続"
  fi
fi
_log "retrospective done"

# 成果物ベースで成否を返す。rc だけを見ると guard 復元後や gate C 分岐と噛み合わず、
# driver 完走 = exit 0 のままだと statusline に「正常終了」と表示されて失敗が 2 週間気づかれない
if [[ "${rc}" -ne 0 && -z "${retro_stage}" ]]; then
  _log "FAIL: claude が exit ${rc} で終わり staging も無い"
  exit 5
fi
