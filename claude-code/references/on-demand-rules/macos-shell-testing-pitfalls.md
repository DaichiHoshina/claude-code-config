# macOS shell / bats / launchd の注意点

hook script / test / launchd LaunchAgent を作成する時に読む。macOS BSD 環境と bash 3.2 前提の誤りやすい点を集約した。

## 1. macOS launchd は sleep 中に発火しない

macOS の launchd `StartCalendarInterval` job は sleep 中に発火せず、wake 時に 1 回だけ遅延実行される。skip されるのは電源 off の時だけ。

**How to apply**: 定刻発火が必要な夜間 job には `sudo pmset repeat wakeorpoweron <days> <HH:MM:SS>` の自動 wake と、wake 直後に `caffeinate -s -t <sec>` を実行する LaunchAgent (ai-tools では `com.claude.night-caffeinate`) をセットで使う。`caffeinate -s` は AC 電源時のみ有効で、バッテリー + 蓋閉じでは適用されない。

## 2. launchd は sleep 中の予定を wake 時に catch-up する (skip は電源 off のみ)

`StartCalendarInterval` は cron と違い、Mac sleep 中に到達した予定を wake 時にまとめて 1 回実行する。cron / systemd timer の類推で「PC sleep 中は skip される」と誤認しない。実挙動確認は `pmset -g log` でできる。

**How to apply**: launchd の StartCalendarInterval を使う LaunchAgent を作成する時、sleep 対策の catch-up 機構を追加で作らない。夜間 job (02:03 発火想定) が PC 閉じてる時間帯にあっても、翌朝 wake で 1 回 fire する前提で設計する。launchd 触る前に類推で判断しない。

## 3. macOS BSD awk は `-F' \| '` を空白 split に degrade する

pipe 区切り log を macOS BSD awk で読むとき、field separator に `-F' \| '` を渡すと FS が空白 split に degrade する。実測で NF が期待の 4 から 7/9/11/29 になる。GNU awk は `\|` を扱えるが portability を優先し、必ず文字クラス `-F' [|] '` を使う。

**Why**: 2026-07-20 の rule-recall-surface Task 3 で metric が n=0 c100=空 ck=空 を返した。同じ FS を Task 2 fix にも使っていたが grep 併用で偶然動いていた。壊れた $3 でも substring match が検出する fragile state だった。

**How to apply**: hook / cron script / metric TSV command / log 集計 shell で `awk -F' \| '` を書きそうになったら `awk -F' [|] '` に置き換える。grep 併用で見た目動く場合も fragile なので同時に直す。

## 4. bats の `! grep` は非最終行だと fail を握りつぶす

bats test で `! grep -q PATTERN FILE` を否定 assertion として使うとき、その行が test 関数の最終行でないと fail が握りつぶされる。原因は bash の `set -e + !` の相互作用で、`!` で否定した command の失敗は early-exit の対象外になる仕様。最終行だけが test の verdict を決めるため、bug 検出行が先・trivial に真の行が後の並びだと regression guard として機能しない。

**Why**: 2026-07-20 の rule-recall-followup で発覚。reviewer が base commit に checkout して test 9 を単独実行し、bug が再現しているのに ok を返すことを empirical に示した。同 pattern を持つ既存 test 3 にも同じ不足があった。

**How to apply**: bats の否定 assertion は `run cmd; [ "$status" -ne 0 ]` 形式で書く。既存 `! grep -q` を見つけたら同時に書き換える。単発 `! grep` (最終行 1 行だけ) は正しく fail 化されるため必ずしも書き換え不要だが、複数 assertion がある関数では例外なく `run + status` に統一する。参照実装: `tests/integration/rule-recall-surface.bats` の test 3/9。

## 5. bats を worktree cwd で実行すると cwd-guard で 38 本が偽 fail する

ai-tools の hook test (`bats -r tests/unit/hooks/`) を `.claude/worktrees/<name>/` 配下の cwd から実行すると、`hooks/lib/write-checkers.sh` の cwd-guard (worktree session 中の worktree 外 path Edit を Forbidden にする機能) が `/tmp` path を使う Edit 系 test で発火し、38 本が偽 fail する (2026-07-16 の pretooluse-split loop で実踏)。

**Why**: cwd-guard は `CLAUDE_PROJECT_DIR` (無ければ `pwd`) が `*/.claude/worktrees/*` に一致すると worktree session と判定する。test helper は cwd を変えないため、worktree 内で実行した bats がそのまま guard 対象になる。

**How to apply**:
1. worktree 内で bats を実行するときは `CLAUDE_PROJECT_DIR=$HOME/ghq/github.com/<owner>/ai-tools bats -r tests/unit/hooks/` で guard を回避する
2. `/loop` の gate command を worktree 起点にする場合も同じ env を gate に含める。含めないと gate が永遠に FAIL し、maker が無駄 iteration で cost を焼く
3. gate green 判定を pipeline (`bats ... | tail`) で見ない。pipe の exit は tail のものになるため `bats ...; echo $?` か `&&` 連鎖の位置で確かめる

