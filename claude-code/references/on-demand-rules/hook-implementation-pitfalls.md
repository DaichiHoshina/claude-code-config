# Hook 実装の注意点集

`hooks/*.sh` の新規実装・logic 追加・NG list 変更の前に読む。latency baseline 計測は `measure-before-hook-change.md` が canonical で、この file は実装内容側の注意点を扱う。

## 注意点 1: NG list (PRINCIPLES.md) 追加時の 3 つの注意点

2026-06-04 session で新 NG list 追加時に 3 連続で失敗した実績から手順を固定した。

### 1-A. `〜` prefix 付き literal は `grep -qF` で match しない

`hooks/pre-tool-use.sh:_check_term_list` は fixed-string match (`grep -qF`)。literal に `〜かもしれない` と記載すると、text 側に `〜` (U+301C) が無いため match 0 で block が発火しない。list には prefix なしの素 literal (`かもしれない`) を記載する。既存 list は元から prefix なしで、新 list だけ説明文の感覚で `〜` を付けてしまう点に注意する。

### 1-B. commit message 本文に NG literal を直書きすると自己 block する

allowlist は `<repo-root>/` 配下 file 編集のみで、commit message は対象外。commit body には literal を書かず「推測語 4 種を block する (list は PRINCIPLES.md の該当 section)」のように抽象表現 + file 参照に置き換える。

### 1-C. sync to-local を忘れると全 commit / gh / Slack MCP が blocked になる

hook は sync 先 (`~/.claude/`) の `hooks/pre-tool-use.sh` が同じ sync 先の PRINCIPLES.md から list を動的抽出する。source 編集後に sync していないと `_assert_required_keys` が exit 2 (loud fail) で後続操作を全部止める。`./claude-code/sync.sh to-local --yes` で反映する (`--yes` 必須)。

### 1-D. 新 NG literal 追加前に git log を確認する

`git log --all --oneline | grep -F '<term>'` で既存 commit に同 literal が含まれていないか確かめる。push 済 commit を hook は block しないが、影響範囲の判断に使う。

### canonical 手順 (5 step)

1. PRINCIPLES.md の NG 辞書 section に `**<name> (block)**: <素 literal>` を追加する (`〜` prefix なし)
2. hook を編集する: `required_keys` / `_inject_keys` / `_block_if_ai_jargon` の 3 箇所 (既存 category を手本にする)
3. `./claude-code/sync.sh to-local --yes` で反映する
4. block test: `echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"<NG literal>\""}}' | ~/.claude/hooks/pre-tool-use.sh; echo "exit=$?"` で exit=2、通常 message で exit=0 を確かめる
5. commit + push: body に literal を直書きせず file path 参照に置き換える

## 注意点 2: session_id は stdin JSON から取る (env は leak する)

Claude Code は session_id を env でなく **stdin JSON** で hook に渡す。`${CLAUDE_SESSION_ID:-$$}` のような env 参照は空 fallback で bash PID になり、`/tmp/claude-session-*` 系 flag file が絶対 hit しない silent bug になる (2026-06 commit `775f842` で発生、`4265e10` で修正)。env `CLAUDE_CODE_SESSION_ID` を優先する逆 pattern も hook 7 file で再発した (env は session 切替時に前 session の値が leak する、incident 2026-06-25)。

- 必ず `SESSION_ID=$(jq -r '.session_id // empty' <<< "$INPUT")` で stdin から抽出する
- flag file path は `/tmp/claude-hook-<hook-name>-${SESSION_ID}` で session 粒度にする
- 参照実装: `hooks/session-start.sh` / `hooks/post-tool-use.sh`
- `tests/unit/hooks/session-id-stdin-priority.bats` が env 優先代入を grep 検出する。新 hook 追加でこの bats が RED になったら stdin 優先に直す
- smoke test: hook 手動発火 → `/tmp/claude-hook-*` 作成確認 → 2 回目で skip 確認

## 注意点 3: git commit の option 判定は word-boundary 正規表現にする

substring 判定 (`[[ "$COMMAND" != *"-m"* ]]`) は `--message` が `-m` を部分文字列に含むため誤マッチする。2026-06-14 `e8af1de` でこの注意点により `git commit --amend --message='...'` が block も warn もされず NG 語がすり抜けた。

