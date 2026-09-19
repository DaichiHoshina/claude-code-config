#!/usr/bin/env bash
# WorktreeRemove Hook
# 役割:
#   1. worktree 削除後に ~/.claude/projects/<sanitized> を掃除する
#   2. dangling cwd 問題の warn を systemMessage で Claude に通知し
#      cd <CLAUDE_PROJECT_DIR> を促す
#      (Claude Code spec: hook stdout は systemMessage として Claude に注入される)
# 安全策: wt パス形式 (/private/tmp/wt-* / *-wt-* / <ghq-root>/worktrees/*) かつ memory 空 (or symlink) の場合のみ削除

set -euo pipefail
trap '' PIPE
exec 2>>"$HOME/.claude/logs/hook-errors.log"

LOG="$HOME/.claude/logs/worktree-cleanup.log"
mkdir -p "$(dirname "$LOG")"

# jq 必須（hook-utils.sh 非依存のため inline check）
if ! command -v jq &>/dev/null; then
  echo '{"error": "jq not installed. Please run: brew install jq (macOS) / apt install jq (Ubuntu)"}' >&2
  exit 1
fi

INPUT=$(cat)
WT_PATH=$(jq -r '.worktree_path // .cwd // .workspace.current_dir // empty' <<< "$INPUT")

# WT_PATH が空の場合でも dangling cwd warn は発行する
if [[ -z "$WT_PATH" ]]; then
  # worktree_path が取れない場合: warn のみ出力して終了
  _PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$HOME}"
  printf '%s [worktree-remove] worktree_path empty; cwd may be dangling. cwd reset to: %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$_PROJECT_ROOT" >> "$LOG"
  jq -n --arg msg "[WorktreeRemove] Worktree was removed. Your working directory may be dangling. Run: cd ${_PROJECT_ROOT}" \
    '{systemMessage: $msg}'
  exit 0
fi

# wt パターン以外は掃除対象外だが warn は発行する
case "$WT_PATH" in
  */wt-*|*-wt-*|*/ghq/worktrees/*)
    _IS_WT=1
    ;;
  *)
    _IS_WT=0
    ;;
esac

# dangling cwd warn を出力 (常に)
_PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$HOME}"
printf '%s [worktree-remove] removed: %s -> cd to: %s\n' \
  "$(date '+%Y-%m-%d %H:%M:%S')" "$WT_PATH" "$_PROJECT_ROOT" >> "$LOG"

# --- ~/.claude/projects/<sanitized> の掃除 (wt パターンのみ) ---
if [[ "$_IS_WT" = "1" ]]; then
  SANITIZED="${WT_PATH//\//-}"
  PROJECT_DIR="$HOME/.claude/projects/${SANITIZED}"

  if [[ -d "$PROJECT_DIR" ]]; then
    _jsonl_files=( "$PROJECT_DIR"/*.jsonl )
    [[ -e "${_jsonl_files[0]}" ]] && JSONL_COUNT=${#_jsonl_files[@]} || JSONL_COUNT=0
    _mem_files=( "$PROJECT_DIR/memory"/*.md )
    [[ -e "${_mem_files[0]}" ]] && MEM_REAL=${#_mem_files[@]} || MEM_REAL=0

    if [[ "$JSONL_COUNT" = "0" && "$MEM_REAL" = "0" ]]; then
      if [[ -L "$PROJECT_DIR/memory" ]]; then
        rm "$PROJECT_DIR/memory"
      fi
      rmdir "$PROJECT_DIR/memory" 2>/dev/null || true
      if rmdir "$PROJECT_DIR" 2>/dev/null; then
        printf '%s [worktree-remove] cleaned project dir: %s\n' \
          "$(date '+%Y-%m-%d %H:%M:%S')" "$PROJECT_DIR" >> "$LOG"
      fi
    fi
  fi
fi

# --- ~/.serena/serena_config.yml の projects 掃除 ---
# 実体が消えた entry のみ削除する。dir が残存していれば触らないので、
# 削除以外の理由で並走 Serena が書き足した entry を対象に含めない
SERENA_CONFIG="$HOME/.serena/serena_config.yml"
if [[ -f "$SERENA_CONFIG" ]]; then
  _tmp=$(mktemp "${TMPDIR:-/tmp}/serena_config.XXXXXX")
  _removed=0
  _in_projects=0
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    if [[ "$_line" == "projects:"* ]]; then
      _in_projects=1
    elif [[ "$_in_projects" = "1" ]]; then
      if [[ "$_line" == "- /"* ]]; then
        _p="${_line#- }"
        if [[ ! -d "$_p" ]]; then
          _removed=$((_removed + 1))
          printf '%s [worktree-remove] unregistered stale serena project: %s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$_p" >> "$LOG"
          continue
        fi
      elif [[ "$_line" != "- "* && -n "${_line//[[:space:]]/}" ]]; then
        _in_projects=0
      fi
    fi
    printf '%s\n' "$_line" >> "$_tmp"
  done < "$SERENA_CONFIG"

  if [[ "$_removed" -gt 0 ]]; then
    cp "$SERENA_CONFIG" "${SERENA_CONFIG}.bak"
    mv "$_tmp" "$SERENA_CONFIG"
    printf '%s [worktree-remove] serena projects pruned: %s entries (backup: %s.bak)\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$_removed" "$SERENA_CONFIG" >> "$LOG"
  else
    rm -f "$_tmp"
  fi
fi

# systemMessage で Claude に cwd reset を促す
jq -n --arg wt "$WT_PATH" --arg root "$_PROJECT_ROOT" \
  '{systemMessage: ("Worktree removed: " + $wt + ". Your cwd may be dangling. Run: cd " + $root)}'

exit 0
