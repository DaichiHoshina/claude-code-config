---
allowed-tools: Read, Edit, Write, Glob, Bash, AskUserQuestion
description: 夜間 job の残件 (失敗 / メモリ掃除の判断待ち / staged 提案) を朝にまとめて片づける単一入口
---

## /sleep-review - 夜間提案の triage (SkillOpt-Sleep Adopt 段)

**Core**: `scripts/sleep-cron-run.sh` が夜間に staging した `memory/sleep-proposals-<date>.md` を処理する。gate C (`scripts/sleep-self-review.sh`、mine / retrospective / audit の全 cron に配線済) が Tier 1 (data/dict 追記)・Tier 2 (command/skill 追記、self-review 通過分)・audit (npm test 通過分) を夜間中に auto-adopt 済で、この command は Tier 3 (`Type: hook` / `remove` / `new-skill`、CLAUDE*.md 全般、常に人手判断) と gate C が HOLD/REJECT にした残りのみを扱う。

## Flow

0. **夜間 job の残件回収** (朝の入口をこの command 1 つに合わせる。Slack の「今日やること」に発生する項目は全部ここで片づける):
   - **job 失敗**: log は追記式で rotate されないため、末尾を読むだけでは解決済みの失敗を毎朝掘り起こす (2026-08-29 実踏)。判定は次の手順で行う。
     1. offset 取得: `~/.claude/logs/launchd/.daily-report-err-offsets` から `<job>` (err.log 用) と `<job>.out` (stdout log 用) の byte offset を取得する。これは前回 Slack 通知に成功した時点の大きさで、それ以前は既報とみなす
     2. 増分抽出: `tail -c +$((offset + 1)) <log>` で増分だけを読み、増分が 0 なら現役の障害ではないので次の job へ進む。offset に entry が無い job と、log が offset より小さい場合 (手動削除 / rotate) は先頭から読む
     3. file 名解決: log の file 名は job 名と一致しないことがある (`pr-review-digest` の実体は `<org>-pr-review-digest.log`) ので、path は `~/Library/LaunchAgents/com.claude.<job>.plist` の `StandardOutPath` / `StandardErrorPath` から取得する
   - 増分に失敗が発生したら原因 1 行と修正案を提示する。cron-auto-repair が PR を作っていればその URL を出す。判定の注意点は次の 3 つ。
     - (a) 失敗の証跡が err.log でなく stdout 側にしかない job がある (`API Error` 等)。err.log が 0 バイトでも `.out` の増分を必ず見る
     - (b) exit code の意味を log の文言から決めない。`retrospective-cron-run.sh` は exit 1 でも `(124 = timeout)` と出力する。log の start 行と done 行の時刻差を取り、timeout 上限 (`max 1800s` 等) と比べれば判別できる。数十秒で終わっていれば timeout ではなく起動失敗なので、prompt / flag / 認証の順に疑う
     - (c) offset が使えず全文を読んだときは、log 内の数値や識別子を実データと突き合わせて発生時期を特定してから修正に入る
   - **メモリ掃除の判断待ち**: `memory-clean.log` に `判断待ち` があれば `/memory-clean --apply` の Stage 2 手順をそのまま実行し、salvage 候補の AskUserQuestion をこの command 内で聞く
   - **棚卸し候補**: 直近の `maintenance-cron-*.log` の `=== /general-clean all` 区間を読み、候補表 (削除候補 N 件) があれば表をそのまま提示し、user が「消していい」と言った scope だけ `/general-clean <scope> --apply` (worktree → git rm → 索引更新 → sync) を実行する。候補 0 件や区間が無い週は何も出さない
   - **NG 語の未登録候補**: `~/.claude/logs/ng-candidates.log` の `new` 行の語のうち `guidelines/writing/NG-DICTIONARY.md` に無いものを列挙し、`references/on-demand-rules/ng-word-register.md` の手順で登録するかを user に確かめる。log が無い週や候補 0 件なら何も出さない
   - 残件が 0 で staged も 0 なら「残件なし」と報告して終了する
