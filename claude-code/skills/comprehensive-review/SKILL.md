---
allowed-tools: Bash, Glob, Grep, Read, mcp__serena__*
name: comprehensive-review
description: "12-perspective code review (arch/quality/security/test). /review 呼び出し時に使用。"
context: fork
disallowed-tools:
  - Write
  - Edit
  - MultiEdit
agent: reviewer-agent
requires-guidelines:
  - common
  - clean-architecture
  - ddd
parameters:
  focus:
    type: enum
    values: [all, architecture, quality, readability, security, docs, test-coverage, root-cause, logging, writing, silent-failure, type-design, db-concurrency, diff-hygiene]
    default: all
    description: Review focus perspective
---

# comprehensive-review — 12-Perspective Code Review (+ always-on regression-guard)

## Perspectives

Details: `skills/comprehensive-review/references/` 配下 (`review-criteria.md` / `diff-hygiene.md` / `layer-boundaries.md` / `test-quality.md` / `writing-docs.md` / `silent-failure.md` / `type-design.md` / `db-concurrency.md`) を後述 Conditional Reference Loading に従い読み込む。Noise discard / P2/P3 downgrade: `references/on-demand-rules/review-noise-discard.md`. Self-Review Gate C (`/flow`): `references/parallel-self-review.md` — fires via `reviewer-agent` 12-lens parallel.

| Perspective | Description |
|---|---|
| **architecture** | Layer knowledge boundaries (what each layer may and must not know), dependency direction, where a decision belongs, the same rule implemented in two layers, CQRS lane separation |
| **quality** | Language/FW best practice, local idioms, code smell, performance, type safety |
| **readability / logging** | Naming, cognitive complexity, consistency; log level appropriateness, structured logs |
| **security** | Authn/authz, injection, secrets, tenant/data isolation, unsafe logging |
| **docs / test-coverage / writing** | Doc quality, test adequacy & quality, human-facing doc quality |
| **root-cause** | Permanent fix vs workaround, recurrence patterns |
| **silent-failure / type-design** | Error swallowing, empty catch; type-encoded invariants, avoid enum abuse |
| **db-concurrency** | InnoDB deadlock / gap lock / FOR UPDATE+INSERT / ODKU / external I/O in TX / missing retry |
| **diff-hygiene** | 差分全体の意味性、同義 rename / 有用 comment 削除 / minimal-diff 違反の検出 (単一 file の Edit では見えない、diff 全体で判定) |

**regression-guard (常時適用)**: 今は壊れていない箇所への劣化を検出する観点。focus 指定によらず `references/review-criteria.md` 「Regression Guard」を当てる (diff 内で完結せず grep と呼び出し元探索が必要な項目を含む。例: 対の非対称 / 単位混在 / 共有 default の波及 / 根拠が記録されない magic number / 実装と同じ思い込みの test)。

## Effort-Linked Mode (`${CLAUDE_EFFORT}`)

| Effort | Critical Threshold | History | Perspectives |
|--------|---------------|---------|---------|
| `low` | 90+ | Skip | Skip writing/type-design/docs |
| `medium` (default) | 80+ | Past 90 days | All 12 |
| `high` | 70+ | Full history | + design tradeoff, dependencies |

## Execution Flow

> Steps 1-4: `reviewer-agent` (model: agent frontmatter canonical). Step 4.5 output → parent for Stage B aggregation.

**Step -1 (Noise)**: diff/code/docs only. Unverified → "hypothesis:". No nitpicks, no unsolicited TODO creation. **Review prose** は `guidelines/writing/PRINCIPLES.md`「文章生成の不変条件」に従い、実測にない影響・件数・原因を作らず finding と根拠だけ伝える。
**Step 0 (History)**: Read `.claude/review-history.jsonl`. Same `file:line±3` + `focus` 3+ times → prefix `🔁 Repeated Finding (Nth time)`. Absent → `history: unavailable`.

### Step 1: Changed File Analysis

`git diff --name-only`. **Serena**: impact → `find_referencing_symbols` / impl → `find_implementations` / types → `get_diagnostics_for_file` / structure → `get_symbols_overview`. Default lenses: `quality` / `architecture` / `root-cause` / `security`. Caller args で渡された追加観点 (例: `/review --fable` の fable 観点) も lens に加え、findings に観点名を明記する。

| Condition | Add Perspective |
|------|---------|
| All files ∈ {`.md`, `.json`, `.yaml`, `.yml`, `.txt`, `.toml`, VERSION-like} | Limit to `docs` / `writing` / `readability` / `root-cause`; skip others ("docs-only mode") |
| Test file (`*_test.*`, `*.spec.*`) | `docs` + `test-coverage` (matcher の緩さと test data は `test-quality.md`) |
| Logic change (non-test) | `test-coverage` + `silent-failure` |
| Type def change (`*.d.ts`, `types/*`, struct/interface added) | `type-design` |
| SQL/ORM change | `db-concurrency` |
| Mixed / uncertain | Full 12 perspectives |

