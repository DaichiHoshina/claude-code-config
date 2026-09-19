---
allowed-tools: Read, Glob, Grep, Bash, Task, Skill, AskUserQuestion, mcp__serena__*
argument-hint: "[scope: commands|skills|agents|hooks|rules|plugins|references|launchd|logs|all] [--apply]"
description: claude-code 配下の設定資産から未使用・重複を実測で洗い出し、fact-check を経て削除する棚卸し command。「痩せさせて」「不要なもの消して」で起動
---

## /general-clean - 設定資産の棚卸し (実測 → fact-check → 削除)

`toolchain-lifecycle.md` の生存条件 (8 週利用ゼロ) を実際に適用する実行系。default は候補表の提示までで、`--apply` か user の「消していい」で削除に進む。方針 (増設条件 / cap) は `references/on-demand-rules/toolchain-lifecycle.md`、集計 script は `scripts/usage-stats.sh --zero` が canonical で、この command はその上に「計測の誤りやすい点」と「削除 checklist」を追加する。

## Step 1: 実測 (数値ごとに対象集合を列挙する)

**Step 0 (必須): 集計するマシンがメイン PC か確かめる。**

1. cwd のマシンがメイン PC か確認する (memory `user-machine-role` を参照)。非メイン PC の transcript は大半の command を使わないので「発火 0」の根拠にならない (2026-08-29 に非メイン PC の log で command 7 本を消し、後から裏取りが必要になった)
2. 非メイン PC なら候補表の提示で止める。メイン PC で `scripts/prune-usage-recount.sh` 相当の集計を取ってから `--apply` に進む
3. launchd / cron も同様に扱う。plist が `launchctl list` に無いのは「そのマシンで load していない」以上の意味を保持しない。メイン PC で `launchctl list | grep com.claude` を取り、載っている job は削除候補から外す (同日に 6 本を「どこにも load されていない」として消し、メイン PC では全部動いていたので revert した)

