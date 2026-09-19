---
allowed-tools: Read, Glob, Grep, Edit, MultiEdit, Write, Bash, Task, TaskCreate, TaskUpdate, TaskList, mcp__serena__*, mcp__context7__*
description: 作業計画書 (SPEC) の Phase を 1 つ実装し、完了報告と /explain への handoff で閉じる。/spec-plan の出口、/dev --plan --phase の spec 系向け入口
argument-hint: "<作業計画書 path> [--phase <n>]"
---

# /spec-dev - 作業計画書の Phase を 1 つ実装する

> **Goal**: `/spec-plan` が書いた作業計画書の Phase n だけを実装し、完了条件を command で確かめ、user が `/explain` で差分を理解してから PR と次 Phase へ進める状態で止める。
>
> **語の対応**: ここで SPEC と呼ぶのは作業計画書 (Phase = PR) を指す。一般にいう Spec (誰がどの状況で何を達成するかと、受け入れ条件) は Design Doc に記載する。

**Position**: `/design-doc` (仕様) → `/spec-plan` (Phase = PR 分割) → `/spec-detail` (Phase n の実装方法) → **`/spec-dev`** (Phase 実装) → `/explain` (差分理解) → PR → 次 Phase

## When to use (棲み分け)

| Command | Use |
|---|---|
| `/spec-dev <path> --phase <n>` | 作業計画書の Phase n を実装する (この command) |
| `/spec-detail <path> --phase <n>` | 実装の前に Phase n の実装形を決める。単純な Phase では省略され、その場合はこの command へ直接入る |
| `/dev --plan <file>` | `/plan` の plan file (ai-tools 用) を実装する。作業計画書も同じ intake で受けて `/explain` を Next に出すが、spec 系の流れでは入口名を合わせるためこの command を使う |
| `/dev <task>` | 計画書のない単発実装 |
| `/flow` | PO / Manager / Dev の hierarchy が必要な規模 |

実体は `/dev --plan <path> --phase <n>` (`commands/dev.md` 「Plan intake」) と同じで、この command は入口と出口を spec 系に合わせるだけになる。実装の判断 (delegation / inline / worktree) は `/dev` の規範に従い、ここで別 rule を保持しない。

## Step 1: 入力

1. 引数の path を作業計画書として Read する。無ければ同 session で `/spec-plan` が最後に出した path を使う。それも無ければ `~/.claude/plans/` と、repo の 1 つ上の dir にある `plans/<issue 番号>/` および `docs/plans/` から、末尾に `/spec-dev` の前提行が書かれた最新 file を候補にして path を 1 行宣言し、候補が無いときだけ 1 問で path を聞く。`plans/` は issue 番号の dir が 1 段深いので `ls -t <parent>/plans/*/*.md` で 1 段下まで探索し、そこに `grep -l "/spec-dev"` を組み合わせる。worktree では元 repo の 1 つ上の dir を基準にする
2. `--phase` 省略時は、計画書の Phase 見出しのうち完了報告がまだ無い最初の Phase を採用し、採用した Phase 名を 1 行宣言する
2.5. Phase の詳細設計 (`/spec-detail` が作成した `<SPEC の basename>-phase<n>.md`) を SPEC と同じ dir で探し、あれば Read して実装形 (interface / method / 契約 / SQL 方針 / TX / テスト観点 / 変更対象 file) をそのまま採用する。冒頭に「無効」と記載された詳細設計は、`/spec-plan --update` が SPEC を更新した後の古い契約なので、file が無いときと同じに扱う。無いときは `/spec-detail` Step 0 の省略判定をこの Phase に当て直す。当たるなら SPEC の 対象 / 完了条件 から実装形を自分で決めてよい。**当たらないなら実装へ進まず**、詳細設計の path を渡すか `/spec-detail` を実行するよう 1 行報告して止める (`/spec-detail` が `--out` で別 dir へ出力した詳細設計は同 dir の検索では見つからない。見つからないことを省略判定と同じに扱うと、決めた実装形を無視して実装が進む)。詳細設計と実物が食い違ったら実装を進めず、食い違いを 1 行報告して `/spec-detail` へ戻す
3. Phase の「実装への指針」に列挙された repo 規範 (rule file) を着手前に Read し、命名 / 型 / 層 / error / test の制約を採用する。列挙が無い計画書なら `~/.claude/scripts/resolve-repo-rules.sh <対象 file>...` で取得して同じ形で報告に記載する (exit 3 なら skip。詳細は `references/on-demand-rules/repo-rules-manifest.md`)。developer-agent へ委譲するときは、読んだ rule の **file 名一覧を絶対 path で prompt に記載する** (harness の auto-load は subagent に届かないため、渡さないと規範が適用されない)。Phase の 対象 / 対象外 / 完了条件 を scope として採用する。対象外に列挙された file には触らず、変更する必要が発生したら止まって報告する
3.5. Phase の対象領域 (ディレクトリ名や table 名から取る。例: `oripa` / `payment` / `shipment`) を語にして memory index を grep し、hit した file を Read する。作業の計画書が `/spec-plan` Step 2.6 で file 名を列挙していればそれを Read し、列挙が無ければ `grep -niE '<領域語>' "$(bash ~/.claude/scripts/memory-save-helper.sh resolve-dir)/MEMORY.md"` で引き当てる (読む上限 3 file、`**地図**` と `**入口**` の行を優先)。既知の trade-off をここで確認しないと、判断済みの箇所を作り直す実装になる。developer-agent へ委譲するときは rule と同じく絶対 path を prompt に記載する
4. worktree と branch は同名にし、命名は `~/.claude/scripts/resolve-repo-rules.sh --get branch_pattern` が返す型に従う (置き場所は `--get worktree_root`)。branch_pattern が返る repo では、repo 名も内容の slug も付けない (user 決定 2026-09-06)。exit 3 の repo にこの決定を当てず、既存 branch 名の付け方を `git branch -a` で 1 度確かめて合わせる (issue 番号を保持しない repo では内容の slug が既存の付け方になる)。PR 番号は作業計画書の PR 分割計画の番号 (2a のような枝番もそのまま) で、be / fe は PR を出す repo の側で決める。既存の worktree が別名なら `git worktree move` と `git branch -m` で一致させてから着手する
5. 着手前に Phase の「merge 後にできること」と完了条件を 3 行で chat に写し、user が読んで理解している前提を作る (AI の出力は下書きで、レビューに出すのは user が説明できる code だけ)

