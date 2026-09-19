#!/usr/bin/env bash
# PreCompact Hook - 圧縮前に文脈スナップショットを file へ保存する
#
# 公式仕様 (https://code.claude.com/docs/en/hooks) が課す制約:
#   - PreCompact の systemMessage / continue は破棄され、additionalContext も受け付けない。
#     AI へ「save しろ」と指示する経路が存在しないので、hook 自身が transcript から書く。
#   - decision:"block" で compact を止めることはできるが、trigger=auto を止めると
#     context 上限到達後の復旧 compact では request 自体が失敗する。よって block は使わない。
#
# 保存先: ${MEMORY_SAVE_DIR:-<repo-root>/memory}/compact-restore-<ts>.md
#   直近 5 分以内に同名 file があれば AI が書いた版とみなし、上書きせず温存する
#   (user-prompt-submit.sh の自然語 compact 経路が生成する。中身が hook 生成より濃い)。
#
# 状態 file: ${HOME}/.claude/.compact-memory-state
#   "ready:<timestamp>" を書き込み、session-start.sh (source=compact) が読む。読んだら削除する契約

set -euo pipefail

_pc_src="${BASH_SOURCE[0]}"
[[ "${_pc_src}" == /* ]] || _pc_src="${PWD}/${_pc_src}"
SCRIPT_DIR="${_pc_src%/*}"
# shellcheck source=../lib/hook-utils.sh
source "${SCRIPT_DIR}/../lib/hook-utils.sh"

require_jq

INPUT=$(cat)
TRIGGER=$(printf '%s' "${INPUT}" | jq -r '.trigger // "manual"' 2>/dev/null || echo "manual")
TRANSCRIPT=$(printf '%s' "${INPUT}" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
HOOK_CWD=$(printf '%s' "${INPUT}" | jq -r '.cwd // ""' 2>/dev/null || echo "")
[ -n "${HOOK_CWD}" ] || HOOK_CWD="${PWD}"

STATE_FILE="${HOME}/.claude/.compact-memory-state"
mkdir -p "$(dirname "${STATE_FILE}")"

printf -v TIMESTAMP '%(%Y%m%d_%H%M%S)T' -1
MEMORY_DIR="${MEMORY_SAVE_DIR:-${HOME}/ai-tools/memory}"
MEMORY_PATH="${MEMORY_DIR}/compact-restore-${TIMESTAMP}.md"

# --- AI 生成版の有無を見る -------------------------------------------
# 直近 5 分以内の compact-restore-*.md は AI が書いた版。hook 生成で潰さない
SAVE_WINDOW_MIN=5
existing_save() {
  [ -d "${MEMORY_DIR}" ] || return 1
  local hit
  hit=$(find "${MEMORY_DIR}" -maxdepth 1 -name 'compact-restore-*.md' -type f -mmin "-${SAVE_WINDOW_MIN}" 2>/dev/null | head -1)
  [ -n "${hit}" ] || return 1
  printf '%s' "${hit}"
}

# --- transcript から直近 user 発言を拾う ------------------------------
recent_user_prompts() {
  [ -n "${TRANSCRIPT}" ] && [ -f "${TRANSCRIPT}" ] || return 0
  jq -r '
    select(.type == "user" and (has("toolUseResult") | not) and (.isMeta | not))
    | (.message.content
       | if type == "string" then . else (map(select(.type == "text").text) | join(" ")) end)
    | select(test("<system-reminder>|<task-notification>|<local-command|<command-name>|\\[Request interrupted") | not)
    | select(length > 2)
  ' "${TRANSCRIPT}" 2>/dev/null | tail -5 | cut -c1-300 | sed 's/^/   - /'
}

write_snapshot() {
  mkdir -p "${MEMORY_DIR}" 2>/dev/null || return 1

  local branch status log prompts
  branch=$(git -C "${HOOK_CWD}" branch --show-current 2>/dev/null || echo "unknown")
  status=$(git -C "${HOOK_CWD}" --no-optional-locks status --short 2>/dev/null | head -20 || echo "")
  log=$(git -C "${HOOK_CWD}" log --oneline -5 2>/dev/null || echo "")
  prompts=$(recent_user_prompts)
  [ -n "${prompts}" ] || prompts="   - (transcript から抽出できず)"

  {
    echo "---"
    echo "name: compact-restore-${TIMESTAMP}"
    echo "description: PreCompact hook が ${TRIGGER} compact 直前に機械生成した文脈 snapshot"
    echo "metadata:"
    echo "  type: project"
    echo "---"
    echo
    echo "> hook が transcript / git から機械生成した。AI が書いた版より粗い。"
    echo
    echo "1. 直近 user 発言 (transcript 末尾 5 件、各 300 字まで)"
    echo "${prompts}"
    echo
    echo "2. 作業場所"
    echo "   - dir: ${HOOK_CWD}"
    echo "   - branch: ${branch}"
    echo
    echo "3. 未 commit 変更"
    if [ -n "${status}" ]; then
      printf '%s\n' '```'
      printf '%s\n' "${status}"
      printf '%s\n' '```'
    else
      echo "   - なし (working tree clean)"
    fi
    echo
    echo "4. 直近 commit"
    if [ -n "${log}" ]; then
      printf '%s\n' '```'
      printf '%s\n' "${log}"
      printf '%s\n' '```'
    else
      echo "   - 取得できず"
    fi
    echo
    echo "5. compact trigger"
    echo "   - ${TRIGGER}"
  } > "${MEMORY_PATH}"
}

# session-start が AI に rm を指示する設計だが実際には保持されるので、1 日超は hook 側で消す
[ -d "${MEMORY_DIR}" ] && find "${MEMORY_DIR}" -maxdepth 1 -name 'compact-restore-*.md' -type f -mtime +1 -delete 2>/dev/null || true

SAVED_BY="hook"
if RESTORE_FILE=$(existing_save); then
  SAVED_BY="ai"
  TIMESTAMP=$(basename "${RESTORE_FILE}" .md)
  TIMESTAMP="${TIMESTAMP#compact-restore-}"
elif write_snapshot; then
  RESTORE_FILE="${MEMORY_PATH}"
else
  SAVED_BY="none"
  RESTORE_FILE=""
fi

echo "ready:${TIMESTAMP}" > "${STATE_FILE}"

# compact は必ず通す。PreCompact の output は AI にも user にも届かないため、
# 記録は log と state file に残し、復元は session-start.sh (source=compact) が担う
_PC_LOG_DIR="${HOME}/.claude/logs"
if [ -d "${_PC_LOG_DIR}" ]; then
  printf '%s pre-compact trigger=%s saved_by=%s file=%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "${TRIGGER}" "${SAVED_BY}" "${RESTORE_FILE:-none}" \
    >> "${_PC_LOG_DIR}/compact-notice.log" 2>/dev/null || true
fi

exit 0