- word-boundary regex を使う: `=~ (^|[[:space:]])(-m|-F|--message|--file)([[:space:]=]|$)`
- 本文抽出側も short / long / `=` 区切りの全形式に対応させる。抽出と warn 抑止が両方すり抜けると安全網が消える
- test には long form と `=` 区切りを必ず含める
- 注: `git commit -F=file` は git 自体が fatal で拒否するため block 不要 (`gh --body-file=` とは挙動が別)

NG 語 canonical は `guidelines/writing/NG-DICTIONARY.md`。

## 注意点 4: 存在チェックは引数付き command から `${cmd%% *}` で実行 file 名を取り除く

settings.json の `command` field は `hook.sh cleanup` のような引数付き形式を取る。丸ごと `-f` チェックすると存在しない path を評価して false-positive になる (2026-05-17 に `session-start.sh` の診断で「not found」誤診断 4 件、`5dc6c1d` で修正)。`[ -f "${cmd%% *}" ]` のように引数を除去してから確認する。

## 注意点 5: 文体違反の再発は rule 追記で止まらない、block 昇格が構造対応

「完了」多用など文体違反の再発に対して、rule / CLAUDE.md への規範追記は効果が現れないことが実測で確定している (rule 追加翌日から同 pattern が再発、7 日累積 warn は増加)。warn は systemMessage で user にしか見えず AI に届かない (7 日で block 79 件 vs warn 1850 件)。block だけが AI に書き直しを強制する feedback loop になる。

- 文体・出力品質の改善依頼が来たら、規範 file の追記より先に `lib/jp-quality/block-checks.sh:_chat_quality_check` の block 対象昇格を検討する
- warn を次 turn へ届けたい場合は `/tmp/claude-stop-jpq-warn-*` 経由の additionalContext 還流を使う (commit `a3c1485`)
- 誤爆が多い検査 (断定語「完了」、連続漢字) は block にしない。loop 上限 5 を浪費して機構全体が log-only へ降格する

## 注意点 6: 語彙 denylist は意味を判定できない、量 gate が構造対応

NG 語ゼロ + 常体で閉じた What 言い換え comment は文字列照合を必ず通過する (2026-07-18 実測)。意味の判定を hook でやろうとせず、量 (新規日本語 comment の行数上限) を機械強制する方が構造対応になる。参照実装: `lib/comment-style-checker.sh` の comment 量 gate。

## 注意点 7: checker 自己改修中の stale warn はノイズ

worktree で checker 自体を改修している間は、sync 前の古い live checker が新規範では正しい行 (動詞終止・動詞 + 閉じ括弧等) に warn を出し続ける (2026-07-18 実踏)。この warn は sync 後に消えるため、1 件ずつ追わず「新 checker で判定し直して本物だけ直す」で切り分ける。

## 注意点 8: hook が出力する log を集計する script は書き出し元 printf を先に確認する

hook / checker が出力する log を awk / grep で集計する script を作成する前に、集計対象 log の書き出し元 printf / echo 文を必ず Read で先に確認する。log の field format (bracket 有無 / tab vs pipe 区切り / 列順) は log 種別ごとに違うことが多く、1 format を仮定して parser を作成すると他 log で silent-failure する (error にならず 0 件集計)。2026-07-21 の `scripts/warn-log-weekly.sh` で 4 log 中 3 log が silent-failure し、翌日発覚 (commit `3c04031` で修正)。CLAUDE.md 「Compounding Engineering」 の「automation 追加は既存分を実測してから判断する」基盤 script が事実上機能しない状態だった。

- 手順: (a) 書き出し元 hook / script を grep で全部特定 (b) それぞれの printf format を Read で確認 (c) format 差分があれば log 種別ごとに parser を分岐する
- bats test も format 種別ごとに最低 1 case ずつ用意する (silent-fallback は仕様として明示 test を作成する、参照: `tests/unit/scripts/warn-log-weekly.bats`)
- 既存の類似 script (dashboard 集計 / retrospective 集計 等) を変更する時も同じ check を先に実行する

## 注意点 9: (廃止 2026-08-28) 100 字超 block は Edit 対象 file 全体を再走査する

> 100 字超文の block / warn は 2026-08-28 に撤去した (字数を理由に語を削った不自然な文を誘発したため。canonical: `guidelines/writing/PRINCIPLES.md` 「文章生成の不変条件」「短くする目的で語を削らない」)。注意点 9 / 注意点 10 は当時の挙動の記録として保持する。

