---
allowed-tools: Read, Glob, Grep, Bash, Task, Skill, Agent, AskUserQuestion, mcp__serena__*, mcp__context7__*
description: Full code review (`comprehensive-review` skill + optional external reviewers). --fix で修正 loop、--push で PR まで、--fable で diff 固有観点を前段 consult
argument-hint: "[scope] [--fix] [--push] [--fable] [--dry-run]"
---

# /review - Full Code Review

> Runs 12-perspective review (+ always-on regression-guard) via `comprehensive-review` skill. `--panel`/`--multi` parallelizes reviewers.
> Noise filter policy: `references/on-demand-rules/review-noise-discard.md` / Finding constraints: `skills/comprehensive-review/SKILL.md` Step -1

## Delegation & Self-Review (required, 2 stages)

**Delegation**: Delegate `comprehensive-review` skill to `reviewer-agent` (model: agent frontmatter canonical) via Task. Delegation prompt: `"Run comprehensive-review skill on current diff. focus=${focus}. repo_rules=<Review Policy & Scope で解決した絶対 path 一覧>. Return raw findings list with confidence scores."` parent runs Stage A (per-finding); Stage B aggregate delegates back to reviewer-agent.

**Always** run the following 2-stage self-review before outputting `/review` results. Applied uniformly to all modes (`--dry-run` / `--codex` / `--multi` / `--panel` / `--adversarial`) — cannot skip.

### Stage A: Finding Self-Review Gate (per-finding)

Skill Step 4.5 has already run the 7-angle primary eval (Evidence / Scope / Overreach / Actionability / Severity / Style / Overprescription). **Parent runs a safety-net re-eval on the same 7 angles**. Prioritize propagation incompleteness / cross-ref desync. Do not include judgment logs in output. Adversarial mode loosens Evidence/Scope (design-challenge nature); Stage B dedup stays as usual.

### Stage B: Result Self-Review Pass (overall) — delegate to reviewer-agent

Pass Stage A findings as a JSON list to `reviewer-agent` as its Stage B aggregate mode (a fresh-context aggregate suppresses post-impl bias). Delegate: `Task(subagent_type: "reviewer-agent")`. Prompt: `"Stage B aggregate review. Input: Stage A filtered findings (JSON list). Apply: (1) phase consolidation, (2) detail-level alignment, (3) convention alignment, (4) Zero-phase valid (no padding). Return: confirmed findings as JSON {p0/p1/p2}. Filter only — no new findings. Noise policy: references/on-demand-rules/review-noise-discard.md (discard confidence <80 / style nitpick / hypothetical edge / scope-out)."`

Prompt 中の適用ルール:

| # | ルール | 意味 |
|---|---|---|
| 1 | phase consolidation | 同種指摘を phase 単位でまとめる |
| 2 | detail-level alignment | 指摘の詳細度をそろえる |
| 3 | convention alignment | repo 規約に沿っているか確認する |
| 4 | Zero-phase valid (no padding) | 指摘 0 件を正当な結果として扱い、無理に水増ししない |

Parent handles only Stage A and passes the Stage B result to the `--fix` loop Step 3. Do not emit judgment logs to the plan file / chat; show only the Stage B result.

## PR-scoped Memory (read → append)

PR 対象 (URL / 番号引数、`gh pr view` で取れる状態) のときだけ、`references/review-pr-memory.md` の手順で per-angle status を Read → Append する。local diff review では skip する。

## Step 0: Auto-infer Mode (no flags)

No flags on launch → present recommended mode, execute after user confirm (heavy modes must not auto-run without consent).

| Situation | Recommend |
|-----------|-----------|
| 1-15 files | default (auto-run) |
| 16+ OR diff has `interface`/`type`/`class` | `--panel` (ask confirm) |
| PR arg present + base is main/master | `--multi` (ask confirm) |
| arg has "design"/"architecture"/"tradeoff" | `--adversarial` (ask confirm) |

material: `git diff --shortstat` / `gh pr diff <PR>` / `gh pr view <PR> --json baseRefName` / `$ARGUMENTS` grep.

## Arguments & Modes

| Argument | Behavior |
|----------|----------|
| none | review local diff |
| URL/number | `gh pr diff` / `glab mr diff` |
| `--focus=<angle>` | narrow to 1 of the 12 perspectives (see skill.md) |
| `--no-difit` | suppress difit (local only) |
| `--full` | guideline を全載せしてから review する (言語 full + DDD / CA、条件付きで CQRS + 領域 memory の引き当て)。手順は `references/review-commands.md` 「Full guideline load」。`ddd` `ca` `観点全部で` 等を引数に含む依頼はこれに当たる |
| `--plan <path>` | Also cross-check that the implementation aligns with the plan / design doc. When the doc has an acceptance-criteria table, output a table `受け入れ条件 (文の引用) / 実装で満たしたか / test の有無 / 根拠 (file:line)` before the findings, and report unmet rows as P1 |
| `--fix` | review 後に developer-agent へ fix を委譲し、再 review で回帰確認する (下記 Fix loop) |
| `--push` | `--fix` を含み、収束後に `/git-push --pr` へ続ける (旧 `/review-fix-push`) |
| `--fable` | review 前に fable へ diff 固有の観点を諮り、追加 lens として注入する (旧 `/review-fix-fable`)。`--fix` と併用可 |

