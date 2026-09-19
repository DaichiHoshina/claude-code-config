---
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, Task, AskUserQuestion, Skill, TaskCreate, TaskUpdate, TaskList, TaskGet, mcp__serena__*
description: orchestration を主体とした workflow — parent 主導の並列 fan-out (orchestrate + parallel を強制)
argument-hint: "[task description]"
---

## /flow - Orchestration-first workflow

**Core**: Orchestration-only command. Forces worktree parallel fan-out under parent direction; minimizing makespan is the top KPI. File-conflict tasks fall back via sequential downgrade.

> Use: `/flow` (orchestrated parallel) / `/flow --auto` (fully autonomous) / `/dev` (single-agent) / `/review --push` (review-loop only)

## Step -1: Mode auto-check (skip on `--parallel` explicit worktree 数 / 「team で」等 team 明示発話)

`commands/plan.md` Step 2 の条件表を現 scope (file count via Glob、独立性) に当てる。1-2 files / single task / cross-file coupling に当たり、PO/Manager overhead を回収できないと判定したら、この command を進めず `/dev <task>` を同じ task 文で再発火して stop する (判定根拠 1 行を先に出す、`rules/minimize-questions.md` 推奨即決 default)。3+ files 独立 / team 明示発話ならそのまま Task type detection へ進む。

## Task type detection

Match keywords top-down, **first hit wins**. If mixed, ask user. `*impl*` = expanded by PO decision.

- **Team**: `Task(po-agent)` → `Task(manager-agent)` → `Task(developer-agent)×N` → aggregate → `Task(reviewer-agent)` → P0 re-fix 1 loop
- **Direct**: `/dev` (review = `/review` = `comprehensive-review` skill). Sub-agents cannot spawn; parent launches each tier.

| # | Keywords | Task | Workflow |
|---|-----------|--------|------------|
| 0 | 相談, ブレスト, brainstorm | Design consultation | /brainstorm → /prd → /plan |
| 1 | 緊急, hotfix, 本番, critical | Urgent | /diagnose → handoff artifact → stop (fresh `/dev --handoff`) |
| 1.5 | インシデント, 障害, エラーログ貼付 | Incident | /diagnose → handoff artifact → stop (fresh `/dev --handoff`) |
| 2 | 根本原因, rca, 再発防止 | RCA | /diagnose → Skill(root-cause) → handoff artifact → stop (fresh `/dev --handoff`) |
| 3 | 修正, fix, バグ, 不具合 | Bug fix | /diagnose → handoff artifact → stop (fresh `/dev --handoff`) |
| 4 | リファクタ, refactor, 構造改善 | Refactor | /plan → *impl* → /lint-test → /test → /review → /git-push --pr |
| 5 | ドキュメント, docs, README | Docs | /docs → /review → /git-push --pr |
| 6 | テスト作成, test追加, spec | Testing | /test → /review → /lint-test → /git-push --pr |
| 7 | 追加, 実装, 新規, 機能, add | New feature | /prd → /plan → *impl* → /test → /review → /lint-test → /git-push --pr |
| 8 | データ分析, analysis, SQL | Analysis | *impl* → /docs → /git-push --pr |
| 9 | インフラ, terraform, k8s, IaC | Infrastructure | /plan → *impl* → /lint-test → /git-push --pr |
| 10 | 調査のみ, 診断, troubleshoot | Investigation (read-only) | /diagnose → /docs |
| 11 | その他 | New feature (default) | |

Boundary: "fix from error log"=1.5 / "bug root cause"=2 / "feature improvement"=7 (struct only=4) / "investigate & fix error"=3.

## Investigation fresh-session boundary

`/diagnose` / root-cause analysis / repo investigation の後に実装が続く場合、調査と実装は同じ `/flow` run で連結しない。context 使用率でなく semantic phase の hard boundary として扱う。investigation が発生しない simple plan / implementation workflow は従来どおり継続する。

手順 (canonical: `references/investigation-session-contract.md`):

1. investigation 完了後、`~/.claude/templates/investigation-handoff.md.template` から absolute path の handoff artifact を作り、evidence・決定事項・実装 scope・検証方法・repo root・full HEAD・`source_session` (SessionStart が注入した `current_session_id` の実値) を保存する
2. blocker と placeholder を解消し、state を `READY_FOR_IMPLEMENTATION` にする
3. contract の `Validator command rule` に従って source-mode validator を実行する (mode = `source`)
4. artifact の `next_command` (`/dev --handoff <absolute-handoff-path>`) を fresh session 用に出力し、source session の `/flow` を停止する