## Step 2: 実装

- `/dev --plan <path> --phase <n>` の Plan intake と同じ手順で進める (再分析と事前確認は skip)。実行 mode は CLAUDE.md の Auto-Delegation 表に従い、独立 scope が 1 つ (1 Phase を 1 人で積む) なら inline、2 つ以上のときだけ developer-agent へ fan-out する
- 計画書のタスクが Phase の scope を超える (参照が 10 file を超える rename / nullable 化 等) と分かったら、そのタスクは実装せず「別 Phase へ送る」と報告に書き、SPEC は `/spec-plan --update` で直す (この command は SPEC を編集しない)
- 計画書と実物の drift (symbol 名が違う / 対象外や未列挙の file を変更する必要が発生した) を見つけたら 1 行で報告して再分析に戻る。対象に列挙された file が実物に無いときは drift でなく新規作成として進め、作成する旨を 1 行で宣言する
- 破壊的操作 (削除 / migration / force) を含む Phase は、計画書があっても実行前に確認する。ただし migration を local の DB に当てるだけなら確認は不要で、共有 DB を使わない手順を採用する
- migration の Phase では、先に local DB の migrate version を見る。branch の最新 migration より先に進んでいる (他 branch の table を含む) なら共有 DB には当てず、使い捨て DB (例: `<db 名>_<branch slug>`) を作って断面の migration を 1 から当てる。使い捨て DB は Phase の integration test が終わったら DROP し、報告に保持した / 消したを記載する
- 完了条件の DB 確認 command (`~/.claude/scripts/resolve-repo-rules.sh --get commands.db_describe` で取得する) が空を返したら、docker exec の `DESCRIBE` と information_schema (UNIQUE / FK の DELETE_RULE) で代替し、動作確認手順に代替 command を併記する

## Step 3: 完了条件の実行

- Phase の完了条件に書かれた command (test 名 / lint / API response) を fresh に実行し、出力と照合する。skip した条件は skip と書く
- 変更した symbol 名と file 名で `tests/` を grep し、hit した test file を全部実行する。共有 fixture (testdata の yml 等) を変えたときは、同じ fixture dir を読む package の test も全部実行する
- mutation check の復元は、壊す前の file を別へコピーしておくか逆置換で行う。`git checkout -- <file>` は未 commit の修正まで消すので、commit 済みの file にだけ使う
- mutation check の fixture は、壊したい条件 (ORDER BY / WHERE の 1 句) が確実に偽になる data を先に決めて作る
- 既存 field の型変更 (nullable 化 等) の更新は、`go vet` / `go build` の error 位置を起点にした script で機械的に直し、手で 1 か所ずつ直さない (2026-09-06 に 13 file 117 か所)
- Phase ごとに worktree を切り替えるので、着手時に Serena の active project を新 worktree に切り替える (旧 worktree に bind されたままだと symbol 編集ができない)
- 実装中に既存挙動を変える判断 (error 応答の形、共有 usecase 経由の別入口への制約) が必要になったら、その場で決めずに `/design-doc --update` で DD へ記載してから続ける。実装で決めた設計は、過去の振り返りで手戻りの主因になった
- 既存 test の FAIL が並列干渉 (単独実行で PASS) なら、test 名と単独実行の結果を報告に記載して無関係と判定し、「全部 green」とは書かない