| Mode | Delegate | PR | Cost |
|--------|--------|----|--------|
| (default) | `comprehensive-review` skill | any | mid |
| `--panel` | 3-lens parallel fan-out (style/security/test-coverage) → integrated by `comprehensive-review` | any | mid×3 |
| `--codex` | `comprehensive-review` + codex plugin parallel, common findings = Critical | any | mid |
| `--adversarial` | codex plugin `adversarial-review` (plugin required) | any | mid |
| `--deep` | **disabled** (pr-review-toolkit disabled to reduce first-ctx, 2026-07-23). Alternative: `--panel` (3-lens parallel) + `--codex` (different model, different perspective) | — | — |
| `--multi` | `comprehensive-review` + codex + code-review + coderabbit parallel → auto-post to PR | required | max |

cloud large: use built-in `/code-review ultra` (below; `/ultrareview` is a deprecated alias).

### CI Integration

`/code-review ultra` is only a user-triggered + billed interactive slash command; there is no non-interactive / CI-launched CLI subcommand form (the `claude ultrareview` CLI subcommand was removed in 2.1.223).

## Codex Invocation (--codex / --adversarial)

Via plugin: `node "${CODEX_PLUGIN_ROOT}/scripts/codex-companion.mjs" <review|adversarial-review> --wait`. `${CODEX_PLUGIN_ROOT}` = `ls -1d ~/.claude/plugins/cache/openai-codex/codex/* | tail -1`. Fallback if missing: `--codex` uses `codex review` direct; adversarial is plugin-only.

## Flow details (Adversarial / Multi)

- **Adversarial**: challenge design correctness / assumptions / real-world failure points. `--base <ref>` / `--scope auto|working-tree|branch` / `--background` → `/codex:status` `/codex:result <id>`. Use for: design review / pre-PR self-challenge. Use `/review` default for implementation defects
- **Multi**: PR required. 4 methods in parallel ((a) `comprehensive-review` skill / (b) codex plugin / (c) `/code-review:code-review` / (d) `coderabbit:code-review`) → merge + dedup → `gh pr comment` auto-post. Aggregation: 3+ agree = Critical confirmed. Use for: pre-merge / security patch; not recommended for daily use

## Output Format

Same format as skill.md. Labels: `🔴 Critical (fix required, confidence ≥80)` / `🟡 Warning (improve, confidence 25-79)` / `Total: Critical N / Warning N`. Fallback: zero findings → `Critical/Warning 0, Total no findings (N files)` / Multi partial fail → `### Degrade factors`.

## Critical/Warning ↔ P0/P1

`/review` solo = `Critical→P0` / `Warning→P1` / else `P2/P3`. Team path = report only. Details: [`reviewer-agent.md`](../agents/reviewer-agent.md).

## Review Policy & Scope

- **policy**: evidence-first (false positives are review debt), diff-only, Critical → Warning, 12 parallel
- **scope**: changed files (git diff). exclude: auto-gen / vendor / node_modules / lock
- **repo rule (always-on)**: delegation 前に repo rule を次の手順で解決する。
  1. `~/.claude/scripts/resolve-repo-rules.sh <変更 file>...` (PR は `gh pr diff <n> --name-only`、local は `git diff --name-only`) で glob が当たる repo rule の絶対 path を取得する
  2. `--review-docs` は別途単独で呼ぶ (**同じ呼び出しに並べると review 定義だけが返り、変更 file 側の glob 解決が行われない**)
  3. 両方の結果を全件 Read してから、その path 一覧を delegation prompt の `repo_rules=` に渡す (auto-load は自分が Read した file にしか反応せず、subagent の context には届かない)
  4. exit 3 なら「manifest 未設定のため repo rule 読込を skip」と 1 行報告する

  当たった分だけを読み、rule dir 全件の bulk load はしない。schema: `references/on-demand-rules/repo-rules-manifest.md`
- **comment + writing check (always-on)**: if the diff adds/changes comment lines, always run the `guidelines/writing/code-comment.md` audit-category check; if the diff has prose (md/docs), always run the `guidelines/writing/PRINCIPLES.md` check (canonical: `skills/comprehensive-review/SKILL.md` 「Writing Enforcement」). Skippable only when comment / prose diff is 0
- **difit**: local only, background after review (require `npm i -g difit`, suppress: `--no-difit`)