`hooks/pre-tool-use.sh` の「100 字超文 block」は Edit の new_string だけでなく Edit 後の file 全体を再検査する。触った行の周辺に既存 100 字超文があると、その行を変更するだけで block が発火する。新規追加分は 100 字未満でも block される。

**Why**: 2026-07-22 の unused-flag 削除で audit.md L50 (231 chars) の直下にある `--no-temp-lock` 参照を消そうとした。`Phase 1: Detection` 行 (既存長文) が block trigger になり Edit が通らなかった。同 pattern で git-push.md L20/L24/L47 の 3 flag も skip、計 6 件を回収できずに終わった。

**How to apply**: 既存長文 file を変更する前に `awk 'length>100'` で file 全体を先に scan する。長文と触りたい行が同一 section にあるなら「(a) 長文を先に句点で割る commit → (b) 目的 edit の commit」の 2 phase に分ける。1 commit で済ませたい時は Options 表 row 削除など block trigger の外側だけを変更する minimum path に限定する。

判定単位は文ではなく段落になる。改行までの 1 chunk をまとめて 1 文として数える。

- 段落内を句点で割っても、chunk 合計が 100 字超なら block する
- 空行で段落を割るか bullet 化して回避する (bullet 1 個 = 独立 chunk)
- 2026-07-26 の goal.md で実踏した。改行なしの 113 字段落が原因だった

## 注意点 10: (廃止 2026-08-28) Edit の anchor に既存長文を含めると block する

pre-tool-use の jp-quality hook は Edit / Write の new_string 全体を検査し、自分が書いた文でなくても含まれる既存行の 100 字超文 (英文含む) を block する。

**Why**: 2026-07-22 の command-tree 実装で、既存英文 intro を old_string に含めた挿入編集が 2 回 block された。anchor を直後の見出し行に変えたら通った。

**How to apply**: 既存文の直後に挿入する編集では、長文を old/new に含めず、見出しや短い行を anchor にする。Write 全置換時は既存長文も分割対象になる点に注意する。

## 注意点 11: 禁止語 literal を引用したい時は code fence で囲む

commit message や chat 応答内で、jp-quality hook の禁止語 (AI 段取り定型) を「例文の literal」として引用したい場合、通常の文中に記載すると block される。code fence 内は scan 対象外。

**Why**: hook (`hooks/pre-tool-use.sh` + `lib/jp-quality/`) は code / literal block を warn / block 対象から除外する仕様。fence 外の平文だけを judge する。

**How to apply**: hook 禁止語 (AI 段取り定型 / 難読漢語 / 完了) を literal として引用する必要があるとき、以下 3 手いずれかで囲む: (1) fenced code block (``` で囲む) / (2) 4-space indent block / (3) inline code span (`` ` `` で囲む)。commit message HEREDOC 内も同じ扱いで検査対象外になる。

## 注意点 12: 長時間 pipeline の副作用 fingerprint に git HEAD を含めない

長時間実行される pipeline (harvest / mine / gate で 2 分以上) 内で「maker が tracked file に副作用を出したか」を git 状態の hash で検知するとき、fingerprint に `git rev-parse HEAD` と `git status --porcelain` を含めない。`git diff` + `git diff --cached` だけで判定する。

**Why**: sleep-pipeline (`sleep-cron-run.sh:79`) が実行中に別 session が commit すると HEAD が変わる。maker session が tracked file を全く触っていないのに reject が発火して当日枠を無駄に消費した (2026-07-22 07:22 事象)。maker の tool 履歴を全 dump しても Edit 対象は stage file (untracked) のみで、真の HEAD 変化元は同時刻の別 session commit だった。

**How to apply**: dev / cron / launchd で並行実行される長時間 script の副作用検知に git 状態を使うとき (`_tracked_fingerprint` 相当)、HEAD と porcelain は除外し diff 2 種のみで hash を作る。stage file を untracked のまま Edit 対象にする pattern なら porcelain 除外が同時に false positive も防ぐ (untracked path 列挙のみで内容 hash なし)。tracked file の unstaged / staged 変化検知は diff 2 種で必要十分。

## 注意点 13: rule 追加 / 辞書追加は AI 想起依存で適用されない (3 回失敗)

