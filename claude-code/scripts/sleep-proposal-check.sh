#!/usr/bin/env bash
# Usage: sleep-proposal-check.sh <proposal-file> [--repo <path>] [--digest <path>]
# proposal の schema を機械検証する。exit: 0=valid / 1=violation / 2=usage / 3=NO-PROPOSAL
# --digest 指定時は Evidence の逐語引用行 (>) を digest へ literal 照合する。未指定 caller は従来挙動
set -euo pipefail

FILE=""
REPO=""
DIGEST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --digest) DIGEST="$2"; shift 2 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) FILE="$1"; shift ;;
  esac
done
[[ -n "${FILE}" && -f "${FILE}" ]] || { echo "ERROR: proposal file を指定する" >&2; exit 2; }
[[ -z "${DIGEST}" || -f "${DIGEST}" ]] || { echo "ERROR: --digest file が存在しない: ${DIGEST}" >&2; exit 2; }
[[ -n "${REPO}" ]] || REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

MAX_PROPOSALS=5
MAX_LINES=200
ERRORS=0
_ng() { echo "NG: $*" >&2; ERRORS=1; }

if grep -q '^NO-PROPOSAL:' "${FILE}"; then
  echo "NO-PROPOSAL: $(grep '^NO-PROPOSAL:' "${FILE}" | head -1)"
  exit 3
fi

lines=$(wc -l < "${FILE}" | tr -d ' ')
[[ "${lines}" -le "${MAX_LINES}" ]] || _ng "file が ${MAX_LINES} 行を超える (${lines} 行)"

starts=$(grep -n '^### P[0-9][0-9]*:' "${FILE}" | cut -d: -f1 || true)
count=0
[[ -n "${starts}" ]] && count=$(wc -l <<< "${starts}" | tr -d ' ')
if [[ "${count}" -eq 0 ]]; then
  _ng "proposal block (### P<n>:) が 1 つもない (NO-PROPOSAL 行もない)"
elif [[ "${count}" -gt "${MAX_PROPOSALS}" ]]; then
  _ng "proposal が ${MAX_PROPOSALS} 件を超える (${count} 件)"
fi

term_file="${PRIVATE_TERM_FILE:-${HOME}/.claude/references-private/private-name-list.txt}"
if [[ -s "${term_file}" ]]; then
  while IFS= read -r term; do
    [[ -n "${term}" ]] || continue
    if grep -qF "${term}" "${FILE}"; then
      _ng "private term を含む (public repo guard)"
      break
    fi
  done < "${term_file}"
fi

idx=0
prev_start=""
_check_block() {
  local s="$1" e="$2" block type target _targets id q has_quote=0
  block=$(sed -n "${s},${e}p" "${FILE}")
  # NG に P id を含め、呼び出し元が違反 proposal 単位で分離できるようにする
  id=$(sed -n "${s}p" "${FILE}" | grep -oE 'P[0-9]+' | head -1)
  grep -Eq '^- Type: (new-skill|skill-edit|claude-md|hook|command|cursor|remove)$' <<< "${block}" \
    || _ng "block ${id} L${s}: Type が enum (new-skill|skill-edit|claude-md|hook|command|cursor|remove) にない"
  target=$(sed -n 's/^- Target: //p' <<< "${block}" | head -1)
  [[ -n "${target}" ]] || _ng "block ${id} L${s}: Target がない"
  grep -Eq '^- Evidence: .*[0-9]' <<< "${block}" \
    || _ng "block ${id} L${s}: Evidence がないか数値引用を含まない"
  grep -q '^- Change: ' <<< "${block}" || _ng "block ${id} L${s}: Change がない"
  grep -q '^- Risk: ' <<< "${block}" || _ng "block ${id} L${s}: Risk がない"
  if [[ -n "${DIGEST}" ]]; then
    while IFS= read -r q; do
      q="${q#"${q%%[![:space:]]*}"}"
      [[ "${q}" == ">"* ]] || continue
      q="${q#>}"
      q="${q#"${q%%[![:space:]]*}"}"
      q="${q%"${q##*[![:space:]]}"}"
      [[ -n "${q}" ]] || continue
      has_quote=1
      grep -qF -- "${q}" "${DIGEST}" \
        || _ng "block ${id} L${s}: evidence-quote-not-in-digest: 引用が digest に一致しない: ${q}"
    done <<< "${block}"
    [[ "${has_quote}" -eq 1 ]] \
      || _ng "block ${id} L${s}: evidence-quote-missing: digest 逐語引用行 (>) が Evidence にない"
  fi
  type=$(sed -n 's/^- Type: //p' <<< "${block}" | head -1)
  case "${type}" in
    skill-edit|hook|command|remove)
      local one tpath _prefix=""
      IFS=',' read -ra _targets <<< "${target}"
      for one in "${_targets[@]}"; do
        one="${one#"${one%%[![:space:]]*}"}"
        one="${one%"${one##*[![:space:]]}"}"
        [[ -n "${one}" ]] || continue
        # dir 区切りを含まない 2 個目以降は直前 path の上位 dir を補って解決する
        # (maker が同一 dir 配下の path を「a/b/c, d, e」と省略記法で書くため)。
        # 上位 dir は「dir 区切りを含む要素」からのみ更新する (先頭 bare 名で自身を prefix 化しない)
        if [[ "${one}" == */* ]]; then
          _prefix="${one%/*}"
        elif [[ -n "${_prefix}" ]]; then
          one="${_prefix}/${one}"
        fi
        tpath="${REPO}/${one}"
        [[ "${one}" == /* ]] && tpath="${one}"
        [[ -e "${tpath}" ]] || _ng "block ${id} L${s}: Target が実在しない: ${one}"
      done
      ;;
  esac
}

if [[ -n "${starts}" ]]; then
  while IFS= read -r line_no; do
    if [[ -n "${prev_start}" ]]; then
      _check_block "${prev_start}" "$((line_no - 1))"
    fi
    prev_start="${line_no}"
    idx=$((idx + 1))
  done <<< "${starts}"
  _check_block "${prev_start}" "${lines}"
fi

if [[ "${ERRORS}" -ne 0 ]]; then
  exit 1
fi
echo "OK: ${count} proposals valid"
