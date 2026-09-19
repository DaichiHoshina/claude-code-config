#!/usr/bin/env bash
# Usage: audit-cron-run.sh [--repo <path>] [--level <severity>]
# 週次の依存脆弱性 audit。High 以上の finding を sleep-proposals 形式で staging し、
# 朝の /sleep-review triage に合流させる。finding なしは log のみで終了する。
# exit: 0=clean or staged or skip / 2=env error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/redact.sh
source "${ROOT}/lib/redact.sh"

REPO="$(cd "${ROOT}/.." && pwd)"
LEVEL="high"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --level) LEVEL="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v npm >/dev/null || { echo "ERROR: npm が見つかりません" >&2; exit 2; }
command -v jq >/dev/null || { echo "ERROR: jq が見つかりません" >&2; exit 2; }
[[ -f "${ROOT}/package-lock.json" ]] || { echo "ERROR: package-lock.json がない: ${ROOT}" >&2; exit 2; }
[[ -d "${REPO}/memory" ]] || { echo "ERROR: ${REPO}/memory がない" >&2; exit 2; }

DATE="$(date '+%F')"
STAGE_FILE="${REPO}/memory/sleep-proposals-${DATE}-audit.md"
LOG_DIR="${HOME}/.claude/logs"
LOG="${LOG_DIR}/audit-cron.log"
mkdir -p "${LOG_DIR}"

_log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "${LOG}"; }

if ls "${REPO}/memory/sleep-proposals-${DATE}-audit"*.md >/dev/null 2>&1; then
  _log "当日分が既に存在するため skip (idempotent)"
  exit 0
fi

# npm audit は finding ありで exit 1 を返すため || true で受け、JSON の中身で判定する
audit_json="$( (cd "${ROOT}" && npm audit --audit-level="${LEVEL}" --json) 2>>"${LOG}" || true )"
if ! jq -e '.metadata.vulnerabilities' <<< "${audit_json}" >/dev/null 2>&1; then
  echo "ERROR: npm audit の JSON を parse できない (詳細: ${LOG})" >&2
  exit 2
fi

critical=$(jq -r '.metadata.vulnerabilities.critical // 0' <<< "${audit_json}")
high=$(jq -r '.metadata.vulnerabilities.high // 0' <<< "${audit_json}")
total=$((critical + high))

if [[ "${total}" -eq 0 ]]; then
  _log "clean: high 以上の脆弱性なし"
  exit 0
fi

pkgs=$(jq -r '[.vulnerabilities // {} | to_entries[]
  | select(.value.severity == "high" or .value.severity == "critical") | .key]
  | unique | join(", ")' <<< "${audit_json}" | cut -c1-200)

{
  printf '# sleep proposals %s (audit)\n\n' "${DATE}"
  printf '### P1: npm 依存の high 以上の脆弱性 %s 件を解消する\n\n' "${total}"
  printf -- '- Type: audit\n'
  printf -- '- Target: claude-code/package.json\n'
  printf -- '- Evidence: npm audit で critical %s 件 / high %s 件 (対象: %s)\n' "${critical}" "${high}" "${pkgs}"
  # shellcheck disable=SC2016 # backtick は markdown の code span で、shell 展開ではない
  printf -- '- Change: claude-code/ で `npm audit fix` を実行し、`npm test` で回帰がないことを確認して commit する。fix で解消しない場合は該当 package の version 更新を個別に検討する\n'
  printf -- '- Risk: transitive 依存の version 変更で statusline 等の test が失敗する可能性がある\n'
} | redact_private_terms > "${STAGE_FILE}"

_log "staged: ${STAGE_FILE} (critical ${critical} / high ${high})"

_log "gate C: self-review (auto-adopt)"
if self_review_out="$("${SCRIPT_DIR}/sleep-self-review.sh" "${STAGE_FILE}" 2>>"${LOG}")"; then
  _log "self-review: ${self_review_out}"
else
  _log "WARN: self-review 失敗 (exit $?)、staging のみで継続"
fi
echo "staged: ${STAGE_FILE}"
