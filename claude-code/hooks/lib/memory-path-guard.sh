#!/usr/bin/env bash
# memory-path guard checkers (extracted from pre-tool-use.sh)
# 多重 source 防止
if [[ "${_MEMORY_PATH_GUARD_LOADED:-}" == "1" ]]; then
    return 0
fi
_MEMORY_PATH_GUARD_LOADED=1

# ====================================
# .serena/memories/ 書き込み block
# Serena の .serena/memories/ は CLAUDE.md 「Compounding Engineering」 / references/compounding-engineering-cycle.md で禁止。
# write 先は scripts/memory-save-helper.sh resolve-dir が返す dir (org repo は org memory、他は <repo-root>/memory/)。
# 引数: file_path (Write/Edit/MultiEdit の tool_input.file_path)
# 副作用: 該当 path なら GUARD_CLASS=Forbidden をセットして exit 2 相当の block を発生させる
# ====================================
_check_serena_memory_path() {
  local file_path="$1"
  [[ -z "$file_path" ]] && return 0

  # .serena/memories/ パターンに match する path を block
  # 絶対 path / 相対 path 両対応 (先頭に任意 prefix を許容)
  local re='\.serena/memories/'
  if [[ "$file_path" =~ $re ]]; then
    # 自己除外: 規約説明 file 自体は allowlist
    # (hook-utils.sh の _is_aitools_path / _aitools_relpath を使って相対 path 取得)
    local rel_path
    if _is_aitools_path "$file_path"; then
      rel_path=$(_aitools_relpath "$file_path")
      case "$rel_path" in
        claude-code/CLAUDE.global.md|\
        claude-code/rules/*|\
        claude-code/hooks/pre-tool-use.sh|\
        claude-code/hooks/lib/memory-path-guard.sh|\
        claude-code/references/compounding-engineering-cycle.md)
          return 0
          ;;
      esac
    fi

    GUARD_CLASS="Forbidden"
    MESSAGE="${ICON_CRITICAL} .serena/memories/ への書き込みは禁止"
    ADDITIONAL_CONTEXT=".serena/memories/ への書き込みは禁止です (CLAUDE.md 「Compounding Engineering」 / references/compounding-engineering-cycle.md 「Memory write target」)。
write 先は \`bash ~/.claude/scripts/memory-save-helper.sh resolve-dir\` の出力 dir (org repo は org memory、他は <repo-root>/memory/) です。~/.claude/projects/*/memory/ (auto-memory) は 2026-06-26 に廃止済みで、こちらも block されます。
ログ: ~/.claude/logs/serena-memory-block.log"
    printf '[serena-memory-block] file=%s\n' "$file_path" >&2
    _append_block_log "${HOME}/.claude/logs/serena-memory-block.log" "$TOOL_NAME" ".serena/memories/" "$file_path"
  fi
}

# ====================================
# ~/.claude/projects/*/memory/ (auto-memory) 書き込み block
# auto-memory は 2026-06-26 に全 project で廃止。write 先は memory-save-helper.sh resolve-dir の出力
# (org repo は org memory、他は <repo-root>/memory/)。system prompt default がこの path を指示するので hook で止める。
# 2026-08-28 に ai-tools 系 dir 限定から全 project へ拡張した (org 作業用 dir に 7/14〜8/21 の 51 file が検出されていなかった)。
# 引数: file_path (Write/Edit/MultiEdit の tool_input.file_path)
# 副作用: 該当 path なら GUARD_CLASS=Forbidden をセットして exit 2 相当の block を発生させる
# ====================================
_check_legacy_auto_memory_path() {
  local file_path="$1"
  [[ -z "$file_path" ]] && return 0

  # ~/.claude/projects/<任意 project>/memory/ への write を block
  # POSIX bash [[ =~ ]] 互換 regex、HOME 展開済み path で比較
  local re="^${HOME}/\\.claude/projects/[^/]+/memory/"
  if [[ "$file_path" =~ $re ]]; then
    # allowlist: .trash- プレフィックスの dir 内は除外 (migration 中の安全策)
    if [[ "$file_path" =~ /memory/\.trash- ]]; then
      return 0
    fi

    GUARD_CLASS="Forbidden"
    MESSAGE="${ICON_CRITICAL} legacy memory path への書き込みは禁止"
    ADDITIONAL_CONTEXT="[block] memory write to legacy path: ${file_path}
        ~/.claude/projects/*/memory/ (auto-memory) は 2026-06-26 に廃止済み (CLAUDE.md 「Compounding Engineering」)
        正しい path: \`bash ~/.claude/scripts/memory-save-helper.sh resolve-dir\` の出力 dir + /<filename> (org repo は org memory、他は <repo-root>/memory/)
        log: ~/.claude/logs/legacy-memory-path-block.log"
    printf '[legacy-memory-block] tool=%s file=%s\n' "$TOOL_NAME" "$file_path" >&2
    _append_block_log "${HOME}/.claude/logs/legacy-memory-path-block.log" "$TOOL_NAME" "legacy-memory-path" "$file_path"
  fi
}