## Fix loop (--fix / --push)

review → fix → **再 review で回帰確認** → (`--push` なら) push の 1 command。`/flow` は新規実装から PR までを担い、`--fix` は「書き終えた code の review-loop 保証」に限る。

| Step | 内容 |
|---|---|
| 1 | Stage A / B を経た findings を user に見せてから fix に入る。Critical 0 & Warning 0 なら fix を skip する |
| 2 | Critical / Warning をすべて `Task(developer-agent)` へ委譲する (parent inline 実装は禁止)。fix 後に lint / type-check を自動実行する |
| 3 | 回帰 loop: `initial_base = HEAD` を取り、iteration ごとに `Skill("comprehensive-review", args="--diff-base=<prev_iter_commit>")` + Self-Review 2 段を実行する。新 Critical 0 で収束、Warning が初回より増えていれば warn して先へ進む。2 回目以降は前 iteration の範囲を skip する |
| 4 | `--push` のときだけ `/git-push --pr` (force push 禁止) |

loop 停止条件: 新 Critical 0 (収束) / iteration ≥ 3 (状況を報告して続行を聞く) / 同じ finding が 2 連続 (手動 fix を依頼)。進捗は `Iteration 1/3: Critical 3 → 0 / Warning 5 → 2 (converged)` の形で出す。`--dry-run` は review のみで fix / push しない。

## Fable lens (--fable)

Fable 5 に「この diff に固有の review 観点」を先に諮り、追加 lens として review に注入する。固定 3 lens の `--panel` とは補完関係で、汎用の網羅を厚くしたいなら panel を使う。

- Step 0: `git status` / `git diff --stat` と変更意図を 5 行に要約する。diff が空なら「review 対象なし」で終了する
- Step 1: `Task(explore-agent, model: fable)` を read-only で 1 回だけ発火する (並列 fan-out 禁止)。explore contract 必須 (`agents/explore-agent.md` 「Prompt contract」)。Step 0 の要約 + `--stat` 全体 + 変更行数上位 5 file の代表 hunk を prompt に書き切り、「diff 固有の観点を 5-8 個、一般論 lens は除外、参照 guideline path は Grep で実在確認、助言のみ 10 行以内」と依頼する。main session が既に fable なら inline で列挙する。fail / timeout は retry せず default lens で続行し 1 行報告する
- Step 2: 観点に添えられた doc を on-demand で Read し、`Skill("comprehensive-review")` の args に観点を渡す。報告に「観点 → 読んだ doc」と観点ごとの verdict を保持する
- 観点 consult が汎用 checklist の再生成になるなら `--fable` を付けずに実行する

## Panel modes (--panel / --verifier-panel)

Fan-out `reviewer-agent` × N in parallel; each lens blind to others. Source: [claudefa.st — Multi-Lens Panel Review](https://claudefa.st/blog/guide/agents/sub-agent-best-practices). `--panel` = 3 fixed lens (style/security/test-coverage) integrated by `comp-review` skill. `--verifier-panel=N` = N lens (correctness/consistency/boundary, fresh context, majority-confirmed only promoted). Orthogonal to `--multi` (engine-diverse).

### Lens config

| mode | lens | focus | ignores |
|---|---|---|---|
| `--panel` | style | naming / readability / convention / cognitive complexity | logic / security |
| `--panel` | security | authn/authz / injection / secrets / data boundary / unsafe logging | style / coverage |
| `--panel` | test-coverage | test adequacy / missing edge cases / silent-failure paths | style / security |

`--verifier-panel` の 3 lens (correctness / consistency / boundary) の定義と delegation prompt: `agents/reviewer-agent.md` `## Lens-specific mode` (canonical、ここに重複させない).

**Common rules**: pass diff + assigned focus only / fire N lens in **1 message bundle** (`Task(reviewer-agent)` × N, peak_concurrency=N, sequential forbidden) / aggregation by `file:line` key (2/N+ → max severity → Stage A / 1/N → P3 silent / all miss → clean) / **default OFF**, limited to large-PR pre-merge final check / `--verifier-panel` token cost = N×, `--multi --verifier-panel=3` = 12× cost so pick one / apply CLAUDE.md `1 dev = 1 file` + parent oversight.

## Next

review の末尾に 1 行記載する (`--fix` / `--push` 指定時は loop が続きを担うので記載しない): Critical / Warning あり → `Next: /review --fix` / 自分の PR に未対応 comment あり → `Next: /self-review-fix` / findings 0 → `Next: /git-push --pr`。