1. **staged 収集**: `<repo-root>/memory/sleep-proposals-*.md` を Glob する (`.rejected.md` / `.adopted.md` は除く)。0 件なら Step 0 の結果だけ報告して終了する
2. **warn flag 確認**: `~/.claude/sleep/tracked-change-warn` があれば内容 (`<date> <発生源>`、mine / retrospective) と該当 log (`sleep-cron.log` / `retrospective-cron.log`)・隔離 dir (`~/.claude/sleep/quarantine-<date>-<発生源>/`) を先に報告し、flag を削除する
3. **proposal 表示 + triage**: staged file を Read する。`<repo-root>/memory/sleep-triage-log.md` の当日行を確認し、`auto-adopt` 済の `P<n>` は表示から除く (gate C が commit 済のため再 triage しない)。残存する proposal (`### P<n>:` で `hold` / `reject`、または gate C 未着手の Tier 3) ごとに 5 field を提示し、AskUserQuestion で adopt / hold / reject を 1 回 1 問で聞く
4. **adopt の適用** (type 別に既存 flow へ委譲し、新規 logic を作成しない):

| Type | 適用経路 |
|---|---|
| new-skill | skills/ に SKILL.md を直接作成し、`skill-lint` と sync で反映する |
| skill-edit / hook / command | Target を full Read し、diff 提示と承認後に Edit する。skill は `skill-lint` を実行し、`./claude-code/sync.sh to-local --yes` で反映する |
| claude-md | `/promote` と同 protocol で適用する (full Read + diff 提示 + 承認後 Edit + sync) |
| cursor | `cursor/` 配下を edit する (`cursor/MAINTENANCE.md` 参照) |
| remove | `/general-clean <scope> --apply` (参照 grep → `git rm` → 索引更新 → sync) を user 承認後に実行する |
| audit | 提示された update (`npm audit fix` 等) を user 承認後に実行し、`npm test` で回帰確認して commit する |

5. **台帳更新**: `<repo-root>/memory/pending-improvements.md` を read-modify-write する (`/retrospective` Phase 5 と同形式)。adopt は completed へ、reject は理由付きで remaining へ書き、hold は pending に保持する
   - あわせて `<repo-root>/memory/sleep-triage-log.md` に 1 提案 1 行 (`<date> | P<n> <title> | adopt|hold|reject | 理由 1 行`) を追記する。health report の adopt 率はこの log が分母分子になる。NO-PROPOSAL の staged file は提案ではないので log に行を書かず、`.rejected.md` への rename だけで済ませる (reject 扱いにすると採用率の分母だけが増える)
   - 同型の reject 理由が 2 回目になったら、`templates/sleep-mine-prompt.md.template` の Constraints に禁止 1 行を還元する (Compounding Engineering)
6. **file 後始末**: 処理し終えた staged file を rename する。adopt が 1 件以上あれば `.adopted.md`、全 reject なら `.rejected.md` にする。hold が残存する file は rename せず翌朝に再提示する (staged 3 件滞留で夜間 mine は止まる)

## Guard

- この command が扱うのは Tier 3 (hook/remove/new-skill/CLAUDE*.md、常に人手判断) と gate C が HOLD/REJECT にした残りのみ。gate C が `auto-adopt` 済とログした proposal を再 Edit しない
- hook 編集を adopt する場合は `references/on-demand-rules/measure-before-hook-change.md` の baseline 計測を先に行う
- config 書き換えは必ず diff 提示と user 承認を経る。無承認 Edit は禁止する

## Related

- `references/sleep-cron-spec.md` — pipeline 全体の仕様 canonical (cron / gate / exit code / triage)
- `scripts/sleep-self-review.sh` — gate C。Tier 1/2 + audit の self-review + auto-adopt 実装
- `scripts/sleep-harvest.sh` — Mine 入力の集計
- `commands/retrospective.md` — 週次の深掘り版。sleep は日次の pre-computed 提案の処理
- `references/loop-engineering.md` — MVL / compounding path (state → memory → skill)
- `references/on-demand-rules/toolchain-lifecycle.md` — 増設 gate と生存条件。remove 提案の adopt はこの `git rm` 手順に従う
