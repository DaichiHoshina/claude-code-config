---
paths:
  - "**/*.sh"
---
# Shell Script Rules

## Required

- set -euo pipefail
- shellcheck compliant
- Variables quoted as `"${var}"`

## Prohibited

- eval forbidden (例外: jq `@sh` で quote した出力を受ける `eval "$(jq -r '@sh ...')"` の fork 削減 idiom のみ許可)
- rm -rf / forbidden
- Undefined variable references forbidden

## Recommended

- Refactor into functions for reuse
- Error messages to >&2
- Return appropriate exit codes

## 失敗パターンカタログ

hooks/ の bash 編集で繰り返し踏む誤りやすい点を 10 件まとめる。shellcheck が検出できる項目も多いが、warn を無視する前にこの表で正しい一手を確認する。

| 症状 | ありがちな誤り | 正しい一手 |
|---|---|---|
| quote の付け忘れによる word splitting | `rm $file` と quote なしで展開し、space 入り path で分裂する | 常に `"${file}"` と quote する (shellcheck SC2086) |
| set -e が pipeline で適用されない | `cmd \| grep x` の cmd 失敗を検知できると思い込む | `set -o pipefail` を併用し、条件は明示的に `if ! cmd; then` で書く |
| pipe while で変数代入が消える | `cmd \| while read -r l; do n=$((n+1)); done` の n が subshell 内で消える | `while read -r l; do ...; done < <(cmd)` と process substitution にする |
| [ と [[ の挙動差で誤判定 | `[ $a == b* ]` で pattern match や `&&` を期待する | bash 専用 script では `[[ ]]` を使い、pattern / regex / `&&` は `[[ ]]` 内で書く |
| local var=$(cmd) で $? が消える | `local out=$(cmd); [ $? -ne 0 ]` が常に 0 になる (local の戻り値を見ている) | `local out; out=$(cmd)` と宣言と代入を分ける (SC2155) |
| glob 0 hit で pattern が生のまま残存する | `for f in *.log; do rm "$f"; done` が hit 0 件で `*.log` を処理する | `shopt -s nullglob` を設定するか、loop 内で `[[ -e "$f" ]] || continue` する |
| IFS の一時変更が持続して後続が壊れる | `IFS=,` を戻し忘れて以降の word splitting が変わる | `IFS=, read -r a b <<< "$line"` と command 単位で局所化する |
| trap EXIT が多重上書きで前の cleanup を消す | 後から `trap '...' EXIT` を追加して既存 handler を上書きする | 1 script 1 handler に集約するか、`trap -p EXIT` で既存を取り込んで連結する |
| $(cmd) の末尾改行削除に依存して壊れる | 改行終端の有無を command substitution が保つと思い込む | 末尾改行が意味のある data は file / process substitution で受け、比較は `printf` で正規化する |
| 未定義変数で `rm -rf "$VAR/"` が `/` を消す | `set -u` なしで typo した変数を展開する | `set -u` を必須にし、削除系は `rm -rf "${VAR:?VAR is empty}/"` で guard する |
| set -e 下で `((n++))` が初回に script を終了させる | post-increment が n=0 で 0 を返し exit 1 になる (SC2219 では検出されない) | counter は `n=$((n+1))` か prefix `((++n))` で書く |
| set -e 下で `saved=$(shopt -p <opt>)` が無言で script を止める | `shopt -p` の exit code は option の有効・無効を表し、off なら 1 を返す。状態の保存のつもりが停止条件になる | `saved=$(shopt -p <opt> \|\| true)` と書き、復元は `eval "$saved"` |
| `[[ =~ ]]` の literal regex が silent に壊れる | shell quoting が pattern を別物に変え capture が常に空になる (見た目は動作する) | `re="..."; [[ $str =~ $re ]]` と変数経由で渡す。検出: `grep -rEn "=~ ['\"]"` |
| `find -printf` が macOS で空出力 | GNU 拡張を BSD find が error なしで無視する | `-exec basename {} \;` か `-print` で書く。count は bash glob (`files=(*.md); ${#files[@]}`) が fork 0 で最適 |
| awk のマルチバイト RS / 否定クラスが誤動作 | BSD awk は `RS="。"` で分割せず、`[^」]` も byte 単位解釈で日本語 match が途切れる | `sed 's/。/\'$'\n''/g'` で行化してから行処理し、括弧対応は regex でなく `index()` で判定する |
| timestamp filter が常に true | epoch の単位 (s / ms) を確認せず `now` と比較する | `head -1 \| jq '.<field>'` で桁数を確認してから式を記述する (10 桁 = s / 13 桁 = ms、ms は `(now - X) * 1000` で単位を合わせる) |
| symlink 配置 script の path 解決 bug を見逃す | target 直実行で検証し `BASH_SOURCE` の解決経路差を踏まない | 検証は必ず symlink 経由 (`.git/hooks/pre-push` 等) で実行し、`readlink` loop で絶対 path に解決する |
| 新規 .sh が配置先で Permission denied | Write tool default の 644 のまま commit する | 作成直後に `chmod +x`、`git ls-files --stage` で 100755 を確認して commit する |
| bash 4+ 記法が macOS で無言失敗する | `${args[-1]}` (負 index) や `readarray` を `#!/bin/bash` (= macOS では 3.2) で使う | bash 4+ 記法を記述する前に実行環境の version を確認し、末尾要素は `${args[$((${#args[@]} - 1))]}` 形式で記述する |
| IFS temp 代入が process substitution 内 func の read に leak する (非決定的) | `IFS=$'\t' read ... < <(func)` と書き、func 内部の別 read (default IFS 前提) が壊れる | `out="$(func)"` で先に capture し `IFS=... read ... <<< "$out"` (here-string) にする |
| `claude -p` の prompt が空になり exit 1 | 可変長 flag の直後に prompt を positional で置き、prompt が flag の値として食われる (`--add-dir` / `--allowedTools` / `--disallowedTools` / `--betas` / `--file` / `--mcp-config` / `--tools` が該当) | prompt は stdin で渡す (`printf '%s' "${PROMPT}" \| claude -p --disallowedTools "Task"`) |
| 日本語の動詞を sed で語幹だけ置換すると活用語尾の処理を失敗する | `s/切り出し/分離/` が「切り出した」を「分離た」にする | 活用形ごとに置換先を記載し (`切り出した → 分離した`)、置換後に `grep -rn "<置換先>[たてなまさ]"` で欠落を数えてから commit する |

補足:
- `shopt -p` 罠は hook のように fail-close で exit 0 に見える経路では、出力が 1 文字も出ない形で現れる (2026-09-14 実踏)
- `claude -p` 罠は無人実行では log の中で見つけにくいので、stub で argv を記録する test も併せて書く

## Claude Code Bash tool 環境

- Bash tool は `.zshrc` でなく `~/.claude/shell-snapshots/` の snapshot を source する。rc 編集は現行 session に反映されない (即時反映するには現行 snapshot にも同修正を入れる)
- script 内の非対話 / Claude 判定は `CLAUDECODE` 環境変数で行う (interactive / tty 判定はどちらも該当しない)
- zsh の echo は single quote 内でも `\n` を実改行に展開する。hook への JSON 入力は `printf '%s' '<json>' | hook.sh` で渡す (echo だと JSON が複数行に割れて fail-close block になり、本来の判定を検証できない)
- zsh は変数展開で word splitting しない (`SH_WORD_SPLIT` が default off)。空白区切りの path を溜めた変数を `cmd $FILES` で渡すと全体が 1 引数になるため、`${=FILES}` か配列で渡す。path 数が多いと連結長が上限に達して `File name too long` になり、受け側 command が複数 path 非対応であるかのように見える (2026-08-23 実踏。切り分けは 2 要素で再現するかと `${=VAR}` との比較で足りる)
