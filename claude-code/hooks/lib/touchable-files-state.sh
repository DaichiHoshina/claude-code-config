#!/usr/bin/env bash
# touchable_files state file helper
#
# parent (Opus) が developer-agent fire 時に touchable_files allowlist を state file に write。
# subagent context の Edit/Write hook が読み込んで literal match で path 検証する。
#
# State file format: ~/.claude/state/touchable-<session_id>.txt
#   1 行 1 path (absolute path) / 空行・# コメント許可
#   TTL 3600 sec (mtime 基準)、超過 file は読込時に noop
#   cleanup: session Stop hook (hooks/stop.sh) が自 session 分を削除 + TTL 超過分を GC
#
# Opt-out: env CLAUDE_TOUCHABLE_ENFORCE=0

# shellcheck source=./portable-stat.sh
source "${BASH_SOURCE[0]%/*}/portable-stat.sh"

_TOUCHABLE_STATE_DIR="${HOME}/.claude/state"
_TOUCHABLE_TTL_SEC=3600

# write allowlist to state file (既存内容との union、並列 developer-agent fan-out での
# 上書き合戦を避けるため truncate ではなく merge + dedup する)
# usage: _touchable_write <session_id> <path1> [path2 ...]
_touchable_write() {
  local _sid="$1"; shift
  [[ -z "$_sid" || "$_sid" == "null" ]] && return 0
  mkdir -p "$_TOUCHABLE_STATE_DIR" 2>/dev/null || return 0
  local _f="${_TOUCHABLE_STATE_DIR}/touchable-${_sid}.txt"
  local _lock="${_f}.lock"
  local _wait=0
  while ! mkdir "$_lock" 2>/dev/null; do
    _wait=$((_wait + 1))
    (( _wait > 50 )) && break
    sleep 0.02
  done
  {
    [[ -f "$_f" ]] && cat "$_f"
    local _p
    for _p in "$@"; do
      [[ -n "$_p" ]] && printf '%s\n' "$_p"
    done
  } | awk 'NF' | sort -u > "${_f}.tmp" && mv "${_f}.tmp" "$_f"
  rmdir "$_lock" 2>/dev/null || true
}

# extract touchable_files from Task prompt (YAML block under `touchable_files:`)
# usage: _touchable_extract_from_prompt <prompt_text>
# stdout: 1 path per line (absolute paths only, others skipped)
_touchable_extract_from_prompt() {
  local _prompt="$1"
  [[ -z "$_prompt" ]] && return 0
  awk '
    /^[[:space:]]*touchable_files:[[:space:]]*$/ { in_block=1; next }
    in_block && /^[[:space:]]*-[[:space:]]+/ {
      sub(/^[[:space:]]*-[[:space:]]+/, "")
      sub(/[[:space:]]*$/, "")
      gsub(/^"|"$/, "")
      gsub(/^'\''|'\''$/, "")
      if ($0 ~ /^\//) print
      next
    }
    in_block && /^[^[:space:]]/ { in_block=0 }
  ' <<< "$_prompt"
}

# check whether <target_path> matches any line in <session> state file
# return 0: match (or state file missing / TTL expired / opt-out)
# return 1: violation (state file exists, fresh, opt-in, target not in list)
_touchable_check() {
  local _sid="$1"
  local _target="$2"
  [[ "${CLAUDE_TOUCHABLE_ENFORCE:-1}" == "0" ]] && return 0
  [[ -z "$_sid" || "$_sid" == "null" ]] && return 0
  [[ -z "$_target" ]] && return 0
  local _f="${_TOUCHABLE_STATE_DIR}/touchable-${_sid}.txt"
  [[ ! -f "$_f" ]] && return 0
  local _mtime _now
  _mtime=$(portable_stat_mtime "$_f")
  _now=$(date +%s)
  if (( _now - _mtime > _TOUCHABLE_TTL_SEC )); then
    rm -f "$_f" 2>/dev/null
    return 0
  fi
  # literal match (full line equality, ignoring leading/trailing whitespace)
  local _line
  while IFS= read -r _line; do
    [[ -z "$_line" || "$_line" == \#* ]] && continue
    [[ "$_line" == "$_target" ]] && return 0
  done < "$_f"
  return 1
}

# session Stop 時の cleanup: 自 session の state file を削除し、ついでに TTL 超過分を GC する
# usage: _touchable_cleanup_session <session_id>
_touchable_cleanup_session() {
  local _sid="$1"
  [[ -d "$_TOUCHABLE_STATE_DIR" ]] || return 0
  if [[ -n "$_sid" && "$_sid" != "null" ]]; then
    rm -f "${_TOUCHABLE_STATE_DIR}/touchable-${_sid}.txt" "${_TOUCHABLE_STATE_DIR}/touchable-${_sid}.txt.tmp" 2>/dev/null || true
    rmdir "${_TOUCHABLE_STATE_DIR}/touchable-${_sid}.txt.lock" 2>/dev/null || true
  fi
  find "$_TOUCHABLE_STATE_DIR" -maxdepth 1 -name 'touchable-*.txt' -mmin "+$(( _TOUCHABLE_TTL_SEC / 60 ))" -delete 2>/dev/null || true
  return 0
}
