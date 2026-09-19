---
allowed-tools: Read, Glob, Grep, Bash, Task
argument-hint: "<task> [--consult]"
description: 難所だけ Fable 5 に委譲する節約 escalation。日常 session は sonnet / auto 前提
---

## 目的

session default を Sonnet 5 / auto に下げたまま、Fable 5 が必要な難所だけ **model override 付き agent 委譲**で使う。fable の消費を「難所 × 1 委譲」に限定する。

## Step 1: Fable 要否判定 (required)

fable 送り条件 (いずれか 1 つで送る):

1. 設計判断で trade-off が深い (可逆性が低い / 複数案が拮抗)
2. RCA・難 bug で仮説が 2 回外れた (thinking-principles Section 7 の前提組み替え局面)
3. security 修正 / 破壊的変更 / migration の方針決め
4. 複数 subsystem にわたる整合性判断

**該当しない task は fable に送らない**。現 model のまま実行し、判定を 1 行だけ chat に出す。却下後に user が「fable で」と再指示したら判定を skip して送る (再指示は異議 signal)。

## Step 2: 委譲 (fable 送り確定時)

| Task 性質 | 発火 |
|---|---|
| 実装込み | `Task(developer-agent, model: fable)` |
| 読み取り分析 / RCA のみ | `Task(explore-agent, model: fable)` |

- `model` param は agent frontmatter より優先されるため、Sonnet 固定 agent でもそのまま使える
- prompt contract は `/mode` と同じ: 対象 file path 明示 / やること 1-3 行 / 完了条件 (lint・test 等の verdict)
- explore-agent へ送るときは **explore contract 必須** (canonical: `agents/explore-agent.md` 「Prompt contract」、欠落は hook が block): `run_id` / `scope_id` / `expected_count: 1` / `target` (worktree_path・branch・head full SHA) / `anchor_evidence` (path:line か path#symbol を 1-3 件) / `paths` / `questions` / `excludes` / `stop_when` / `budget_class` を prompt 先頭に記載する (`--consult` 発火時も同様)
- **agent は親 transcript を読めない**。ここまでの調査結果・確定済み判断・却下済み案を prompt に書き切る (fable に再調査させるのは節約の逆)
- **1 task = 1 agent。fan-out しない** (fable 並列は節約と矛盾)
- 委譲後は trailer (`status` / `confidence` / `issues_blocking`) を読み、fact-check 1 点を parent 側 (安い model) で行う

## `--consult` (advisor mode)

実装は現 model のまま、**方針の妥当性だけ** fable に諮る (`Task(explore-agent, model: fable)`、read-only で十分)。`references/model-selection.md`「Verifier consult の 2 タイミング」に対応:

- (a) approach 確定前 — 最初の write の前に実装方針を諮る
- (b) done 宣言前 — test 結果が発生した後に done 判定を諮る

prompt に「助言のみ / code を作成しない / 出力は要点 10 行以内」を明記する (advisor の出力を限定しても品質劣化しない測定知見に準拠)。出力を限定した 1 call で済むため、`--consult` は Step 1 判定を skip してそのまま発火してよい。

### advisor mode を default 発火する pattern

相談 turn では最初の write の前に `--consult` で fable に諮る (先行 Read で文脈を集めてから prompt に書き切る)。trigger:

- rule や定義 file (`commands/` `skills/` `rules/` `hooks/`) を変更する前の方針相談
- user が「大事」「重要」「慎重に」を明示した task
- 既決判断への異議で、対象が Step 1 条件か定義 file に該当するとき (yes/no 質問は inline 回答)

advisor 出力は助言 text のみで、実装は現 model の inline が担う (Step 2 の実装込み委譲には進めない)。

## 運用前提

- 日常 session は `/model` → sonnet or auto にしておく (settings.json.template の default 変更は別判断)
- main session が既に fable のときは委譲せず inline 実行し、その旨を 1 行報告する (fable → fable 委譲は overhead 純増)

## Anti-pattern (即 reject)

- 判定を skip して全 task を fable に送る (節約の逆)
- fable agent への並列 fan-out
- 単発の軽 task (typo / 1 symbol fix / lint) を fable に送る

## 参照

- `references/model-selection.md` (model 選定 canonical / advisor pattern)
- `commands/mode.md` (N 判定 + prompt contract)
- `commands/goal.md` (`/goal --checker-model fable` で fable を objective gate の checker に指名できる)
- `commands/deep.md` (思考の深掘りは `/deep`。`--consult` の 10 行制限を外した長めの問い立てを担う)
