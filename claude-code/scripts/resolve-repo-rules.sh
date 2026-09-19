#!/usr/bin/env bash
# 変更 file に glob が当たる repo rule の絶対 path を stdout へ 1 行 1 件で出す。
# ai-tools 本体に特定 repo の dir 構造と frontmatter key を含めないための解決層。
# 宣言は manifest 側にあり、本 script も呼び出し元の command も repo 名を知らない。
#
# manifest: $CLAUDE_REPO_RULES_MANIFEST (既定 ~/.claude/references-private/repo-rules.json)
# usage: resolve-repo-rules.sh <changed-file>...   (path は repo root 相対でも絶対でもよい)
#        resolve-repo-rules.sh --review-docs        (repo が宣言する review 定義 file を出す)
# exit:  0=解決した (0 件でも 0) / 3=manifest 不在または対象 repo 節なしで skip
set -euo pipefail

mode=changed
get_key=""
if [ "${1:-}" = "--review-docs" ]; then mode=review_docs; shift; fi
if [ "${1:-}" = "--get" ]; then mode=get; get_key="${2:-}"; shift 2 || true; fi

MANIFEST="${CLAUDE_REPO_RULES_MANIFEST:-${HOME}/.claude/references-private/repo-rules.json}"
[ -f "$MANIFEST" ] || exit 3
command -v jq >/dev/null 2>&1 || exit 3

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 3

# glob を ERE へ変換する。`**/` は 0 段以上の dir、`*` は / を含まない
glob_to_regex() {
    local g="$1" out="" i=0 c len=${#1}
    while [ "$i" -lt "$len" ]; do
        c="${g:$i:1}"
        if [ "$c" = "*" ]; then
            if [ "${g:$i:3}" = "**/" ]; then out+="(.*/)?"; i=$((i + 3)); continue; fi
            if [ "${g:$i:2}" = "**" ]; then out+=".*"; i=$((i + 2)); continue; fi
            out+="[^/]*"; i=$((i + 1)); continue
        fi
        case "$c" in
            '?') out+="[^/]" ;;
            '.' | '+' | '(' | ')' | '[' | ']' | '{' | '}' | '^' | '$' | '|' | '\\') out+="\\$c" ;;
            *) out+="$c" ;;
        esac
        i=$((i + 1))
    done
    printf '^%s$' "$out"
}

# rule file の frontmatter から glob を取り出す。exit 1 = frontmatter が無い
extract_globs() {
    awk -v key="$2" '
        NR == 1 && $0 != "---" { exit 1 }
        NR == 1 { next }
        $0 == "---" { exit 0 }
        $0 ~ "^" key ":" {
            rest = substr($0, length(key) + 2)
            gsub(/^[ \t]+|[ \t]+$/, "", rest)
            gsub(/^["'"'"']|["'"'"']$/, "", rest)
            if (rest != "") { print rest; inlist = 0 } else { inlist = 1 }
            next
        }
        inlist && $0 ~ /^[ \t]*-[ \t]*/ {
            v = $0
            sub(/^[ \t]*-[ \t]*/, "", v)
            gsub(/^["'"'"']|["'"'"']$/, "", v)
            print v
            next
        }
        inlist && $0 ~ /^[^ \t-]/ { inlist = 0 }
    ' "$1"
}

# 節の選択は両 mode で共通なので、先に repo 節を決める
select_section() {
    local pat
    while IFS= read -r pat; do
        [ -n "$pat" ] || continue
        # shellcheck disable=SC2053
        if [[ "$repo_root" == $pat ]]; then printf '%s' "$pat"; return 0; fi
    done < <(jq -r '.repos[]?.path_prefix // empty' "$MANIFEST")
    return 1
}

if [ "$mode" = "get" ]; then
    [ -n "$get_key" ] || exit 3
    section=$(select_section) || exit 3
    val=$(jq -r --arg p "$section" --arg k "$get_key" \
        '.repos[] | select(.path_prefix == $p) | getpath($k | split(".")) // empty' "$MANIFEST" 2>/dev/null) || exit 3
    [ -n "$val" ] || exit 3
    printf '%s\n' "$val"
    exit 0
fi

if [ "$mode" = "review_docs" ]; then
    section=$(select_section) || exit 3
    # 候補 group ごとに、実在する最初の 1 件だけを出す (正本を先、生成物を後に宣言する)
    while IFS= read -r group; do
        [ -n "$group" ] || continue
        while IFS= read -r cand; do
            [ -n "$cand" ] || continue
            if [ -f "$repo_root/$cand" ]; then printf '%s\n' "$repo_root/$cand"; break; fi
        done < <(printf '%s' "$group" | jq -r '.[]?')
    done < <(jq -c --arg p "$section" \
        '.repos[] | select(.path_prefix == $p) | .review_docs[]?' "$MANIFEST")
    exit 0
fi

# 変更 file を repo root 相対へ合わせる
changed=()
for f in "$@"; do
    case "$f" in
        "$repo_root"/*) changed+=("${f#"$repo_root"/}") ;;
        /*) continue ;;
        *) changed+=("$f") ;;
    esac
done
[ ${#changed[@]} -gt 0 ] || exit 0

# repo root に path_prefix glob が当たる節を採用する
section=$(select_section) || exit 3

# sources を宣言順に見て、実在する最初の dir を採る (正本が先、生成物が fallback)
rules_dir=""
glob_key=""
while IFS=$'\t' read -r d k; do
    [ -n "$d" ] || continue
    if [ -d "$repo_root/$d" ]; then rules_dir="$repo_root/$d"; glob_key="$k"; break; fi
done < <(jq -r --arg p "$section" \
    '.repos[] | select(.path_prefix == $p) | .sources[]? | [.dir, (.glob_key // "paths")] | @tsv' \
    "$MANIFEST")
[ -n "$rules_dir" ] || exit 3

shopt -s nullglob
for rule in "$rules_dir"/*.md; do
    globs=$(extract_globs "$rule" "$glob_key") || { printf '%s\n' "$rule"; continue; }
    if [ -z "$globs" ]; then printf '%s\n' "$rule"; continue; fi
    while IFS= read -r g; do
        [ -n "$g" ] || continue
        if [ "$g" = "**/*" ] || [ "$g" = "**" ]; then printf '%s\n' "$rule"; break; fi
        re=$(glob_to_regex "$g")
        for f in "${changed[@]}"; do
            if [[ "$f" =~ $re ]]; then printf '%s\n' "$rule"; break 2; fi
        done
    done <<< "$globs"
done