| 対象 | 計測 | 誤りやすい点 (2026-08-29 実踏) |
|---|---|---|
| command 利用 | transcript (`~/.claude/projects/**/*.jsonl`、mtime -90) の `<command-name>/x</command-name>` を数える | `commands/x.md` の file 名 grep は過大になりやすい。<br>- 原因: ai-tools 保守 session の Read / Edit も含めてしまう<br>- 対策: file 名で数えるなら ai-tools の project dir を除外する |
| 自然言語 trigger 経由 | `references/natural-language-triggers.md` に行があるか | tag が付かず transcript に出ない。trigger 行がある command は発火 0 でも保留にする |
| plugin | `templates/settings.json.template` の `enabledPlugins` で `true` のものを対象にし、利用は transcript の `"skill":"<plugin>:<skill>"` (Skill tool_use の実呼び出し) で数える | 既に `false` の plugin を「呼び出し 0」の根拠に含めない。<br>- 罠: 引用符なしの `grep -l 'claude-md-management:revise-claude-md'` のような語だけの grep は毎 session の skill 一覧に含まれる分を拾い、全 session が hit する (506 / 508 file と表示されて利用に見えた。2026-09-05 実踏) |
| 毎 session 固定 load | `~/.claude/CLAUDE.md` + 無条件 rule + `paths: **/*` rule の bytes、command / skill / agent の `description:` 行の bytes | 本文の行数は session cost でない。影響するのは description と auto-load 領域だけ。`/compact` 発火は transcript の `compact_boundary` で数え、`logs/compact-notice.log` は bats の test session ID が含まれる |
| 保管庫 (`_archive` 系) | active file から archive 内の個別 file を指す link を `rg '_archive/[^ ]+\.md'` で数える | 「読まれた回数 0」は link の存在を検出しない。消す前に link を履歴参照へ書き換える |
| references / guidelines で link 0 の file | 各 file 名で repo 全体 (`tests/` 除く) を grep し、他 file からの link 0 を出す | on-demand library の「据え置き」は trigger や索引から参照できる file の話で、どこからも参照されていない file は候補になる。`INDEX.md` が dir 単位で書く `retrospectives/` のような場所は個別 file の link が無くても索引上は存在して見える |
| launchd / cron | `launchctl list` + `~/Library/LaunchAgents` + `crontab -l` の 3 経路で load 状態を見る | plist が repo にあることと動いていることは別。hardcode された user 名や path の陳腐化も見る |
| agent 利用 | transcript の `"subagent_type":"<name>"` を数える。先に同じ母集団で全 agent の分布を出し、他 agent が検出できていることを確かめてから 0 を採用する | agent 定義は `md` + `toml` の対 (Codex port)。<br>- `~/.codex/agents` は `agents/` への symlink なので Codex 側も同時に消える<br>- 参照 grep は `rg --no-ignore --hidden` を付ける (repo root の `.ignore` が `*.md` を広く除外するため。付けないと `CLAUDE.global.md` / `references/` が hit せず参照数を過小に出す。2026-09-05 実踏) |
| hook | 登録経路 3 つ (`templates/settings.json.template` の `hooks` 節 / 他 hook からの `source` / `githooks/`) を file 名で grep し、どこにも無いものを出す。登録済の hook は event ごとに必ず実行されるので「発火 0」は成立せず、判定は登録と参照だけで行う | hook 名の log (`logs/<hook 名>.log`) は存在しない。hook が書く log は機能名 (`hook-info.log` / `stop-verify.log` / `subagent-events.log` 等) で、`grep -oE 'logs/[^ ]+\.log' hooks/<h>.sh` で探す (20 本中 11 本は log を記載しない)。登録が無くても他 hook から `source` される lib 兼用 script がある。block / warn 系を消す前に `scripts/hook-bench.sh --log` で baseline を取る (`measure-before-hook-change.md`) |
| rule | frontmatter の `paths:` を 1 つずつ取り出し、末尾の file pattern を `find <ghq-root>/github.com -name '<pattern>' \| head -1` に当てて到達を見る。`**/*` は全 file なので除外し、`{ts,tsx}` の brace は `*.ts` / `*.tsx` に分けてから当てる (`find` は brace を展開しない)。frontmatter の無い無条件 rule (4 本) と `paths: **/*` は毎 session load なので bytes を見る | `paths:` の書式は複数行 list (`- "**/*.go"`) と inline 配列 (`paths: ["**/*"]`) の 2 種があり、抽出はどちらも検出する。rule は編集対象に応じて auto-load されるので発火回数は transcript に出ない。「読まれた回数 0」で候補に含めず、glob の到達先が消えたものだけ候補にする。frontmatter の `- ` や引用符を pattern に含めたまま渡すと全 rule が到達 0 に見える (検出器が動作していない状態。`*.go` が 0 なら疑う) |
| runtime log (`~/.claude/logs/`) | file 名の日付部分を除いて prefix ごとに件数を数え、各 prefix の writer と reader を `rg --no-ignore --hidden -l <prefix> hooks scripts lib sync.sh` で探す。(a) writer なし = dead (b) reader の参照範囲 (`flow-baseline-summary` は 30 日、`hook-bench --diff` は直前 1 件) を超えて古い (c) 追記のみで rotation が無く 1MB 超、の 3 つに分ける | dot prefix の state file (`.session-split-warned-*` 等) は `ls` に出ないので `find -name '.*'` で数える。`hooks/session-end.sh` の purge list に無い prefix は 48h を超えても残存するので、writer が現役なら purge list へ追加する側で修正する (2026-09-05 に purge 対象外だった state file 3 系統を手で消し、purge list へ 6 pattern 追加した。`ee84391d`) |
| scripts / lib / templates | `git ls-files <dir>` を母集団にし、各 file 名で repo 全体 (`tests/` 除く) を grep して参照 0 を出す | 全 file が参照済なら削るものは無い。参照 0 の判定で `tests/` を含めると test だけが参照する残骸を見落とす。`find` を母集団にすると gitignore 済の `__pycache__/*.pyc` が候補に含まれる。script が起動する app の dir (`dashboard/` 等) は `git ls-files <dir>` が 0 なら本体が既に無く、script と test が残骸になっている |

- 参照 grep は常に `rg --no-ignore --hidden` で行う。repo root の `.ignore` が `*.md` を広く除外するため、付けないと `CLAUDE.global.md` / `references/` / `agents/README.md` が hit せず参照数を過小に出す (2026-09-05 に「参照 4 か所」と書いて実測は 19 file だった)
- 母集団で検出器を確かめてから 0 を採用する。同じ grep pattern で他の対象 (別 agent / 別 skill) が数件以上 hit することを先に見る。全部 0 なら「使われていない」より先に「pattern が jsonl の実 key と合っていない」を疑う (skill は `<command-name>` tag と `"skill":"x"` の 2 key に含まれる)
- 語が共通するだけの別機能を対象に含めない。`handoff` の語だけの grep は `--handoff` flag (investigation-session-contract) を検出する。検証 grep は `commands/x\.md` や `/x\b` の command 固有 pattern にする
- 判定表の候補には「主張 / 実測 / 判定 (verified / adjusted / rejected)」を付け、`/fact-check` の形式で reviewer-agent に第三者 check を合格させる

## Step 2: 判定

| 状態 | 扱い |
|---|---|
| 発火 0 (90 日) かつ trigger 行なし かつ 参照 0 | 削除候補 |
| 発火 0 だが trigger 行あり / 他 repo で読まれた | 保留 (次回再計測) |
| on-demand library (guidelines / references の trigger 読み) | 据え置き (session cost 0 なので読まれない = 無駄ではない) |
| 同名の command と skill | 分業 (command = workflow、skill = 完了 gate) の可能性を `allowed-tools` の差で見てから判断する |
| 役割が重なる入口 (review 族等) | 1 目的 1 入口へ flag 統合する。行数が目安 (command 150 行) を超えるなら on-demand 節を references へ移動する |
| 起動 0 の agent が判定表 (`fable.md` / `auto-delegation-detailed.md` / `CLAUDE.global.md`) に含まれている | 削除候補。表に保持すると存在しない agent への `Task` を誘い、hook は agent 名の allowlist を保持しないので止められない。表の行は代替 (explore-agent / `/lint-test` / `Skill(root-cause)`) へ差し替える |
| 起動 0 の agent の隣接入口 (同目的の skill / command) も 0 | 「skill から呼ぶ 1 行を追加して保持する」を代替案にしない (呼び出し元も未使用なら起動は増えない)。agent を消し、skill は別 item として再計測する |

