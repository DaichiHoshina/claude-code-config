# Compounding Engineering Cycle

> Boris-style Compounding Engineering. Structurally fix recurring review findings to eliminate them permanently.

## Core Proposition

**"Same-location finding occurring N=3 consecutive commits = structural problem signal. Fix structurally via config (CLAUDE.md / skill / hook)."**

Manual fixes repeat the same mistake N times. One structural fix (hook, etc.) drops the count to 0 permanently. Investment 1, return N — compound relationship.

## Cycle: 4 Steps

### Step 1: Detect

Extract same file:line±3 + same focus findings from past review history (`.claude/review-history.jsonl` or commit series). Threshold:

| N | Judgment |
|---|----------|
| 1 | One-off, fix only |
| 2 | Watch, consider structural fix |
| 3+ | **Structural problem confirmed**, root-cause target |

`comprehensive-review` skill Step 0 auto-runs history cross-check. 3+ occurrences are highlighted as `🔁 Recurring finding (Nth time)`.

### Step 2: Structural Problem Assessment

Determine if the recurrence is structural:

| Signal | Structural problem likelihood |
|--------|------------------------------|
| Same location + same focus 3× | High |
| Same focus, different locations, frequent | Medium (guideline-side issue) |
| Same location, different focus | Low (location-specific) |

If structural → Step 3. Otherwise → standard fix.

### Step 3: Root-Cause Strategy (priority order)

| Priority | Strategy | Example |
|----------|----------|---------|
| 1 | **Hook auto-detection** | Writing self-check hook (pre-commit), PostToolUse format |
| 2 | **Skill rule addition** | Add NG examples to `comprehensive-review` writing perspective table |
| 3 | **CLAUDE.md / guidelines addition** | Document "X is prohibited" / "X is required" |
| 4 | **Auto-memory save** | Save successful pattern for reproduction |

Hook is highest priority: zero cognitive load for user/Claude, detects before commit. Skill / CLAUDE.md have load cost + interpretation variance.

**CLAUDE.md 自己約束の hook 昇格基準**: 「〜を避ける」型の自己約束を CLAUDE.md へ追加しても、1 週間 (または同種 block ≥50 件/週) で効果が現れなければ user-prompt-submit の additionalContext inject (`_inject_*_if_trigger` パターン) に昇格する。自己 restraint は反復タスクで破綻し、pre-tool-use の後段 block は retry loop で token と makespan を浪費する。生成前の文脈に置くのが構造解 (実例: commit-ng-pre-sweep `d921fc0`、追記当日 603 件 block → inject 化)。list は log / canonical file から動的抽出し literal 直書きしない。

### 規則の不足を見つけたときの振り分け (2026-09-06)

修正する前に「手順 / 判定 / 経緯 / repo 固有」のどれかを決める。手順なら本文に一般形で 1 文、機械で判定できる条件 (件数の一致・marker の残存) は script + bats、実踏の経緯は on-demand の episodes file (`references/on-demand-rules/*-episodes.md`)、repo 固有の判断 (命名・列の表現・一意性の範囲) は先例や repo rules を参照する手順にする。本文に日付付きの注記を追加しない。判定を script で実装するときは、根拠にした定義の文を引用して条件節 (「〜のとき」「〜を採ったとき」) があるか確かめ、あればその条件を script の分岐として記載する。条件節を省いた判定は、定義どおりに記載した成果物を必ず FAIL にする (2026-09-17 に `spec-gate.sh` の behavior 判定で実踏)。同じ症状に 2 回続けて同種の対処を当てたら、3 回目は対処を変える前に**症状そのものを実物で測る**。2026-09-17 に実踏した。図の表示が切れるという報告へ、向きの変更と label 20 文字と label 30 文字 + 分割を順に当てて 3 回とも症状が持続し、4 回目に表現形式ごと差し替えた。その後 Chrome で実測すると、超過した図は切断されずに縮小表示されていて、「切れる」は viewer 固有の挙動だった。幅の実測値は `137 × 段のノード数 + 19` (label が ID のとき) と単純な式になり、label の文字数から独立していた。1 回目の対処の前にこの 1 枚を測っていれば、4 回の変更のうち 3 回は不要だった。他 session や user から受け取った症状の記述を、そのまま原因の根拠として扱わない。1 日の修正が 10 commit を超えたら本文の最長行と日付注記の数を測り、肥大していれば分離を先に行う。

### Step 4: Measure Effectiveness

Verify same-type findings don't recur after fix:

- Short-term: Did hit count decrease in next 1-2 commits?
- Mid-term: Zero same-location findings for 1 week?
- Long-term: Same-type mistakes reduced in other files too (generalization)?

