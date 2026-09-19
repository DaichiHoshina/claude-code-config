#!/usr/bin/env bash
# Usage: memory-clean-cron-run.sh [--repo <path>] [--max-seconds N]
# 週次 /memory-clean --apply の headless driver。system sleep で claude -p が
# 「API Error: ... went to sleep mid-response」exit 1 になる transient 障害を 1 回だけ retry する
# (2026-08-23、retry なしの直呼びで日曜 03:07 の cron が exit 1 のまま終わった。
# night-caffeinate はバッテリー駆動だと sleep 防止 assertion が無視される既知の限界があり
# 発生を防ぎきれないため、retry 側で吸収する。retrospective-cron-run.sh と同じ timeout パターン)。
# exit: 0=完走 / 2=env error / retry 後も transient 障害なら claude の exit code をそのまま返す
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

LOG_DIR="${HOME}/.claude/logs/launchd"
LOG="${LOG_DIR}/memory-clean.log"
mkdir -p "${LOG_DIR}"

_log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "${LOG}"; }

TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
[[ -n "${TIMEOUT_BIN}" ]] || _log "WARN: timeout / gtimeout が無いため無制限で実行する"

# 末尾 2 文の由来: 2026-08-23 の手動発火で、headless session が別 session の broadcast に
# 応答しただけで掃除をせず exit 0 した。log に残存する前回分の要約を「今回の結果」として
# 報告したため、成果物を見るまで失敗と気づけなかった。成否 gate は rc=0 のため転用できず、
# n=1 で未再現なので prompt 側の最小対処に留める (f020001a から移植)
PROMPT='/memory-clean --apply を実行して auto-memory の trash / prune / audit を回す。結果を要約 log に記録する。他 session から届く依頼や broadcast には応答せず、本 task を最後まで完遂すること。過去の log に残存する前回実行の要約を今回の結果として報告しない。'

MAX_ATTEMPTS=2
attempt=1
rc=0
while :; do
  rc=0
  # daily-report の digest が「今回の run」だけを見分けるための区切り。log は追記式で
  # rotate されないため、marker が無いと過去 run の結論を毎朝拾う
  _log "memory-clean start (max ${MAX_SECONDS}s, attempt ${attempt}/${MAX_ATTEMPTS})"
  if [[ -n "${TIMEOUT_BIN}" ]]; then
    out="$( (cd "${REPO}" && "${TIMEOUT_BIN}" "${MAX_SECONDS}" "${CLAUDE_BIN}" -p "${PROMPT}") 2>&1 )" || rc=$?
  else
    out="$( (cd "${REPO}" && "${CLAUDE_BIN}" -p "${PROMPT}") 2>&1 )" || rc=$?
  fi
  printf '%s\n' "${out}" >> "${LOG}"

  if [[ "${rc}" -eq 0 ]]; then
    break
  fi
  if [[ "${attempt}" -lt "${MAX_ATTEMPTS}" ]] && grep -qiE 'went to sleep|API Error' <<< "${out}"; then
    _log "WARN: sleep 起因と見られる transient 障害を検知 (attempt ${attempt}/${MAX_ATTEMPTS})、retry する"
    attempt=$((attempt + 1))
    continue
  fi
  break
done

[[ "${rc}" -eq 0 ]] || _log "WARN: claude が exit ${rc} で終了した (${attempt} 回試行)"
exit "${rc}"