この boundary では `*impl*`、`--auto` の自動継続、source session からの `/plan --go` を実行しない。`/compact` は investigation phase 内の圧縮に限り、fresh session の代替にしない。artifact が `PREFLIGHT` / `INVESTIGATING`、`UNRESOLVED_BLOCKER` を含む、または検証失敗なら ready にせず、欠落・blocker を報告して停止する。

## Options

```text
--parallel  (alias of plain `/flow`; parallel is already the default, so behavior is identical to no flag)
--auto
--sequential  (opt-out: only when parent judges parallelism physically impossible; PO/Manager always required)
--multi-review  (step 8: 12-lens split fan-out forced. `--auto` auto-ON)
--until-gate-green "<check-cmd>" [--max-iter <n>]  (step 9 P0 loop: switch stop-condition to objective gate. default max-iter=3. Ralph Wiggum guard; see `references/loop-engineering.md`)
```

**Default = orchestrate + parallel forced ON**. Plain `/flow` fires pre-delegation (N calc / target / verify / DoD) + worktree parallel fan-out. Add `--auto` for fully autonomous mode (skip confirms + auto push). `--sequential` emergency fallback only when file conflicts make parallelism physically impossible.

## Orchestration (forced)

Always force parent-direction mode. Pre-delegation 4 steps are **internal**; user sees 2 lines only (formula trace + fan-out declaration). Detailed echo goes into subagent prompt literals — no chat output.

After completion, **fire N tool_use in 1 message** (1 message per Agent N times = sequential chaining — forbidden). Spec: `references/orchestrate-mode.md` / `references/PARALLEL-PATTERNS.md`.

Formula trace echo: `formula: N=<N_chosen> / sum_T_i=<sum>s / LPT+ovh=<expected_parallel>s / PASS|FAIL (basis=<T_i_basis>)` / `fan-out: N=<n>, targets=<file count>`. Detail: `references/flow-orchestration.md`

## Parallel (forced)

Physically parallelizes via worktree isolation. Parallelism eval = Manager forced / worktree proposal = PO forced / worktree creation = `--auto` は 4 skip conditions で auto、それ以外は user confirm / file conflict or `--sequential` → sequential downgrade。`--auto` skip 4 conditions / cleanup policy / sweet spot / hard rules は `references/PARALLEL-PATTERNS.md` canonical を参照する。

## --auto mode

`--auto`: skip AskUserQuestion + auto-adopt / `bypassPermissions` / always PR push / auto-fix lint 1× / `--multi-review` auto-ON. review-fix loop: post-impl `/review` → auto-fix until Critical 0 + Warning 0 (max 3×). Detail: `references/flow-orchestration.md`

**`--auto` skips confirmations / approvals / push prompts ONLY. It does NOT skip the hierarchy.** The `Task(po-agent)` → `Task(manager-agent)` → `Task(developer-agent)×N` chain is mandatory — autonomous means "no questions asked", not "no PO/Manager". Going straight to `developer-agent` (or inline implementation) without PO design judgment + Manager allocation is a spec violation. Only `--sequential` downgrades to single `/dev` (PO/Manager still run per step 2). Self-Review 3 gates (A/B/C) stay mandatory; canonical: `references/parallel-self-review.md`.

Natural language triggers: "全自動で" / "autoで" / "おまかせ" → `/flow --auto` (旧 `/flow-auto` はこの command に統合済)。

- `--auto` 小規模 guard: `next` 等で対象 item が 1-2 file / 1 観点の小規模と判定できる場合、3 段 hierarchy を起動せず `/dev` か inline に降格する。`/flow --auto` は独立 dev task が 2 つ以上あり並列化が必要な場合に限定する (1 行 fix に 3 agent を起動して過大 cost になった実績あり、2026-06)。

## Execution logic