**規範 (guideline) の判定基準を追加したときの測り方**: 書いて終わりにせず、その規範が防ぎたい失敗の実物 (review で意味を問われた comment 等) と、同じ母集団で問題にならなかった対照を 1 file の fixture にまとめ、skill に「対象の節だけで判定」させて正解 key と突き合わせる。

- 再現率と誤検知率の両方を出す。片方だけで判断すると、陽性を全部検出するが対照の半数も要修正にする規範 (書き手に無視される) や、誤検知ゼロだが陽性を取りこぼす規範ができる
- sync 前の更新版 file を canonical として skill の引数で明示する (sync 済の旧版を読ませない)
- 「文全体から復元できるか」のような書き手側の主観判定は錯覚しやすい。判定基準は読み手の問いの形 (「X とは?」) から逆算して書く
- 2 周以上で改善が止まるか、境界例 1 件のための条件追加 (過適合) になったら止める (3 周が目安)。収束した実測値は規範の該当節に 1 句記載する

## Example (2026-04-29)

| commit | Phase | Finding | Response |
|--------|-------|---------|----------|
| `427733a` series | Detect | "最優先" evaluation word without evidence, 3 consecutive commits | Structural problem confirmed |
| `04503f5` | Root-cause | Added writing self-check to post-tool-use hook | Pre-commit detection via hook |
| `71f690f` | Reinforce | Consolidated NG dictionary SoT to `lib/writing-self-check.sh` | Prevented three-way drift |
| `a2bc297`–`61b27ef` | Measure + improve | Dogfood: hits 36→24 (33% reduction), 4 exclusions for false positive suppression | Productionized |

**Result**: Same-location "最優先" finding = 0 since `04503f5`. Investment 4 commits / return N (ongoing).

## Reproduction Steps

On discovering a new recurring finding:

1. Check history in `.claude/review-history.jsonl`; apply this cycle if 3+ occurrences
2. Plan implementation via priority order (hook → skill → guidelines → memory)
3. Design with `/plan`, optionally run through codex review
4. Implement → add unit tests → dogfood measurement → commit
5. Save to auto-memory as success pattern (reference for next similar problem)

## Case Studies

### awk regex bug immediate fix (2026-04-30)

While implementing context-aware logic in PR #12, broken awk regex parentheses caused over-exclusion of `例:` / `詳細:` / `参考:` single occurrences as false negatives. reviewer-agent detected with 3 evidence cases; 1-line regex fix + 3 bats negative cases added, root-cause in under 5 minutes. Short lead time from Critical detection to fix worked as compounding effect.

### Pass-by-coincidence test structural fix (2026-04-30)

In PR #11, 3 of 6 bats tests reconstructed behavior manually (mkdir/cp/ln) without calling the actual function — tests passed even with the implementation fully deleted. Rewrote 17 tests to fix. Established standard bats patterns:

- Call real functions with `run bash -c "source <lib> && <function> <args>"`
- Save PATH in `setup` as `ORIG_PATH="$PATH"`, restore in `teardown` with `export PATH="$ORIG_PATH"` (never `unset PATH`)
- Don't suppress status with `|| true`
- Prohibit two-outcome asserts (`status -eq 0 || status -eq 1`)

### Guideline self-check tuned with review-question fixture (2026-08-24)

code-comment.md に「状況を自作の名詞句に縮めない」節を追加した際、実 PR の review で意味を問われた comment 18 件と対照 8 件を fixture にして code-comment skill で 3 周採点した。1 周目 (名詞句単体で採点) は再現 16/16・誤検知 4/8、2 周目 (comment 全体で判定) は 11/16・1/8、3 周目 (対処側の自作ラベルも対象) で 15/16・1/8 に収束した (commit `3b88ff13` / `de097eac`)。

### spec 系 command の 3 層分離 (2026-09-06)

#30472 の再テストで不足を 1 件ずつ本文へ追加した結果、4 file で日付注記 28 か所、最長 1 行 2,620 文字になった。注記 32 件を `references/on-demand-rules/spec-flow-episodes.md` へ移動し、合計と表の行数の一致や未決事項の残存を `scripts/dd-gate.sh` / `spec-gate.sh` + bats 13 本にし、命名や列の表現は「repo の先例を数えて多数派を既定にする」Step に置き換えた。

## Memory write target

Write only to Claude Code auto-memory (`~/.claude/projects/.../memory/`). Writing to Serena `.serena/memories/` is forbidden to avoid dual management (decided 2026-06-10).

## Related

- `claude-code/CLAUDE.global.md` 「Compounding Engineering」 — core rule
- `claude-code/lib/writing-self-check.sh` — implementation SoT
- `claude-code/skills/comprehensive-review/SKILL.md` — `🔁 recurring finding` detection logic
- `claude-code/references/memory-usage.md` 「Recording targets」 — success pattern storage
- Reference: [howborisusesclaudecode.com](https://howborisusesclaudecode.com/)
