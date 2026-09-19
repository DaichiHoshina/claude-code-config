#!/usr/bin/env bash
# PostCompact Hook - compact 結果の記録のみ
#
# 公式仕様 (https://code.claude.com/docs/en/hooks) では PostCompact に decision control がなく、
# systemMessage / continue は破棄され、additionalContext の注入も保証されない。
# よって文脈復元の指示はここから出せない。復元は session-start.sh (source=compact) が担う。
#
# ここで記録するのは診断用の 1 行だけ: compact が実際に走ったか、要約がどれだけ残存したかを
# ${HOME}/.claude/logs/compact-notice.log で pre-compact の行と突き合わせられるようにする

set -euo pipefail

_pcr_src="${BASH_SOURCE[0]}"
[[ "${_pcr_src}" == /* ]] || _pcr_src="${PWD}/${_pcr_src}"
SCRIPT_DIR="${_pcr_src%/*}"
# shellcheck source=../lib/hook-utils.sh
source "${SCRIPT_DIR}/../lib/hook-utils.sh"

require_jq

INPUT=$(cat)
TRIGGER=$(printf '%s' "${INPUT}" | jq -r '.trigger // "unknown"' 2>/dev/null || echo "unknown")
SUMMARY_LEN=$(printf '%s' "${INPUT}" | jq -r '(.compact_summary // "") | length' 2>/dev/null || echo 0)

LOG_DIR="${HOME}/.claude/logs"
if [ -d "${LOG_DIR}" ]; then
  printf '%s post-compact trigger=%s summary_chars=%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "${TRIGGER}" "${SUMMARY_LEN}" \
    >> "${LOG_DIR}/compact-notice.log" 2>/dev/null || true
fi

exit 0