### Step 2: Static Analysis

TypeScript: `npm run lint && npx tsc --noEmit` / Go: `golangci-lint run && go vet ./...`。exit 127 → `static-analysis: skipped` / exit 0/1 → incorporate / other non-zero → Warning。

### Step 3: Cleanup Enforcement

Unused imports/vars/functions, backward compat remnants, progress comments。**未使用判定の除外**: interface 実装 / framework hook / generated code は grep で呼び出し元を数えられないため対象外とし、件数を数える前にその symbol が interface 定義に現れないか確認する (実測 repo の `pkg/entity` は export method 812 のうち 495 が gorp hook で参照 grep が常に 0 件になる)。
**Bash 固有チェック**: `cmd || true` + `$? -ne 0`, duplicate `[[ -z "$x" ]]` after assign, `&&` chains under `set -e` with unreachable failure-path.

### Step 4 + 4.5: Scoring & Self-Filter

**Coverage-first**: Steps 1-3 は coverage 優先で候補を全部挙げる (低 severity / 不確実でも confidence + severity 付きで出す)。severity / confidence による filter は本 Step と Stage A/B のみで行う。
Score 0-100: **80+** (low 90+, high 70+) → Critical / **50-79** → Warning / **<25** → Discard。Validate each candidate:

| Check | Pass condition |
|---|---|
| Evidence | Anchored to diff/code/docs/tests/tool output |
| Scope / Overreach | Tied to user request / code contract / changed behavior; no invented problem statement or requirement |
| Actionability / Severity | Author can fix in this change; severity matches real impact and confidence |
| Style / Overprescription | Backed by documented guideline (not taste); a reasonable engineer calls it a defect, not another valid alternative |

Discard: "cleaner / more elegant" / "consider X" without defect. Zero findings valid — never invent. **Step 5-6**: Append confirmed Critical/Warning (confidence ≥25) to `.claude/review-history.jsonl`.

## Output Format

confidence score と discard 件数は内部判定にだけ使い、user が求めない限り出力しない。出力は確認できた finding、根拠、必要な修正に限定する。

```
## Review Results
### Critical
- [security] SQL injection (src/api/user.ts:120) — 根拠: user input を文字列連結して query を組み立てている。修正: placeholder を使う (🔁 Repeated Finding: 対象が Step 0 の再出現 3+ 回条件を満たすとき、この見出し語を prefix する)
### Warning
- [quality] 独自 sort callback が不要 (pkg/sort.go:15) — 根拠: 要素型は ordered。修正: slices.Sort を使う
```

Zero findings → `確認できた指摘はありません。` Tags: `must`=Critical / `imo`,`nits`=Warning / `q`=question.

## Writing Enforcement (always-on)

**Comment check (毎 review 必須、diff 種別問わず)**: diff に comment 行 (`// ` `# ` `-- ` `/* ` `<!-- `) の追加/変更が 1 つでもあれば、canonical `guidelines/writing/code-comment.md` を Read して監査カテゴリ table で分類する (削除カテゴリ + AI marker 該当 → Warning 以上、diff 0 なら skip)。
**Prose check (writing/docs/prompt diff 時)**: `guidelines/writing/PRINCIPLES.md` / `prompt-engineering.md` / `long-form-doc.md` を Step 4.5 で追加適用する (confidence-80 filter は両 check に適用)。comment 品質の詳細規範 (Before/After rewrite) は `code-comment` skill に委譲する (trigger 重複を避ける)。

## Conditional Reference Loading

**常時 (focus 不問)**: `review-criteria.md` (「Regression Guard」含む全 focus 共通の判定表) + `diff-hygiene.md` (diff 全体で判定する観点)。どちらも対象言語に依らない。

**条件付き** (残り 6 file、Step 1 の条件表がその perspective を追加したときだけ読む):

| file | 読む条件 |
|---|---|
| `test-quality.md` | test file の変更時 |
| `layer-boundaries.md` | architecture lens 稼働時 (docs-only mode 以外の全 code diff。default lens なので実質常時) |
| `writing-docs.md` | docs / writing |
| `silent-failure.md` | logic change (`db-concurrency` 併用時も) |
| `type-design.md` | type def change |
| `db-concurrency.md` | SQL/ORM change |

`Mixed / uncertain` は 8 file 全部読む。単一 focus 指定時は該当 file + 常時 2 file。load は **Step 1 の直後、Step 2 の前** (読む file は Step 1 の file 分析で決まる)。

**Multi-lens panel (`/review --panel` only)**: `--panel` passes `reviewer-agent` × 3 (style / security / test-coverage) verdicts as pre-Step-1 input (lens count canonical: `commands/review.md` 「Panel modes」). Each verdict passes Stage A 7-point filter. Duplicates (same file:line, different lens, same root cause) → merge to 1. Merged list flows through Step 4.5 → Stage A → Stage B.