## Step 3: 削除 checklist (`--apply` 時)

1. worktree を切る (`ai-tools-worktree-flow.md`)。`git rm` で消す。保管庫 dir は作らず git 履歴を復元先にする
   - plist / launchd script を消すときは、直前にメイン PC で `launchctl list | grep <label>` を打ち、出力が空であることを確かめる。load 中の plist の実体 script だけ消すと翌朝から job が失敗する
   - runtime log は git 管理外なので worktree は切らず `rm` で消す。消す前に読み手 (summary cron / `hook-bench --diff`) の参照範囲を確かめ、範囲内の file は保持する
2. 索引の更新: `references/command-tree.md` / `references/natural-language-triggers.md` / `references/INDEX.md` の該当行を手で消す (bats は「実在 file が索引にあるか」の片方向しか見ないので索引だけに残存する行を検出しない)
   - agent を消したら `README.md` と `agents/README.md` の表と link、他 agent の `Not:` 行 (`explore-agent` / `reviewer-agent` の md + toml 両方)、`references/model-selection.md` の tier 表も合わせて更新する
   - hook を消したら `templates/settings.json.template` の `hooks` 節と `hooks/README.md` の行を消し、sync 後に `~/.claude/settings.json` からも消えたことを見る
3. 削除した script / agent の test を逆引きして消す (`grep -rl <名前> tests/`)。script だけ消して test を保持すると fail する。agent は `agent-trailer-schema.bats` / `agent-frontmatter.bats` / `agents-toml-heading-sync.bats` に名前で固定された test があるので、その block を消す
4. 残参照を command 固有 pattern で grep して 0 hit を確かめる (CHANGELOG と過去日付の design doc / retrospective は履歴なので保持する)。rename を伴うときは `/x\b` の一括置換が `scripts/x-usage.sh` のような script 名の中の `/x` にも当たるので、置換後に新名で grep して存在しない path を作っていないか見る (2026-09-05 に `prune-usage-recount.sh` の参照を壊した)
5. 逆引き bats を実行し、**fail 数を `&&` 連鎖の中で読まない** (`grep -c '^not ok'` は件数を返すだけで exit code に反映されない)。file へ保存して `grep '^not ok'` を別 command で見る。`ok` が 0 件で exit 1 なら test の fail でなく起動失敗を先に疑う (改行区切りの file 一覧を変数展開で渡すと zsh が 1 引数にする。`xargs bats` で渡す)。worktree で bats を実行するために `node_modules` の symlink を置いたら、commit 前に `git status --short` で `A  claude-code/node_modules` が含まれていないか見る (2026-09-05 に混入して amend した)
6. ff-merge → push → `sync.sh to-local --yes` → `~/.claude/` で消えたことを確認する。plugin の無効化 (`enabledPlugins`) は settings の root key なので `--only=templates` では同期されず、全体 sync を要する
7. 定義 file (command / skill / agent) の削除と rename は再起動なしで次の呼び出しから反映される (2026-09-05 に同一 session で rename 後の skill 一覧と agent 削除の通知が発生するのを実測)。報告に「再起動が必要だ」と書かない。plugin の有効 / 無効 (settings の root key) の反映は未検証なので、切り替えたときは次の呼び出しで skill 一覧を見て確かめる

## Output

```
# /general-clean result (scope: <scope>)
| # | 対象 | 実測 | 判定 | 根拠 |
...
削除候補: N 件 (-<lines> 行) / 保留: N 件 / 据え置き: N 件
Next: /general-clean <scope> --apply  (または「消していい」)
```

## Anti-pattern (即 reject)

- 実測なしに「使っていなさそう」で候補に挙げる
- 保管庫 dir を新設して移動で済ませる (削除の先送り。git 履歴で足りる)
- fact-check の reviewer trailer を読まずに `--apply` へ進む
- 削除で空いた分を同 session で新設資産に使う (toolchain-lifecycle の one-in-one-out は増設側の規制で、削除は入場資格にならない)

## 参照

- `references/on-demand-rules/toolchain-lifecycle.md` (生存条件 / cap / 削除手順)
- `scripts/usage-stats.sh` / `scripts/health-check.sh` (機械集計)
- `commands/fact-check.md` (候補表の第三者 check)
- 却下済み代替案: skill 化は「発話で自動発火させる価値が薄い (月次以下の頻度)」ため command にした

ARGUMENTS: $ARGUMENTS
