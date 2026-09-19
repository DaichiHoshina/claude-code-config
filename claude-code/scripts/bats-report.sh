#!/usr/bin/env bash
# bats の結果 3 点 (plan / not ok 件数 / 実 exit code) を必ず末尾に出す wrapper。
# 素の bats をパイプで包むと $? が下流 command のものに置き換わり、打ち切りや fail を
# 「全 pass」と誤読する事故が同日 2 回起きたため (2026-08-23)、要約を script 側で完結させる。
#
# usage:
#   bats-report.sh <path>...        # 指定 path (file / dir) を実行
#   bats-report.sh --changed        # git 変更 file から対象 bats を逆引きして実行
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

resolve_changed_targets() {
  local -a changed=() targets=()
  local f stem hit
  while IFS= read -r f; do
    [[ -n "$f" ]] && changed+=("$f")
  done < <(
    {
      git diff --name-only HEAD
      git diff --name-only --cached
      git ls-files --others --exclude-standard
      git diff --name-only main...HEAD 2>/dev/null
    } | sed 's|^claude-code/||' | sort -u
  )
  for f in "${changed[@]}"; do
    case "$f" in
      tests/*.bats|tests/**/*.bats)
        [[ -f "$f" ]] && targets+=("$f")
        continue
        ;;
    esac
    stem="${f##*/}"
    stem="${stem%.*}"
    # 2 文字以下の stem は無関係 file を大量に含めるため逆引き対象にしない
    (( ${#stem} < 3 )) && continue
    while IFS= read -r hit; do
      [[ -n "$hit" ]] && targets+=("$hit")
    done < <(find tests -name "*${stem}*.bats" 2>/dev/null)
  done
  printf '%s\n' "${targets[@]-}" | sort -u | sed '/^$/d'
}

declare -a targets=()
if [[ "${1:-}" == "--changed" ]]; then
  while IFS= read -r t; do
    [[ -n "$t" ]] && targets+=("$t")
  done < <(resolve_changed_targets)
  if (( ${#targets[@]} == 0 )); then
    echo "bats-report: 変更 file に対応する bats が見つからない (全 suite は npm run test:bats)"
    exit 0
  fi
  echo "bats-report: 対象 ${#targets[@]} file (変更 file から逆引き)"
  printf '  %s\n' "${targets[@]}"
elif (( $# >= 1 )); then
  targets=("$@")
else
  echo "usage: bats-report.sh <path>... | --changed" >&2
  exit 2
fi

out=$(mktemp)
trap 'rm -f "$out"' EXIT

bats -r "${targets[@]}" >"$out" 2>&1
ec=$?

cat "$out"
notok=$(grep -c '^not ok' "$out")
echo "---- bats-report summary ----"
echo "plan: $(grep -m5 '^1\.\.' "$out" | tr '\n' ' ')"
echo "not ok: ${notok}"
echo "exit code: ${ec}"
exit "$ec"