## 6. Claude Code CLI は Bash tool 実行に /bin/bash (3.2) を hardcode する

Claude Code CLI (`~/.local/share/claude/versions/<ver>`) は Bash tool 実行 shell として `/bin/bash` を hardcode する。macOS 標準 bash は 3.2 で `declare -A` 等の bash 4+ 構文を通さない。

**Why**: foreground session ではまだ問題が顕在化していなかったが、launchd 経由の headless `claude -p` で jp-quality lib の `declare -A` が全 tool block を起こし判明した。PATH 側で bash 4+ を先に置いても Bash tool の shell 選択は CLI 内部制御で覆せない。

**How to apply**: hook / lib で bash 4+ 構文を使う時は、hook 冒頭で `[[ BASH_VERSINFO[0] -lt 4 ]]` を検知して `/opt/homebrew/bin/bash` に `exec` 切替する guard を置く。`_JP_HOOK_BASH_UPGRADED=1` 等の env で無限 loop 防止。source される lib file は shebang が適用されないため、source 側 (入口 hook) で切替する。canonical impl: `hooks/pre-tool-use.sh` 冒頭。

`mapfile` (別名 `readarray`) も bash 4+ の機能で、3.2 では `mapfile: command not found` になる。`scripts/` 配下には exec 切替の guard が無く user が直接実行するため、array は `while IFS= read -r line; do arr+=("$line"); done < <(cmd)` で作る。空 array へ `${#arr[@]}` を参照すると `set -u` で error になるので `${#arr[@]:-0}` の形にする。shellcheck はこの不足を警告しないので、bats を実行するまで気付かない (2026-09-12 に `scripts/publish-export.sh` で 34 件が全 fail した)。

## 7. launchctl kickstart の連発は throttle で silent drop する

launchd agent の手動発火 (`launchctl kickstart -k gui/$UID/<label>`) を複数 label へ連続実行すると、throttle により一部が spawn されず silent drop する (2026-07-23 実測: 4 本連発で runs 数が 1 本も増えなかった)。kickstart は即時実行の保証がなく、exit 0 で返るため失敗が見えない。

**Why**: launchd は minimum runtime (default 10 秒) 未満で exit した job の再 spawn を抑制し、連発 kickstart も間隔不足として drop する。log 追記も runs 増加もないのに command 自体は成功するため、「発火した」と誤認する。

**How to apply**: 発火は 1 本ずつ `sleep 15` 以上空けて実行する。発火後は `launchctl print gui/$UID/<label> | grep runs` で runs 数の増加を確認する (log mtime だけでは前回実行と区別できない)。state = running → not running + last exit code の遷移まで見てから完了と判断する。

## 8. launchd job の正常ログを stderr に出力すると err.log 監視が永久誤警報する

launchd の StandardErrorPath は追記式で rotate されないため、`_log()` 等が正常ログを `>&2` で出力すると、監視 script の「err.log にサイズあり = エラー」判定が一度きりの書込みで永久に誤警報する (2026-07-25 daily-report で実発生)。

**How to apply**: cron script の stderr は実エラー専用にし、進行ログは stdout に出力する。監視側は前回 offset からの増分だけで判定する。

## 9. plist 生成 script の `&&` は `&amp;` escape + plutil -lint 必須

heredoc で plist を生成する install script が command 文字列の `&&` を生のまま埋めると、plist が XML として invalid になる。launchctl は load 済みの旧版で動き続けるため壊れに気づけず、再 load 時に初めて失敗する (2026-07-25 hook-bench / flow-baseline で実発生)。

**How to apply**: plist 生成 script は `&` を `&amp;` に escape し、生成直後に `plutil -lint` を必ず入れる。

## 10. 日次 cron/digest の date-only cutoff 計算は JST-UTC 境界と同日再実行で壊れる

日次実行の digest/cron で「前回実行日 + N 日」のような date-only (時刻を含まない) marker から since cutoff を計算すると、実行時刻と UTC 日境界の関係次第で cutoff が未来日に飛び、新着 0 件と誤検出する。JST 朝 (9 時 JST = 0 時 UTC) より前に実行する cron で特に発生しやすく、同日に 2 回実行した場合も同じ理由で壊れる (pr-review-digest skill で実発生、複数日分が「新着 0 件」と誤記録された)。

**How to apply**: since 計算は date-only marker + 固定 offset でなく、前回実行の正確な ISO timestamp (since-cursor 形式) を記録してそのまま次回 cutoff に使う。date-only marker の実装を見かけたら、timezone と UTC 日境界の関係、同日複数回実行の 2 case を疑って検証する。

## 関連

- `references/on-demand-rules/hook-implementation-pitfalls.md` — hook 実装全般の注意点
- `references/on-demand-rules/bash-tool-environment.md` — Bash tool の環境制約
- `references/bats-test-writing.md` — bats test 書き方
