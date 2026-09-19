# agent-output-schema

Agent が返す Markdown 末尾 trailer の canonical 定義。
Team flow / 非 Team 全 agent に適用。

## Overview

Agent (Manager / Developer / Reviewer 等) は、出力 Markdown の末尾に `---` 区切りの YAML-like trailer を必ず付与する。
Parent はこの trailer を parse して `status` を判定し、次 gate を制御する。
Trailer が欠落した場合は `status: failure` と同等に扱う (`hook-payload-map.md` 「Subagent failure 検知 設計方針」 参照)。

適用範囲: `agent-team-contract.md` Section 5 で定義する全 agent output (Developer / Manager / Reviewer 等)。

## Trailer format

Markdown 本文の末尾、**区切り行 `---` の後に** YAML-like block を置く。
field 順序は以下のとおり固定する (変更禁止)。

```
---
run_id: <string>
scope_id: <string>
generation: <non-negative integer>
status: <enum>
failure_scope: <task_local | shared_precondition | infrastructure | null>
precondition_id: <string | null>
error_fingerprint: <string | null>
confidence: <0-100>
issues_blocking: [<string>, ...]
digest: <compact string>
---
```

- `---` 行は区切り専用。コメントや他 field を同行に混在させない
- block は `---` で閉じる (trailing `---` 必須)
- field は上記 10 個のみ。追加 field は禁止

## Field spec

**run_id** — 1 回の fan-out 全体で不変の ID。retry / resume でも変更しない。

**scope_id** — bounded investigation / task の論理 scope ID。担当 agent が変わっても同じ scope の retry では変更しない。

**generation** — scope の初回実行を `0` とする非負整数。retry / resume ごとに 1 増やす。同じ `run_id` + `scope_id` の新しい generation は新規 scope ではなく resume として扱う。

**status** — `agent-team-contract.md` Section 5 と完全一致の enum (この順序で固定):

| 値 | 意味 |
|----|------|
| `success` | DoD を全て満たし完了 |
| `partial` | 一部完了。`issues_blocking` に blocker を列挙済み |
| `failure` | タスク失敗。retry 2 回消費 + root cause 特定済み |
| `dep_unresolved` | 外部依存 (他 Dev 成果物 / 環境) が未解決で続行不能 |
| `blocked` | user 判断が必要な decision fork で停止 (subagent silent-fail guard 発火)。parent は user に escalate する |

`partial` は free pass ではない。具体的 blocker 行が `issues_blocking` に必須。blocker なしの `partial` は parent が `failure` 扱いで reject する。

**failure_scope** — `success` の場合は `null`。それ以外は次の enum:

| 値 | 意味 |
|----|------|
| `task_local` | 当該 `scope_id` だけの失敗。parent は失敗 scope だけを次 generation で retry し、success scope は再実行しない |
| `shared_precondition` | run 全体が依存する前提の失敗。parent は run 全体を停止し、同じ `precondition_id` を 1 回だけ再検証する。全 scope の一括 resume は禁止 |
| `infrastructure` | runner / network / tool 等、task 内容以外の基盤障害。success scope は再実行せず、未完了 scope の扱いを parent が決める |

`shared_precondition` の再検証後も、parent は成功済み scope を再実行しない。前提が回復した場合は未完了 scope を個別に次 generation へ進め、回復しない場合は run を失敗として停止する。

**precondition_id** — `failure_scope: shared_precondition` の場合に必須の安定 ID。それ以外は `null`。

**error_fingerprint** — non-success の場合に必須。変動する時刻・一時 path を除いた、同じ原因を同定できる短い fingerprint。`success` では `null`。

**confidence** — `0`〜`100` の整数。運用閾値は **80** (`references/on-demand-rules/review-noise-discard.md` の confidence-80 filter と整合)。80 未満の場合は `issues_blocking` に不確実要素を記載する。

**issues_blocking** — 未解決 blocker を string 配列で列挙。解決済みなら `[]`。粒度: 1 要素 = 1 blocker (root cause 1 行)。推測は書かず、確認済み事実のみ記載。

**digest** — parent が追加要約なしで利用できる compact digest。結果、主要 evidence、未解決事項だけを 1〜3 文で記載する。

## Delivery contract

Team transport が利用可能な場合、agent は completion report 全体を `SendMessage` で parent に **1 回だけ**送る。送信成功後に normal text で同じ内容を再要約しない。送信失敗時だけ、同一 report を normal text fallback として 1 回返す。

## Evidence label (VERIFIED / REASONED / ASSUMED)

report 本文中の claim (個別の主張。測定値 / file 変更 / 重要な結論) 単位に、検証根拠ラベルを付ける。

| label | 意味 |
|----|------|
| `VERIFIED` | command 実行・test・file 読取で直接確認した |
| `REASONED` | 確認済み事実からの推論で導いた |
| `ASSUMED` | 未確認の仮定に基づく |

`confidence` は report 全体の確度を示す数値で、evidence label は claim 単位の検証根拠を示す。役割が違うため両者は併存し、evidence label が trailer field を置き換えることはない。

出力例:

```yaml
claims:
  - claim: "hook latency は 120ms 前後で baseline と同等"
    evidence: VERIFIED   # hook-bench.sh を実行して確認した
  - claim: "regression は import 追加が原因"
    evidence: REASONED   # 計測差分と diff から推論した
  - claim: "CI 環境でも同じ latency になる"
    evidence: ASSUMED    # CI では未計測
```

## Examples

### Template

```
---
run_id: <string>
scope_id: <string>
generation: <non-negative integer>
status: success | partial | failure | dep_unresolved | blocked
failure_scope: task_local | shared_precondition | infrastructure | null
precondition_id: <string | null>
error_fingerprint: <string | null>
confidence: 0-100
issues_blocking: []
digest: "<1-3 sentences>"
---
```

### 良い例 (success)

```
---
run_id: flow-20260806-001
scope_id: task-001
generation: 0
status: success
failure_scope: null
precondition_id: null
error_fingerprint: null
confidence: 95
issues_blocking: []
digest: "対象 scope の実装と指定 verification が成功した。未解決事項なし。"
---
```

### 悪い例 (status 欠落)

```
confidence: 90
issues_blocking: []
```

→ `status` field がないため parent は `failure` と判定する。`---` 区切りも欠落している点に注意。

## Inlining policy

各 agent file は trailer example を inline 必須とする。agent が references/ を読めない context で spawn されても trailer format に従えるようにするため。semantics / enum / evidence label の定義はこの file が canonical で、inline example とこの file の enum が食い違った場合はこの file が勝つ。

## Silent-fail guard

`AskUserQuestion` and permission-gated ops are auto-denied in subagent context with no error signal. On any decision fork requiring user approval or judgment outside task spec (incl. destructive Bash / writes outside `touchable_files`): stop, set `status: blocked`, list it in `issues_blocking[]` — never guess, skip, or attempt the op. Verify the actual file change before reporting success (silent-win prevention).

各 agent はこの節を「Canonical: `references/agent-output-schema.md` 「Silent-fail guard」」1 行で参照する (developer-agent.md はこの canonical の記述元のため全文を保持する)。

## Cross-references

- `agent-team-contract.md` Section 5 — status enum 定義 (canonical source)
- `hook-payload-map.md` 「Subagent failure 検知 設計方針」 — trailer 欠落時の failure 判定方針
