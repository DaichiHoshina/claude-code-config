---
allowed-tools: Read, Glob, Grep, Bash, Task, Skill
description: 入力の状態から深掘り mode (詰問 / 発散 / 妥当性判定 / review 観点) を判定し、fable で思考を深掘りする router
argument-hint: "<topic | file | 案の要約> [--mode grill|diverge|consult|review]"
---

## /deep - Fable 思考深掘り router

入力の状態から深掘り mode を 1 つ採用し、fable に委譲して思考を掘る。mode 選定を user に聞かず、判定根拠 1 行を chat に記載して即実行する (`rules/minimize-questions.md`)。全 mode read-only で、実装や file 編集はしない。

### Step 1: mode 判定

| 入力の状態 | mode | 実体 |
|---|---|---|
| 設計案 / plan が既にある | `grill` | 詰問 6 観点 (`commands/grill.md`) の生成と回答仕分けを fable が担う |
| 選択肢がまだない / 問いが曖昧 | `diverge` | 案 3-5 個の発散 + 推奨 1 つ + 却下理由を fable が出す |
| 方針の yes/no 妥当性だけ知りたい | `consult` | `commands/fable.md` `--consult` へそのまま委譲する (10 行制限あり) |
| working diff があり review 目的 | `review` | `/review --fable --fix` へ誘導してこの command は終了する |

`--mode` 指定時は判定を skip してその mode で実行する。file path / issue URL が入力なら実物を Read してから判定する。複数の状態に該当するときは `review` > `grill` > `diverge` > `consult` の順で先勝ちさせる。対話で往復しながら発散したいなら `/brainstorm`、1 発の案出しで足りるなら diverge を使う。

### Step 2: fable 委譲

`Task(explore-agent, model: fable)` を read-only で 1 回だけ発火する。prompt contract:

- **explore contract 必須** (`agents/explore-agent.md` 「Prompt contract」、hook が block する): `run_id` / `scope_id` / `paths` / `questions` / `excludes` / `stop_when` に加え、target block (`worktree_path` / `branch` / `head` = full SHA、`git rev-parse` で取得) と `anchor_evidence` (path:line か path#symbol を 1-3 件) を prompt 先頭に記載する。単発委譲のため `expected_count: 1` 固定 (案の数ではなく fan-out の agent 数)、`budget_class` は `focused|standard|broad` の enum から採用する (diverge は `standard` default)
- 対象の要約 / 確定済み判断 / 却下済み案 / 関連 file の抜粋を prompt に書き切る (agent は親 transcript を読めない)
- 「repo を Read / Grep して主張と実物を突き合わせる」を明記する (机上の詰問を防ぐ、`/review --fable` の実在確認と同 pattern)
- 深掘り用途のため `--consult` の 10 行制限は適用せず、上限 40 行で依頼する (consult mode のみ 10 行のまま)。深掘りは問いの列挙が成果物の本体なので、この上限は圧縮対象にしない
- 「助言と問いのみ / code を作成しない / 未決定点には推奨を 1 つずつ添える」を明記する
- main session が既に fable のときは委譲せず inline で掘り、その旨を 1 行報告する
- 委譲が fail / timeout したら retry せず、現 model の inline 深掘りに切替えて 1 行報告する

### Step 3: 出力

- `grill`: 詰問と現状回答 / 未決定点表 / 総評 (`commands/grill.md` の Output format)
- `diverge`: 案の一覧 + 推奨 1 つ + 却下理由 (追わない案を長く並べない)
- `consult`: fable の助言をそのまま報告する
- 末尾に次の一手 (`/plan` / `/brainstorm` / 手動修正 等) を 1 行だけ添える

## Anti-pattern (即 reject)

- 軽 task (typo / 1 symbol fix / 手順が自明な作業) を深掘りに送る。`/fable` Step 1 判定と同じ基準で却下する
- fable agent への並列 fan-out
- 深掘り結果を経て実装まで続ける。実装は `/plan` → `/dev` 等の通常経路に戻す

## 参照

- `commands/fable.md` (委譲の節約原則 / `--consult` の実体)
- `commands/grill.md` (詰問 6 観点 / Output format)
- `commands/review.md` 「Fable lens」 (review mode の実体)
- 却下済み代替案: router を作らず 3 command を直接使い分ける運用は、trigger 語の記憶負荷が残存するため却下した

ARGUMENTS: $ARGUMENTS
