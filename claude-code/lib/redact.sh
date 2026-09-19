#!/usr/bin/env bash
# stdin の private term を [REDACTED] に置換する。term list が空なら素通しする

redact_private_terms() {
  local term_file="${PRIVATE_TERM_FILE:-${HOME}/.claude/references-private/private-name-list.txt}"
  local sed_args=() term
  if [[ -s "${term_file}" ]]; then
    while IFS= read -r term; do
      [[ -n "${term}" ]] || continue
      # term は literal 扱いにする。regex メタ文字や区切り文字 | が入ると
      # 広範囲マッチや sed 構文エラーになるため BRE 特殊文字を全て escape する
      term="$(printf '%s' "${term}" | sed -e 's/[].[^$*\/|&]/\\&/g')"
      sed_args+=(-e "s|${term}|[REDACTED]|g")
    done < "${term_file}"
  fi
  if [[ ${#sed_args[@]} -gt 0 ]]; then sed "${sed_args[@]}"; else cat; fi
}
