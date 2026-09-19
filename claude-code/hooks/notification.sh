#!/usr/bin/env bash
# Notification Hook - 入力待ち通知を端末ごとの経路で出す
# 本体の preferredNotifChannel は notifications_disabled にして二重発火を避ける

set -euo pipefail

_nt_src="${BASH_SOURCE[0]}"
[[ "${_nt_src}" == /* ]] || _nt_src="${PWD}/${_nt_src}"
HOOK_DIR="${_nt_src%/*}"
LIB_DIR="${HOOK_DIR}/../lib"
source "${LIB_DIR}/hook-utils.sh"
require_jq

INPUT=$(cat)

IFS=$'\x1f' read -r NOTIF_TYPE MESSAGE CWD < <(
  extract_json_fields "$INPUT" \
    '.notification_type // ""' \
    '.message // ""' \
    '.cwd // "."'
)

# 実行許可待ちだけ通知する。idle_prompt は turn 終了のたびに鳴って煩いので黙らせる (user 指示 2026-08-26)
case "${NOTIF_TYPE}" in
  permission_prompt)
    # 本体の文言は "Claude needs your permission to use <tool>"
    TOOL="${MESSAGE##*permission to use }"
    [[ "${TOOL}" == "${MESSAGE}" ]] && TOOL=""
    BODY="${TOOL:+${TOOL} の}実行許可を待っています"
    ;;
  *)
    jq -n '{}'
    exit 0
    ;;
esac

# project の .claude/settings.json が Notification hook を保持する repo (シンフロ等) では、
# 両 scope の hook が並列で走り 1 event で通知が 2 回発生する。repo 側に譲って通知しない
if jq -e '.hooks.Notification | length > 0' "${CWD}/.claude/settings.json" >/dev/null 2>&1; then
  jq -n '{}'
  exit 0
fi

PROJECT=$(basename "${CWD}")
# symbolic-ref は commit 前の repo でも branch を返し、detached HEAD では空になる
BRANCH=$(git -C "${CWD}" symbolic-ref --short HEAD 2>/dev/null) || BRANCH=""
LABEL="${PROJECT}${BRANCH:+ (${BRANCH})}"

# iTerm2 は OSC 9 が通り、クリックで発行元タブへ戻れる。
# JetBrains の JediTerm は OSC 9 を解さず制御文字が画面へ表示されるため通知 command 側へ回す
if [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then
  SEQ=$(printf '\033]9;%s: %s\007' "${LABEL}" "${BODY}")
  jq -n --arg seq "${SEQ}" '{terminalSequence: $seq}'
  exit 0
fi

# Warp は plugin (warp@claude-code-warp) が permission 通知を出すので、ここで重ねない
if [[ "${TERM_PROGRAM:-}" == "WarpTerminal" ]]; then
  jq -n '{}'
  exit 0
fi

if command -v terminal-notifier >/dev/null 2>&1; then
  _tn_args=(-title "Claude: ${LABEL}" -message "${BODY}" -group "claude-${PROJECT}")
  # bundle id は起動元 app のものが env に入る。取れない端末では活性化先を諦めて通知だけ出す
  if [[ -n "${__CFBundleIdentifier:-}" ]]; then
    _tn_args+=(-activate "${__CFBundleIdentifier}")
  fi
  terminal-notifier "${_tn_args[@]}" >/dev/null 2>&1 || true
fi

jq -n '{}'