## Step 3.5: self-review (完了報告の前)

diff は reviewer が 1 本で採否を決められる状態にする (`commands/spec-plan.md` Step 3 「分割の優先順位」)。Phase の目的の達成に不要な変更を同じ diff に残存させない。対象になるのは symbol の rename、format のそろえ直し、周辺 code の書き直しの 3 つとする。残存していたら別 commit へ分け、分けられないものは PR 本文に理由を 1 行記載する。

完了条件が成立したら、`/review --plan <SPEC path>` を diff に当て、needs-fix を修正してから完了報告に進む。spec 系で繰り返し発生する指摘は次の項目で、review を待たず自分で先に点検する。

| # | 点検項目 | 判定基準 |
|---|---|---|
| a | 参照 0 件の symbol の先出し | production の参照が 0 件の symbol を先出ししていない (使う Phase の PR へ移動するか、PR 本文に使う Phase を記載する) |
| b | magic number の出所 | MySQL の 1062 等に出所の comment か定数がある (隣接 file の書き方に合わせる) |
| c | validation と保存の対称性 | validation で分岐した条件と保存の条件が対称になっている (validation が HasSize のときだけ見る値を、保存側が無条件に記載していない。Data Schema の「〜なら NULL」は保存側で保証する) |
| d | Non-Goals の残存 comment | Non-Goals で受け入れた制約が code の該当箇所に 1 行 comment で残存している |
| e | NULL 条件と代入の対応 | Data Schema の各列の NULL 条件 (「サイズ不要なら NULL」等) と usecase の代入が列ごとに対応している (入力の条件で validation を分岐させた値を、保存側が無条件に記載していない) |
| f | 同種 field の取りこぼし | repo 規範を当てて型を修正したときは、同じ struct 内の同種 field を全部 grep して取りこぼしが無い |

## Step 4: 完了報告と handoff

完了報告は次の 4 行で閉じる。

```
Phase <n> <Phase 名>: 完了 / 一部完了 (残り: ...)
満たした条件: <条件の文の引用> / 残り: <同>   (計画書が担当条件を保持するときだけ)
検証: <実行した command と結果 1 行>
Next: /explain                              (この Phase の差分を理解してから PR と次 Phase へ)
```

- `/explain` の後の PR 作成は `/git-push --pr`、次 Phase は `/spec-dev <path> --phase <n+1>` を user が発火する。この command は次 Phase に自動で進まない
- 完了報告の直後に、PR を出す前の checkpoint を user 向けに列挙する (user が確認する。AI は代行しない)
  - test 抜きの変更行数が 400 行以下 (`git diff --stat <base> -- ':!*_test.go' ':!**/__tests__/**'` の合計)
  - AI が書いた comment が 0 件 (全部書き直したか消した)
  - 参考にした既存実装を 1 つ以上 PR 本文に記載する
  - `/explain` の説明と自分の理解が食い違った箇所が 0 件 (食い違いは PR 前に解消する)
  - PR 説明文を自分の言葉で書き直した。diff の各変更について「なぜ必要か」を一言で言える
  - 本文の節を repo の PR template に揃え、レビュー観点 / 影響範囲 / PR の順番を該当節へ記載した。計画書の PR 行に「既存挙動: 変わらない」とあれば title に repo の印 (`[確認不要]` 等) を付けた (`guidelines/writing/pr-description.md` 「節への配置」)
- 作業計画書自体は編集しない。Phase の切り方に問題があれば `/spec-plan` で直す

## Guard

- 対象外の file を変更しない。変更する必要が発生したら止まって報告する (計画書の scope が SoT)
- 対象 file の内側でも、詳細設計に記載が無い変更を追加しない。comment の書き換え / rename / 周辺の整理が該当する。実装後に `git diff --stat <base>..HEAD` を取り、詳細設計の「変更対象 file」節と件数・file 名を突き合わせる (2026-09-18 実踏: 詳細設計に無い comment の書き換え 3 行が混入し、設計と実装の照合で齟齬として検出された)
- 完了条件を command で確かめる前に「完了」と書かない
- Phase を 2 つ以上まとめて実装しない (1 Phase = 1 PR を守らない)
- 詳細設計が見つからない (「無効」と書かれた file を含む) まま、省略判定にも当たらない Phase を実装しない (Step 2.5)

## Related

- `commands/spec-plan.md` — 入力の作業計画書を作成する
- `commands/spec-detail.md` — Phase の実装形を決める。この command の入力になる
- `commands/dev.md` 「Plan intake」 — 実装手順の canonical
- `commands/explain.md` — 完了後の差分説明
- `references/design-phase-flow.md` — 遷移全体
