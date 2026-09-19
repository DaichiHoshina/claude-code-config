#!/usr/bin/env bash
# code comment の機械判定に使う共通 helper

set -euo pipefail

# 対象外 prefix (機械 marker / example label は文体判定を skip)
_COMMENT_STYLE_SKIP_PREFIX_RE='^(MEMO|TODO|FIXME|NOTE|XXX|HACK|WARN|NB|NG|OK|Bad|Good|例):'

# 拡張子 → comment marker regex
_comment_style_marker_re_for() {
  local _ext="$1"
  case "$_ext" in
    py|rb|sh|bash|zsh|tf|pl|ex|exs)
      printf '%s' '^[[:space:]]*#([^!]|$)' ;;
    sql|lua|hs)
      printf '%s' '^[[:space:]]*--' ;;
    go|ts|tsx|js|jsx|mjs|cjs|rs|java|kt|kts|c|cc|cpp|h|hpp|swift|php|scala|proto|dart)
      printf '%s' '^[[:space:]]*(//|/\*)' ;;
    *)
      return 1 ;;
  esac
}

# 拡張子ごとに marker 定義が違うため、既存の _comment_style_marker_re_for を再利用して抽出する
_extract_comment_body_text() {
  local _file="$1"
  local _content="$2"
  local _ext="${_file##*.}"
  local _marker_re
  if ! _marker_re="$(_comment_style_marker_re_for "$_ext")"; then
    return 1
  fi
  local _out="" _line _body
  while IFS= read -r _line; do
    grep -qE "$_marker_re" <<< "$_line" || continue
    _body="$(_comment_style_strip_marker "$_line")"
    [[ -z "$_body" ]] && continue
    _out="${_out}${_body}"$'\n'
  done <<< "$_content"
  printf '%s' "$_out"
  return 0
}

# comment marker を取り除いて本文だけ返す
_comment_style_strip_marker() {
  local _line="$1"
  local _body="$_line"
  # 先頭 whitespace 除去
  _body="${_body#"${_body%%[![:space:]]*}"}"
  # marker prefix 除去 (bash 変数展開で対応可能な単純 pattern のみ)
  case "$_body" in
    '//'*) _body="${_body#//}" ;;
    '/*'*) _body="${_body#/\*}"; _body="${_body%\*/}" ;;
    '#'*) _body="${_body#\#}" ;;
    '--'*) _body="${_body#--}" ;;
  esac
  # 先頭 whitespace 再除去
  _body="${_body#"${_body%%[![:space:]]*}"}"
  # 末尾 whitespace 除去
  _body="${_body%"${_body##*[![:space:]]}"}"
  # 末尾記号 (。 . ! ? , 、 : ;) を判定用に除去
  while :; do
    case "$_body" in
      *[.。!?、,:\;]) _body="${_body%?}" ;;
      *) break ;;
    esac
    _body="${_body%"${_body##*[![:space:]]}"}"
  done
  printf '%s' "$_body"
}

# 日本語 (非 ASCII) を含むか判定
_comment_style_has_japanese() {
  local _text="$1"
  # 非 ASCII byte を含めば日本語ありとみなす (URL / 識別子は ASCII のみのため誤爆しない)
  LC_ALL=C printf '%s' "$_text" | LC_ALL=C grep -q '[^ -~]' 2>/dev/null
}

# Write は content が全文なので、disk の既存 file と diff して新規行だけに限定する。
# file 未存在は全体を新規行扱い、既存 file の読込失敗は 1 を返し呼び出し側に block を見送らせる
run_comment_style_new_lines_for_write() {
  local _file="$1"
  local _new_content="$2"
  if [[ ! -e "$_file" ]]; then
    printf '%s' "$_new_content"
    return 0
  fi
  local _old_content
  if ! _old_content="$(cat "$_file" 2>/dev/null)"; then
    return 1
  fi
  diff <(printf '%s\n' "$_old_content") <(printf '%s\n' "$_new_content") 2>/dev/null \
    | grep '^> ' | sed 's/^> //' || true
  return 0
}

# linter 制御 directive (機械向け comment) は quantity gate の対象外にする
_COMMENT_QUANTITY_DIRECTIVE_RE='(nolint|eslint-disable|eslint-enable|shellcheck (disable|source|enable)|noqa|prettier-ignore|@ts-ignore|@ts-expect-error|SPDX-License-Identifier|Copyright \(c\)|Copyright ©)'

# quantity gate の対象外行か判定する (対象外=0 / 対象=1)。skip prefix / directive / 英語のみ行を除く
_comment_quantity_is_excluded_line() {
  local _body="$1"
  [[ "$_body" =~ $_COMMENT_STYLE_SKIP_PREFIX_RE ]] && return 0
  [[ "$_body" =~ $_COMMENT_QUANTITY_DIRECTIVE_RE ]] && return 0
  if ! _comment_style_has_japanese "$_body"; then
    return 0
  fi
  return 1
}

# 新規行に限定済みの content から、quantity gate 対象の日本語 comment 行数を数える
run_comment_quantity_count() {
  local _file="$1"
  local _content="$2"
  [[ -z "$_file" || -z "$_content" ]] && { printf '0'; return 0; }
  local _comment_text
  if ! _comment_text="$(_extract_comment_body_text "$_file" "$_content")"; then
    printf '0'
    return 0
  fi
  local _count=0 _line
  while IFS= read -r _line; do
    [[ -z "$_line" ]] && continue
    _comment_quantity_is_excluded_line "$_line" && continue
    _count=$((_count + 1))
  done <<< "$_comment_text"
  printf '%d' "$_count"
}

# comment 量 gate: 行数上限は撤廃 (2026-07-22)。呼び出し側互換のため関数は保持する no-op。
# 品質判定は code-comment.md の「default 書かない / Why not のみ」に一本化する
run_comment_quantity_gate_check() {
  return 0
}
