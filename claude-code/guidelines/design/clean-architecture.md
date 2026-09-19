# Clean Architecture Guidelines

> **Purpose**: Framework-independent, testable software design

## Core Principles

| Principle | Detail |
|-----------|--------|
| **Direction of dependency** | Outer → inner (inner knows nothing about outer) |
| **Separation of concerns** | Separate responsibilities per layer |
| **Framework independence** | Business logic is independent of technical details |

---

## Dependency Direction Is Non-negotiable, Responsibility Granularity Is

The dependency direction is one-way, outer → inner, and the inner layer knows nothing about the outer. This is not open to negotiation and must be respected in every repo. The granularity of each layer's responsibilities (how much the UseCase determines vs. what the View composes) and where things are placed may be negotiated with repo conventions.

The sections that follow proceed from judgment (DB dependency in the Presentation layer) → measurement (dependency graph) → negotiation (conflicts with conventions) → tolerance (remaining duplication), moving down from the non-negotiable topic of direction to the subordinate topic of granularity. Do not read them as license to bend the direction on the grounds of convention.

---

## Layer Structure

| Layer | Responsibility | Contains | Depends On |
|-------|----------------|----------|------------|
| **Domain** | Business rules | Entity, ValueObject, Repository IF | None |
| **Application / UseCase** | Application logic | UseCase, ApplicationService, DTO | Domain only |
| **Interface / Presentation** | I/O handling | Controller, Presenter | Application, Domain |
| **Infrastructure** | Technical details | Repository impl, API Client, ORM | All layers |

---

## Dependency Inversion Principle (DIP)

| Element | Role | Example |
|---------|------|---------|
| **Interface** | Defined in upper layer | `UserRepository` (Domain) |
| **Implementation** | Implemented in lower layer | `PostgresUserRepository` (Infrastructure) |
| **Injection** | Connected via DI | Inject implementation at startup |

---

## Directory Structure

| Pattern | Example Structure | Characteristics |
|---------|-------------------|-----------------|
| **Feature-based (recommended)** | `features/user/{domain,application,infrastructure}/` | Feature-unit separation, scalable |
| **Layer-based** | `{domain,application,infrastructure}/` | Layer-unit separation, simple |

---

## Data Flow

```
Controller (request→DTO) → UseCase (business logic) → Repository (persistence) → Presenter (response)
```

**Data crossing boundaries**: passed via DTO; Domain entities must not leak externally

---

## Test Strategy

| Layer | Test Type | Mock | Characteristics |
|-------|-----------|------|-----------------|
| **Domain** | Unit test | Not needed | Verify business logic |
| **Application** | Unit test | Mock Repository | Verify flow |
| **Infrastructure** | Integration test | Use real DB | Verify technical details |

---

## Anti-patterns vs Best Practices

| Case | NG | OK |
|------|----|----|
| **Framework coupling** | Framework-specific code in Domain | Use framework in Infrastructure |
| **Penetrating architecture** | Controller → DB direct access | Access via UseCase |
| **Transitive DB dependency** | View imports the query layer through a helper under UseCase | View reads only the UseCase Output (see the section below) |
| **Over-abstraction** | Interfaces everywhere | Abstract only necessary boundaries |
| **Business logic placement** | Complex logic in Controller | Consolidate in Domain / UseCase |
| **Technical details** | Framework-specific processing in UseCase | Isolate in Infrastructure |
| **Testability** | No DI | Ensure testability with DI |
| **Layer boundary** | Ambiguous boundaries | Define clear boundaries |

---

## Judge Presentation-layer DB Dependency by the Dependency Graph

A remark like "the View is connecting to the DB" should be judged not by whether the View hits the DB at runtime, but by whether a DB access layer (query / reader) is mixed into the View's import path. Even if the View does not directly import query, if it depends transitively as in `adapter/view → svc/<helper> → pkg/query`, the remark is valid as pointing out DB dependency leaking into the View layer.

Correct direction:

```text
adapter/view → pkg/view → domain model / nullable / logger   (does not import query)
UseCase      → query / command IF → reader / writer implementation
```

Responsibility split (display-label example):

| Layer | Holds | Does not hold |
|---|---|---|
| UseCase | Fetching from DB, mapping onto Output, and when needed the state judgment of "selected / unselected / missing" | Display strings like `"サイズ: M"` |
| pkg/view | Converting Output's map / state into display strings | Importing DB / query |
| adapter/view | Receiving Output, calling pkg/view, and putting the result on the response | Fetching or state judgment |

How to tell them apart: if display-string generation lives in the UseCase (svc), it is presentation concerns leaking in; if a View-side helper imports query, it is DB dependency leaking in. When replying to such a remark, accept it as "inaccurate as a runtime path but valid as a design remark," and write down which dependency you cut and what improvement remains.

---

## Measure the Dependency Graph with a Command

Do not argue "the View does not hit the DB" by reading the runtime call path. Reading only shows the current call order, and a dependency leak comes back with a single import line. Emit the transitive closure of imports and show that the DB access layer appears 0 times.

- Go: `go list -deps ./pkg/view/ | grep -E "/(query|reader|writer)(/|$)"` returns 0 lines (closing with `$` alone will miss sub-packages like `pkg/query/foo`)
- TS / JS: no repository / query path appears in the transitive dependencies of `madge --json src/view`
- Language-agnostic: recursively follow the imports under the target dir and confirm that no forbidden-layer path appears

State the 0-count claim by the line count of a fully enumerated output, not by a grep non-hit. Note, however, that the transitive closure only shows the compile-time direction; implementations injected via DIP do not appear. A 0-count is evidence that "the direction is preserved," not that "the code has nothing to do with the DB." To make it permanent, move the check into an import-restriction linter (Go: depguard; TS: eslint `no-restricted-imports`) and take it out of manual review.

---

## When the Ideal Form Conflicts with Repo Convention, Count the Distribution First

There is more than one right answer for how responsibilities are split across layers. "The UseCase determines state and the View only stringifies it" is the ideal form, but if the repo is consistently "the UseCase returns raw models / maps and the View assembles them," aligning with that convention imposes less burden on readers. The practical landing point is: do not yield on the direction of dependency (never make View → query), but pull the granularity of responsibilities toward the convention.

- Before deciding, count files of the same kind in full. Write both the population and the matching count side by side, such as "out of 129 files defining UseCase outputs, 2 hold display-string fields."
- Distribution is evidence of convention, but not evidence that no rule exists. Before counting, look once through the repo's rules / design docs / ADRs.
- When you do not adopt the ideal form, leave a one-line note of the decision and its rationale in the reply or the PR body, so the same remark does not require recounting next time.
- Do not carve out a package for a shared routine that has only two callers. Layer separation is achieved by the direction of imports, not by adding packages.

---

## Duplicated Conditions Left After Splitting Layers Are Acceptable

Cutting a dependency can leave the same conditional judgment split across two places. The UseCase side may keep it for an inconsistency-monitoring log, and the View side for switching what to display, for instance. When the purposes differ, do not force them to share.

If you do share, name the condition itself and place it on the domain-model side so that both layers call it. Sharing by having the View or the UseCase import the other reintroduces the very dependency you just cut.
