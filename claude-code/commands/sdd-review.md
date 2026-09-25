---
allowed-tools: Read, Glob, Grep, Bash, Task, Skill, Agent, mcp__serena__*
description: /sdd-implement で実装した Phase 1 つの diff に、既存の /review (comprehensive-review) を Phase の scope と作業計画書固有の観点で当てる。/sdd-implement の出口
argument-hint: "<作業計画書 path> [--phase <n>] [--fix] [--member] [--panel]"
---

# /sdd-review - Phase の diff を review する

> **Goal**: `/sdd-implement` が実装した Phase n の diff に既存の `/review` を当て、user が `/explain` で差分を理解する前に修正するものを確定させる。汎用の 12 観点に、作業計画書とPhase 詳細設計から取った Phase 固有の観点を加える。

**Position**: `/sdd-implement` (Phase 実装) の次に **`/sdd-review`** を当てる。修正するものが無くなったら `/explain` (code の説明) から PR と次 Phase へ進む

## When to use (棲み分け)

| Command | Use |
|---|---|
| `/sdd-review <path> --phase <n>` | Phase n の diff を、作業計画書の scope と Phase 固有の観点付きで review する (この command) |
| `/review` | 任意の diff の汎用 review。この command が内部で呼ぶ |
| `/review-member` | team の過去の指摘傾向で確認する。`--member` のとき内部で呼ぶ |
| `/sdd-converge <path>` | 全 Phase 実装後に、設計と code 全体の差を確かめる |

「Phase をレビューして」「作業計画書と突き合わせてレビュー」で発火する。

## Step 1: 入力

1. 引数の path を作業計画書として Read する。無ければ同 session で `/sdd-implement` が最後に扱った path を使い、それも無ければ 1 問で聞く
2. `--phase` 省略時は、現在の branch 名を作業計画書の各 PR の `branch:` 行と照合して Phase を特定する。一致が無ければ `/sdd-implement` が最後に完了報告した Phase を採り、Phase 名を 1 行宣言する
3. Phase の 対象 / 対象外 / 実装への指針 を読む。同じ dir にPhase 詳細設計 `<作業計画書の basename>-phase<n>.md` があれば、変更対象 file と契約の節を読む (冒頭に「無効」とあるものは使わない)
4. diff の base を決める。作業計画書の `依存:` にある前 Phase の branch が未 merge ならその branch、merge 済みか依存なしなら default branch とし、`git merge-base` の結果を 1 行記載する。diff が空なら「review 対象なし」で終える

## Step 2: review を当てる

既存の `/review` の手順をそのまま使い、この command では独自の rule を定義しない。

- 委譲・Stage A / B の self-review・repo rule の解決・noise 基準・出力形式は `commands/review.md` の「Delegation & Self-Review」「Review Policy & Scope」「Output Format」に従う (`comprehensive-review` skill を `reviewer-agent` へ委譲する)
- scope は Step 1 の base からの diff に限る
- 追加 lens として次の 4 つを `comprehensive-review` の args に渡す
  - **Phase の scope**: 対象外に列挙された file / 振る舞いへの変更 (Critical)、Phase 詳細設計の変更対象 file に無い変更と、Phase の目的に不要な rename / format / 周辺の書き直し (Warning)
  - **`/sdd-implement` Step 3.5 の点検表 a-f**: 参照 0 件の symbol の先出し / magic number の出所 / validation と保存の対称性 / Non-Goals の残存 comment / NULL 条件と代入の対応 / 同種 field の取りこぼし
  - **repo 規範**: Phase の「実装への指針」に列挙された rule file (絶対 path)
  - **命名**: diff で新設した関数名と変数名を `guidelines/common/code-quality-design.md` 「Naming Criteria」の 3 基準と「Naming Shape」、対象言語の `guidelines/languages/<言語>.md` 「Naming Conventions」で点検する (repo に無い語 / 難しい英語 / 削れる語 / 名前の形。Warning)
- `--panel` は `/review --panel` の lens 構成で並列に実行する
- `--member` のときは同じ diff に `review-member` skill を並列で当て、`comprehensive-review` と同じ `file:line` の指摘は 1 件にまとめる

## Step 3: 出力

`/review` の Output Format で記載し、冒頭に次の 2 行を置く。

```
sdd-review: Phase <n> / 全 <N> — <Phase 名>
base: <ref> (<理由>)
```

末尾に Next を 1 行記載する。

## Step 4: 修正 (`--fix`)

- `/review` の Fix loop をそのまま使う (developer-agent へ委譲し、再 review で回帰を確かめる。停止条件も同じ)
- 修正してよいのは Phase の対象 file と、その test だけとする。対象外の file を変更する修正は行わず報告する
- 指摘の原因が作業計画書 / Phase 詳細設計 / Design Doc の側にあると判断したものは修正せず、`/sdd-phase-design` か `/sdd-design --update` へ戻す。どちらが正かは user が決める

## Next の判定

| 状態 | Next |
|---|---|
| Critical / Warning が 0 件 | `/explain` (Phase の差分を理解してから PR へ) |
| Critical / Warning がある | `/sdd-review <path> --phase <n> --fix` |
| 作業計画書 / Design Doc 側の誤りが疑われる | `/sdd-phase-design` か `/sdd-design --update` |

## 禁止事項

- `--fix` 以外では code を編集しない
- 作業計画書 / Phase 詳細設計 / Design Doc を編集しない。不足は `--update` の経路へ戻す
- 次 Phase へ自動で進まない

## Related

- `commands/sdd-implement.md` — この command の入力を作る。Step 3.5 の点検表を追加 lens として使う
- `commands/review.md` / `skills/comprehensive-review/SKILL.md` — review の手順の正本
- `skills/review-member/SKILL.md` — `--member` の lens
- `references/design-phase-flow.md` — 遷移全体