1. **git status check** → WIP confirm → investigation が発生した run は Investigation fresh-session boundary を完了して stop、それ以外は step 2
2. **Pre-Manager downgrade**: `--sequential` explicit → single `/dev` (skip PO/Manager). Otherwise → step 3
3. **PO Agent (required)**: design judgment / scope split. Cannot skip
4. **Manager Agent (required)**: task split / file dedup / N calc + `formula_trace`
5. **Post-Manager downgrade**: `parallelism: 1` + `worktree_required: false` or file conflict → Dev×1 sequential
6. **Orchestration pre-delegation** (internal + echo 2 lines); `mkdir -p <impl_notes.dir>`
6.3. **PO Gate** (required). Parent re-spawns PO with Manager allocation → `verdict: pass | fail | modify`。`pass` → 6.5 / `modify` → Manager re-allocation (1 loop max, then escalate) / `fail` → stop + user escalation。criteria / `fix_request` schema / literal 検証は 「Self-Review」 参照。Canonical: `agents/po-agent.md`
6.5. **Gate A** (required; N≥2 only). FAIL → re-run Manager. PASS → step 7. criteria は 「Self-Review」 参照
7. **Parallel fan-out**: Fire `Task(developer-agent)×N` in 1 message (bundle required)
8. **Parallel integrate + review** (1 message): Manager integrate + `Task(reviewer-agent, --codex)`×1 (or Gate C on `--auto`/`--multi-review`). Canonical: `references/parallel-self-review.md` 「Gate C」
8.5. **Gate B** (required; N≥2). FAIL → force step 9. criteria は 「Self-Review」 参照
8.7. **Dev failure gate** (required; after step-8 aggregate). criteria は 「Self-Review」 参照
9. **P0 re-fix loop**: P0 → manager realloc → dev×M fix → reviewer re-verify (max 1 loop). **`--until-gate-green "<cmd>"`**: switches stop-condition to bash `<cmd>` exit 0 (max-iter default 3). Canonical: `references/loop-engineering.md`

Detail step prose: `references/flow-orchestration.md`

## Self-Review (required, 3 gates)

Parent gates mandatory. Canonical: `references/parallel-self-review.md`. Noise discard: `references/on-demand-rules/review-noise-discard.md`. **Parent responsibility**: no outsourcing to PO/Manager. PO Gate v2 fires pre-fan-out (cannot skip). Canonical: `references/retrospectives/2026-06-19_agent-oversight.md`

A/B mandatory on orchestration path; `--sequential` exempts A/B. `/dev --parallel` also exempts A/B (no PO/Manager orchestration). C: `--auto`/`--multi-review` only.

- **PO Gate v2** (step 6.3): 8 criteria — goal/constraints/priority/file_count/bundle_justification/scope/subagent_type/branch_cwd literal. `modify` → Manager re-allocation (max 1) with `fix_request` 3+1 field (modify_target / unchanged / reason / concrete_change); parent post-validation: `grep -F task.files[]` vs PO instruction literal; `fail` → stop + user escalation
- **Gate A** (step 6.5): 6 criteria — N consistency / formula PASS / file conflict / worktree applicability / T_i basis / bundle fire format. FAIL → re-run Manager (max 1); 2nd → `--sequential` downgrade
- **Gate B** (step 8.5): 4 criteria — cross-diff conflict / duplicate import / naming collision / propagation incompleteness. FAIL → force step 9 P0 loop (max 1)
- **Dev failure gate** (step 8.7): 1 criterion — any Dev `status != success`. FAIL → Manager re-allocation (max 1); 2nd → stop + user escalation
- **Gate C** (`--auto`/`--multi-review` only): 12-lens stage split (stage 1=7 agent / stage 2=6 agent). Default `/flow` uses `comprehensive-review` + codex 2-agent mode.

## Integration rules

Required: impl → /lint-test → /review → review-fix → /git-push. 2× fail same approach → `/clear` → re-organize.

**Code comment enforcement (always-on)**: 各 developer-agent の delegation prompt に canonical `guidelines/writing/code-comment.md` 準拠を明示する (hook 要約で判定、迷ったときのみ Read)。Self-Review Gate 5 (developer-agent.md) で comment 混入を目視確認する。

### Completion actions

- Save to auto-memory: `~/.claude/projects/<project>/memory/work-context-YYYYMMDD-{topic}.md`
- `--auto`: secret check → /git-push --pr → notify `[flow --auto] {topic} complete → PR created` (fail: `fail: {reason}` / lint 2×: `stop: lint-test 2× fail`)
- Normal: AskUserQuestion "push?"
- **/clear recommended (cache_read prevention)**: after /flow completes, propose `/clear` before next task (`--auto`: append `→ next task: start after /clear`)

## Auto-apply features

| Feature | Condition | Action |
|------|------|------|
| worktree isolation | Default forced; skip on `--sequential` / downgrade | `isolation: "worktree"` auto-create / cleanup |
| Post-impl verify | `--auto` complete | `/lint-test` |
| `IMPL_NOTES` | Team path (Dev via Task()) | Dev writes `dev-<task-id>.md` → Manager merges → parent persists `MERGED.md` under `~/.claude/plans/impl-notes/<run-dir>/`. `/git-push --pr` consumes for PR draft (`--no-impl-notes` to skip) |

worktree apply decision: `references/PARALLEL-PATTERNS.md#worktree-applicability-flow`.

ARGUMENTS: $ARGUMENTS