hook block / warn が高止まりしている pattern (jp-quality の 100 字超 / 完了 turn 締め等) に対し、rules/*.md や NG-DICTIONARY.md への rule 追加 / 辞書 pattern 追加で対処しても、block 頻度は下がらない。同型の対処を 3 回失敗した実測がある。

- 2026-07-15: rule を CLAUDE.md 冒頭 header へ格上げ → 「完了」warn 424→421→461 と横ばい
- 2026-07-17: JP 文体 hook 拡充、禁止語 12 語追加 + 100 字超 block に該当文冒頭 32 字表示 → 直近測でも block 頻発
- 2026-07-20: 5 分間で 5 連続 block

**Why**: LLM の生成 loop に self-check が組み込まれていない基礎能力課題を、rule 記述 (= AI が「思い出す」ことに依存する型) で解決しようとしても、書く直前に rule を想起する trigger が無く同 pattern が再発する。

**How to apply**: 同種の再発抑止設計をするとき、rule / 辞書追加案は「AI 想起依存」型として除外し、以下 3 型のいずれかに限定する: (1) 既存 hook 拡張 (`_inject_chat_selfcheck_if_signal` の trigger 語拡張 pattern) / (2) block 後の retry 成功率向上 (block message に修正例テンプレを inject する pattern) / (3) AI が通らざるを得ない経路の構造強制 (git-push script の commit template pattern)。

## 注意点 14: log parser は実 log 1 sample で列区切りを先に確かめる

log format を「TS | context | term | verdict」等の N pipe 区切りだと仮定して parser を作成するとき、作成前に必ず実 log を tail し **term 側に区切り文字 (`|`) が含まれていないか** を確認する。想定 N と実 NF が違えば単純 `-F' \| '` split は列位置がずれて silent fail する。

**Why**: 2026-07-20 の jp-quality-override-detect.sh 実装で、`jp-quality-block.log` を 4 列と仮定した awk -F' \| ' が実 log で NF=7-37 になり、literal 照合が 0 hit で沈黙失敗した。unit smoke は合成 4 列 log で通ったが実運用で機能せず、fix commit が 1 個増えた。

**How to apply**:
1. parser 実装前に `tail -20 <log> | awk -F<sep> '{print NF}' | sort | uniq -c` で NF 分布を見る
2. NF が一定でないなら区切り文字が term 内に混入している。first-pipe と last-pipe による 3 分割 (TS / rest / verdict) 方式か、jsonl / tsv 等の safe 区切りに置き換える
3. unit smoke は必ず実 log の tail 1-3 行を fixture に採る (合成 log で通しても実運用の証拠にならない)

## 注意点 15: async 登録の hook は block / 出力書換が無効

settings で `async: true` 登録した hook が返す `decision: block` と `hookSpecificOutput.updatedToolOutput` (出力書換) は harness に無視される。exit code 2 も無視される。async は fire-and-forget で、`asyncRewake` だけが exit code 2 で wake する (公式 doc: "runs in the background without blocking")。

**Why**: 2026-07-26 の設定監査で、stop.sh (raw XML / NG 語 block) と post-tool-use.sh (secret redact) が async 登録のまま block / redact を出していて silent 無効化していた。async 化が guard 追加より先で時系列が逆転したのが原因。stop.sh の raw XML guard は「最終防衛」と信じられていたが適用されていなかった。

**How to apply**:
1. block や出力書換 (redact / sanitize) を有効にしたい hook は必ず `async` を外して同期登録する。log 出力・通知など副作用だけの hook は async のままでよい
2. 同期化コストは block 経路が早期 exit するか (stop.sh は exit 0 で重処理未到達)、matcher が限定できるか (post-tool-use は Bash 限定で他は early-exit) で判断する。新 hook 分離より async 除去 1 行が regression 面で有利なことが多い
3. hook を新規追加するとき、その hook が block / 出力書換を出すなら async にしない。log 専用と block 兼用を同 file に置くなら、同期にして block 経路を早期 exit させる

## 注意点 13: script-level trap / set -E は source した unit test に leak する

hook 本体へ ERR trap や `set -E` を追加すると、hook を `source` して関数を直呼びする unit test にも trap が installed され、`return 1` 契約の関数が exit 2 になる (&& list 末尾の関数呼び出しは ERR trap の発火対象)。

**How to apply**: trap の install 条件に `[[ "${BASH_SOURCE[0]}" == "$0" ]]` を含めて直接実行時のみ仕込む。影響検証は file 列挙でなく `bats tests/unit/hooks/` の dir 全数で実行する (2026-08-13 実踏: pre-tool-use の trap 追加で prep-check 系 5 件を列挙しないまま「影響なし」と誤報した)。

## 注意点 16: comment 量 / 体言止め / NG 辞書の block も編集単位で発火する

100 字超以外の jp-quality block も、Edit 1 回分の new_string をまとめて judge する。

- comment 量: 1 編集の新規 comment は 2 行まで。関数を 2 つ追加すると doc comment が合算されて block する
- 体言止め: 折返し行を各行独立で検査する。1 文を 2 行に割ると両方が体言止め扱いになる
- NG 辞書: NG 語を例示として含む file では、無変更の既存行を anchor に含めた時点で block する

**Why**: 2026-07-19 に memory-save-helper.sh / post-tool-use.sh / PRINCIPLES.md で各 1〜2 回実踏した。

**How to apply**: 関数追加は 1 編集 1 関数に割る。日本語 comment は 1 行 1 文で閉じ、折り返さない。

NG 語を含む file では、挿入位置の直後行など NG 語を含まない行を anchor として採用する。

## 注意点 17: ERE の bracket 内 `\n` は改行に match しない

`grep -E` の `[\n]` は改行ではなく literal の `\` と `n` の 2 文字に match する。

**Why**: grep は行単位処理で行内に改行が現れず、POSIX ERE は bracket 内の backslash を literal 扱いする。

**How to apply**: 行頭判定は `^` だけで足りる。複数行にわたる判定が必要なら tr / awk 側へ委ねる。

2026-07-18 の jp-quality 位置判定で ASCII n 直後の短語を誤って block した (352c0e4 で修正)。

## 注意点 18: block 文言の「最小例」が canonical と食い違うと再 block loop になる

gate 系 hook の error message に記載する retry 誘導 (最小例・形式説明) が canonical 文書の要求形式とずれていると、AI は誘導どおりの誤形式で retry して再 block される loop に入る。

**Why**: block された側は canonical を読み直さず error message だけを頼りに retry する。誘導文言は gate の仕様の一部で、gate 本体と同じ精度を要する。

**How to apply**: gate を追加・修正したら、error message に「検査を通過する形式の具体例」を載せ、canonical の記述・validator の正規表現と 3 点一致を確認する。2026-08-23 の explore contract gate で、最小例が `anchor_evidence: <ls/git 出力 1 行>` と誤形式を教えており、形式違反 block 10 件/週の主因だった (91bea9ee で修正)。

## 注意点 19: set -e + pipefail 下の glob 非 hit が script を丸ごと落とす

`x=$(ls -t "$dir"/pat-*.md 2>/dev/null | head -1)` は glob が 1 件も hit しないと script 全体を終了させる。`2>/dev/null` は error 出力を隠すだけで exit code を変えず、pipefail が `ls` の非 0 を pipeline に持ち上げ、set -e が assignment の失敗として検出する。「無ければ空文字」のつもりの行が出力なしの即時終了になり、後ろの無関係な出力もまとめて消える (2026-08-24 実踏: session-start.sh の compact 復元 block で、snapshot 不在時に memory 読込指示と guidelines 注入ごと消えていた)。

**How to apply**: 「無ければ空でよい」代入には `|| true` を明示する。存在チェックが目的なら bash の glob と `[[ -e "${arr[0]}" ]]` で書く。test は「1 件も無い」経路を 1 本書き、`[ "$status" -eq 0 ]` を assert に含める (出力の assert だけだと即死と分岐違いを区別できない)。

## 注意点 20: guard の案内文が「対象外の同種 path」を推奨していないか確かめる

block 系 guard の error message に記載する「代わりにここへ」の path は、guard 自身の block 対象と同じ精度で保守する。禁止 path A を block しつつ案内文で path B を勧め、B が別の rule で禁止済みだと、hook が禁止領域へ誘導する装置になる。

**Why**: 2026-08-28 の点検で、`.serena/memories/` guard の案内文が廃止済みの auto-memory (`~/.claude/projects/*/memory/`) を推奨し、その auto-memory guard は ai-tools 系 dir しか block していなかった。結果、org 作業用 dir に 7/14〜8/21 の 51 file が書かれ、live memory の dead ref 30 名 / 100 箇所超の主因になった。CLAUDE.md の禁止文は 3 重の誘導 (system prompt / 案内文 / 部分 block) に負けた。

**How to apply**:
1. 案内文の path は固定文字列で書かず、解決 script (`memory-save-helper.sh resolve-dir` 等) の出力を指す
2. guard の block 対象を project / repo 名で限定するときは、限定した外側に同種の禁止 path が無いか `find` で実測する (今回は `~/.claude/projects/*/memory/*.md` の全 project 集計で発覚)
3. 廃止した path は「禁止と書く」だけでなく guard の block 対象に入れる。rule 追記だけでは止まらない (注意点 13 と同型)
4. 廃止領域への流入は `/memory-clean` Stage 1 の legacy-dir 検出が定期的に数える

## 注意点 19: settings の env は Bash tool に継承されるので、既定値を確かめる bats は env を外す

`~/.claude/settings.json` の `env` は Claude Code の Bash tool の子 process に継承される。`JP_QUALITY_STYLE_ENFORCEMENT=1` を既定にした (2026-09-11) 後、「既定では block しない」を確かめる `tests/unit/hooks/notion-checkers.bats` が Bash tool 経由でだけ失敗した。terminal から直接実行すると成功するため、hook の regression に見える。対処は `run env -u JP_QUALITY_STYLE_ENFORCEMENT bash -c '...'` で変数を外し、code 側の既定値 (未設定 = 0) を確かめる形にする。settings の env に hook の切替変数を追加したときは `grep -rn "<VAR>" tests` で既定値に依存する test を探す。

## 注意点 21: hook の修正は再起動なしで反映される (settings.json の登録だけ例外)

`hooks/*.sh` と `hooks/lib/*.sh` の修正は、sync 後の次の tool call から既存 session にも反映される。hook は毎回別 process として動き、lib も毎回 source されるので、既存 session でも最新の内容が実行される。command / skill / agent の定義 file も、追加・削除・rename が同じ session に反映される (2026-09-05 実測)。

- 再起動を案内するのは、settings.json の hook 登録を変えたときだけにする
- 「再起動後に反映される」と報告する前に、sync 後に同じ操作を再実行して確かめる (sync.sh の古い案内文を根拠に誤報告した実例がある)

## 注意点 22: hook の出力は「user 向け」と「model 向け」を区別する

`systemMessage` は user の画面に表示されるだけで、model の context に入らない。model へ渡す経路は `hookSpecificOutput.additionalContext` か plain-text stdout の 2 つ。hook から skill を自動起動する API は無く、skill 名を表示しても model は読まない。

- 規範を model に適用させたいなら、`additionalContext` に「どの file を Read するか」の 1 行を記載する。本文の複製は不要
- hook 出力の test は「期待する文字列が context に入ること」を検査する。長さ 0 を正として固定すると、壊れた状態が凍る (2026-08-17 に実踏)
- 注意点 5 の warn が AI に届かない件も、同じ原因

## 注意点 23: block の処理を変えたら、実際の JSON を hook に渡して出力まで確かめる

bats と lint の通過だけで終えない。`sync.sh to-local` の後に `jq -n '{tool_name:..., tool_input:{...}}' | bash ~/.claude/hooks/pre-tool-use.sh` で実物を渡し、block の message 本文が出力されることを確認する。

- 確認する経路は 3 つ: file への Write (md と code の comment)、commit message を含む Bash、chat 応答を検査する `stop.sh`
- 拒否されないはずの入力 (言い換え後の日本語) も 1 件渡し、誤検出が無いことまで見る
- 実例 (2026-09-14): lib の関数を直接呼ぶと正常なのに、hook 経由では `set -e` で停止して出力が 0 文字になった。fail-close のため exit 0 で終わり、log にも記録が作られない

## 関連

- `measure-before-hook-change.md` — hook 編集前の latency baseline 計測
- `guidelines/writing/NG-DICTIONARY.md` / `guidelines/writing/PRINCIPLES.md` — NG 語 canonical
- `CLAUDE.repo.md` "## Hook 編集 baseline rule"
