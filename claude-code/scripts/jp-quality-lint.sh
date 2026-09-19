#!/usr/bin/env bash
# jp-quality hook (pre-tool-use / stop) と同じ辞書・判定関数で既存文書を後追い検査する CLI。
# 判定 logic は lib/jp-quality/ を source して共有する (複製すると hook と判定がずれる)。
# 構造検査は hook と同じ全観点 (連続漢字 / 読点 / 矢印 / 平坦 bullet / 時限 / 括弧詰め)。
# usage: jp-quality-lint.sh [--strict] <file...>   (file 省略時は stdin を検査)
#        --strict は辞書の skill-only key (荒い比喩語) も検査対象に足す。既定 mode は
#        hook と同じ key 集合のままにして、hook と CLI の判定がずれないようにする。
# env:   JP_QUALITY_DICT=<path> で辞書を差し替える (test 用)
# exit:  0=block hit なし / 1=block hit あり / 2=引数・辞書エラー

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/jp-quality/structural-checks.sh
source "${SCRIPT_DIR}/../lib/jp-quality/structural-checks.sh"

[[ -n "${JP_QUALITY_DICT:-}" ]] && _principles_file="${JP_QUALITY_DICT}"

if [[ ! -f "$_principles_file" ]]; then
  printf 'error: 辞書が見つからない: %s\n' "$_principles_file" >&2
  exit 2
fi

# hook の _block_if_ai_jargon と同じ category 集合 (block 13 key + warn 2 key)
_BLOCK_KEYS=(
  "AI定型語" "カタカナ造語禁止" "難読漢語 (block)" "非日常英語 (block)"
  "弱い表現 (block)" "冗長表現 (block)" "AI段取り定型 (block)"
  "ヘッジ濫用 (block)" "過剰丁寧 (block)" "比喩・擬人化 (block)"
  "曖昧な汎用動詞 (block)" "くだけた話し言葉 (block)"
  "非公式専門用語 (block)"
)
_WARN_KEYS=("断定語 (warn-only)" "英語jargon (warn-only)")
# --strict でのみ見る key。hook は口語 chat への誤爆を避けて自動 block しないが、
# 規範自体は chat にも適用されるので、後追い検査では明示的に当てられるようにする
_SKILL_ONLY_KEYS=("荒い比喩語 (skill-only)")
STRICT=0

EXIT_CODE=0

# 無理やりの短縮の検出。語 list では「確認済」と「確認済み」を区別できないため、
# 辞書ではなく本 script 側の regex で見る。hook 共有の lib へは入れない (毎 turn の
# 走査を増やさない。canonical: guidelines/writing/PRINCIPLES.md 「文章生成の不変条件」)
_check_forced_shortening() {
  local text="$1" out=""
  local hits stripped
  # 「〜済」で文を切る形。「済み」「済ませる」等は送り仮名ごと潰してから探すので検出されない
  # 送り仮名付きの活用形と、済を含む正規の熟語を先に潰してから探す
  stripped=$(printf '%s' "$text" | sed -E 's/済[みまむめせ]/@@/g; s/(経済|救済|決済|返済|完済|弁済|共済|済生)/@@/g')
  hits=$(printf '%s' "$stripped" | grep -oE '[一-龥ァ-ヶー]+済' | sort -u | tr '\n' ' ' || true)
  [[ -n "${hits// /}" ]] && out="${out}済で切る省略形: ${hits}; "
  # 「要確認」「要対応」のように 要+漢語 で状態を表す形
  hits=$(printf '%s' "$text" | grep -oE '要(確認|対応|修正|議論|再考|検討)' | sort -u | tr '\n' ' ' || true)
  [[ -n "${hits// /}" ]] && out="${out}要+漢語の省略形: ${hits}; "
  # 連用形否定 (未渡し / 未指定時)
  # 「し」側は「未満しか」等を拾うため、文書化済の例 (未渡し) だけを明示で見る
  hits=$(printf '%s' "$text" | grep -oE '(未[一-龥]{1,3}時|未渡し)' | sort -u | tr '\n' ' ' || true)
  [[ -n "${hits// /}" ]] && out="${out}連用形否定: ${hits}; "
  printf '%s' "${out% }"
}

# hit 語 list (改行区切り) を「語 → 置換候補」併記の 1 行へ整形する
_format_hits() {
  local hits="$1" word sug out=""
  while IFS= read -r word; do
    [[ -z "$word" ]] && continue
    sug=$(_lookup_suggestion "$word")
    out="${out:+${out}, }${word}${sug:+ → ${sug}}"
  done <<< "$hits"
  printf '%s' "$out"
}

_lint_text() {
  local label="$1" text="$2"
  local key hits found=0
  printf '== %s ==\n' "$label"
  for key in "${_BLOCK_KEYS[@]}"; do
    if ! hits=$(_check_term_list "$text" "$key"); then
      printf '[block] %s: %s\n' "$key" "$(_format_hits "$hits")"
      found=1
      EXIT_CODE=1
    fi
  done
  for key in "${_WARN_KEYS[@]}"; do
    if ! hits=$(_check_term_list "$text" "$key"); then
      printf '[warn] %s: %s\n' "$key" "$(_format_hits "$hits")"
      found=1
    fi
  done
  if [[ "$STRICT" -eq 1 ]]; then
    for key in "${_SKILL_ONLY_KEYS[@]}"; do
      if ! hits=$(_check_term_list "$text" "$key"); then
        printf '[strict] %s: %s\n' "$key" "$(_format_hits "$hits")"
        found=1
        EXIT_CODE=1
      fi
    done

    local shortening
    shortening=$(_check_forced_shortening "$text")
    if [[ -n "$shortening" ]]; then
      printf '[strict] 無理やりの短縮: %s\n' "$shortening"
      found=1
      EXIT_CODE=1
    fi
  fi
  # 構造検査は hook (_block_if_ai_jargon) と同じ全観点を見る (100字超文は 2026-08-28 に廃止)
  _check_sentence_structure_counts "$text" 0 1
  local structural
  structural=$(_format_sentence_structure_warn)
  if [[ -n "$structural" ]]; then
    printf '[warn] 構造: %s\n' "$structural"
    found=1
  fi
  [[ $found -eq 0 ]] && printf 'hit なし\n'
  return 0
}

while [[ $# -gt 0 && "$1" == --* ]]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    *) printf 'error: 不明な option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ $# -eq 0 ]]; then
  _lint_text "(stdin)" "$(cat)"
else
  for _f in "$@"; do
    if [[ ! -f "$_f" ]]; then
      printf 'error: file が見つからない: %s\n' "$_f" >&2
      exit 2
    fi
    _lint_text "$_f" "$(cat "$_f")"
  done
fi

exit "$EXIT_CODE"
