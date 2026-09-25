# Design Doc Template

12-section full template used by `/sdd-design --type full`. The default is the spec-type template (`design-doc-spec-template.md`).

## 12-section structure

```markdown
# Design Doc: [Title]

## 1. Overview
- What is being realized (1–2 lines)
- PRD / Spec link / reference
- Glossary: terms undefined elsewhere in the doc (only when the overview uses them)

## 2. Goals / Non-Goals
### Goals
- What to achieve
### Non-Goals
- What is out of scope (explicit scope boundary)
- Do not add a separate Scope section: in-scope goes to Goals, out-of-scope to Non-Goals

## 3. Background / Spec mapping
### 3.1 Background
- Current problem
- Why change is needed (Why, connection to PRD)
### 3.2 Acceptance criteria mapping
| Acceptance criterion (Spec) | Design response | Verification |
| --- | --- | --- |
| [expected behavior, quoted from the Spec] | [screen / API / data] | [pointer into 11.1] |
- Do not restate the Spec here. Map each criterion to the design that satisfies it
- The Verification column is an index only; the actual plan lives in 11.1

## 4. High-Level Design
- Overall structure (Mermaid arch diagram)
- Data flow (Mermaid sequence diagram)
- Responsibility boundary (roles between services/modules)

## 5. Detailed Design
### 5.1 Data model
- Table design / ER diagram (Mermaid)
- Indexes / constraints
### 5.2 API / Interface
- Endpoints / function signatures
- I/O (type definitions)
### 5.3 Processing flow
- Sequence / pseudo-code (within 5 lines)

## 6. Alternatives
- Other options considered (Option A/B/...)
- Why not adopted: name the acceptance criterion (3.2) or invariant (8.1) the option fails

## 7. Trade-offs
- What is gained / lost
- Numeric comparison (performance / cost / complexity)

## 8. Invariants / Failure Handling
### 8.1 Invariants
- Data consistency conditions that always hold
- Conditions to hold under concurrent execution / resend
- Conditions re-checked inside the write transaction
### 8.2 Failure Handling
- Error case enumeration
- Retry policy
- Idempotency guarantee
- State rolled back on failure / state allowed to remain

## 9. Migration Plan
- Expand: add new elements (maintain existing compatibility)
- Migrate: data migration / dual-write
- Contract: remove old elements
(If no DB change: state "N/A")

## 10. Rollback Strategy
- Is rollback possible on failure
- Up to which stage can zero-downtime rollback occur

## 11. Verification / Observability
### 11.1 Verification (before release)
- Which test covers each row of the 3.2 mapping
- Integration / E2E tests, operational checks
### 11.2 Observability (after release)
- Logs / metrics / alerts

## 12. Open Questions
- Unconfirmed items (who is waiting for decision)
- Constraints / assumptions (MySQL 8.0, TX isolation etc.)
```

## Type-based application

| Type | Required sections | Optional sections |
|------|------------------|------------------|
| feature (default) | All 1–12 | None |
| refactor | 1,3,5,6,7,9,10 | 2,4,8,11 |
| arch | 1–4,6,7,11 | 5.1/5.3,9 |
| adr | 1,3,6,7,10 | 2,4,5,8,9,11 |
| db-migration | 1,3,5.1,8,9,10,11 | 4,6 (alternatives can be simple) |
| requirements | 1,2,3,12 | 4-11 (skip — deferred to later phases) |
| basic | 1,3,4,6,7,11 | 5,8,9,10 (skip — moved to the detailed phase) |
| detailed | 1,5,8,9 | 2,3,4,6,7,10,11 (already decided separately in basic / adr) |

## Quality guards (type-based)

| Check | feature | refactor | arch | adr | db-migration | requirements | basic | detailed |
|-------|---------|----------|------|-----|--------------|--------------|-------|----------|
| Why (connection to PRD) | required | required | required | required | required | required | required | required |
| Acceptance criteria mapping (3.2) | required | optional | recommended | optional | recommended | required | required | required |
| Invariants explicit (8.1) | required | recommended | recommended | optional | required | optional | recommended | required |
| Alternatives 2+ options | required | recommended | required | required | recommended | recommended | required | optional |
| Trade-offs numeric comparison | required | recommended | required | required | required | recommended | required | required |
| Failure Handling 3+ cases | required | recommended | recommended | optional | required | optional | recommended | required |
| Migration Expand/Migrate/Contract | required on DB change | required on DB change | optional | optional | **required** | optional | optional | required on DB change |
| Mermaid diagram 1+ | required | recommended | required | recommended | ER diagram required | recommended | required | required (sequence or class) |
| Constraints / assumptions explicit | required | recommended | required | required | required | required | required | required |

## Design philosophy

> A good Design Doc is not "clever design" but **"design where decisions are communicated"**.

| Principle | Bad example | Good example |
|-----------|-------------|-------------|
| Write Why | Create new table | Create new table for O(1) lottery |
| Comparison and tradeoffs | Implement with option A | Compare A/B, B rejected due to high load |
| Change tolerance | Works now | Can handle quantity limit changes / new carrier additions |
| Responsibility boundary | Ambiguous | order-service: orders / shipping-service: delivery |
| Failure cases | Success path only | Out of stock / API failure / double execution / idempotency |
| Migration strategy | Replace table | Expand→Migrate→Contract 3 stages |

**High-quality writing**: speak with numbers (O(n)→O(1), 100req/s→1000req/s), explain with diagrams (sequence/ER/arch), write constraints (MySQL 8.0, READ COMMITTED).

## Phase split (vertical cut)

Types `requirements` / `basic` / `detailed` are **subset cuts of the same 12-section template split per phase**. Use them when one feature is delivered as three docs.

### Chain pattern

requirements (Why / Goal / Non-Goal / Open) → basic (arch / module layout / trade-off) → detailed (data model / API / processing flow / failure / Migration)

Each phase doc references its predecessor from the "PRD link / reference" line in `## 1. Overview`. When a later phase overturns an earlier decision, sync the earlier doc via `--update <path>` (`--scope` is for PRD Q1-Q5 partial fix, not for Design Doc section targeting).

### 【要確認】 tag convention (all types)

Do not fill unconfirmed items with placeholders. Mark pending decisions in the **【要確認: <what / who decides / by when>】** form. Step 6 Quality gate copies the count and content of 【要確認】 tags into `## 12. Open Questions`.

NG example: 「DB は MySQL を使う」 (unfounded placeholder)
OK example: 「【要確認: DB 選定 / backend lead / Sprint 計画時】MySQL 8.0 想定で進める」
