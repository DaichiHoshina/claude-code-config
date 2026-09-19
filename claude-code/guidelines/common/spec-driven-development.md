# Spec-Driven Development (SDD)

> **Purpose**: Decide whether to write a spec before implementing, and how to run it without paying the maintenance tax. Not a case for adopting SDD wholesale — material for the per-change judgment.
>
> Each section cites its source as `[S1]`. The ID table is at the bottom.

---

## Core idea

Traditionally code is the source of truth and the spec is a subordinate artifact. SDD inverts this: a version-controlled spec becomes the source of truth, and code, tests, schemas, and deployment config are derived from it. Behind the inversion is a failure mode of vibe coding — agents write code well but guess intent poorly, and drift from intent grows with scale. [S1][S2][S6]

Three reasons to put the spec at the center: [S9]

| Reason | Detail |
|--------|--------|
| Change cost | Among code, tests, and docs, the spec is the cheapest to change and maintain |
| Review focus | Review shifts from tracing code to confirming the implementation satisfies the spec |
| Contract for agents | Constraints on what to build become explicit, reducing unrequested features and surprise changes |

---

## Workflow comparison

| Approach | Structure | Notes |
|----------|-----------|-------|
| GitHub Spec Kit | 6 commands: `constitution → specify → plan → tasks → taskstoissues → implement`, plus 3 optional validation commands | Supports 30+ coding agents. Test-first is enforced by the constitution [S1][S2] |
| AWS Kiro | 3 artifacts: `requirements.md` (user stories, acceptance criteria), `design.md` (architecture, sequence diagrams), `tasks.md` (trackable work units) | Requirements-first and design-first variants. Artifacts are written into the repo before implementation [S3][S4] |
| cc-sdd | OSS slash commands (Kiro-compatible) for Claude Code / Cursor / Gemini CLI | Greenfield starts with `steering` to set guardrails; brownfield starts with `validate-gap` / `validate-design` to reconcile against the existing system [S5] |

---

## Constitution (fixing the non-negotiables)

Spec Kit places invariant principles in a project constitution (`memory/constitution.md`) that govern how specs become code: library-first, CLI interface required, test-first as non-negotiable, a simplicity gate (at most 3 projects initially), no excessive abstraction, and integration tests against real data rather than mocks. [S1]

Templates enforce a `[NEEDS CLARIFICATION]` marker, which stops ambiguity from flowing into implementation. [S1]

---

## When to write a spec

Overhead grows heavier the smaller the task. Running a three-phase pipeline for a one-line bug fix does not match reality. [S7][S8]

| Change | Judgment |
|--------|----------|
| Typo / 1 symbol / a few lines | No spec. Implement directly |
| Single feature that fits the existing structure | A few bullet points of requirements at most. No phase breakdown |
| Destructive change / migration / feature spanning components | Write a spec. Separate requirements, design, and tasks |
| Change to a large legacy system | Give up on specifying the whole. Scope the spec to the changed area |

The legacy failure is concrete: against a 500-table schema and years of accumulated business rules, an LLM exceeds its context limit before it can produce a spec. SDD tooling is optimized for "describe it and it gets generated" and does not assume established architecture or accumulated rules. [S7]

---

## Failure modes

| Pattern | Symptom |
|---------|---------|
| Spec drift | Spec and implementation diverge. A stale design doc merely misleads people; a stale spec misleads agents, which execute a plan that no longer matches reality — confidently, without flagging anything [S6][S8] |
| Cost inversion | Authoring and syncing the spec accumulate until effort doubles instead of dropping [S7][S8] |
| Context limit | On a large existing application, the spec cannot be produced at all [S7] |
| Bureaucracy | The spec becomes a form to fill in rather than a tool for clarity. Teams drown in generated plans, task lists, and intermediate artifacts [S7][S8] |

---

## Operating rules

- **Make spec updates bidirectional**: a spec only humans maintain will rot. Maintenance is unrewarded and gets deprioritized, so let agents read and write it too and split the responsibility [S6]
- **Have the agent fix the spec when premises change**: reflect it the moment code changes an assumption or a new constraint surfaces [S6]
- **Narrow the reporting granularity**: reporting every diff is noise. Escalate only changes at the level of "the decision went a different way" [S6]
- **Approve in stages**: approve the initial draft → run tasks → agent reports → confirm changes, and repeat [S6]

---

## Starting light

Handing over roughly 10 bullet points (goal, features, target services) and letting the agent grow them into a full spec works in practice. What made the difference was periodic self-review: asking the AI to find gaps in error handling, data structures, and edge cases surfaced omissions such as infinite-loop guards and external format limits. [S10]

For file layout, avoid an all-in-one `CLAUDE.md`. Keep the spec itself in `SPECIFICATION.md` (chaptered, semantically versioned) and leave only a reference in `CLAUDE.md`. [S10]

---

## Sources

| ID | Source |
|----|--------|
| S1 | [spec-kit/spec-driven.md — github/spec-kit](https://github.com/github/spec-kit/blob/main/spec-driven.md) |
| S2 | [Spec-driven development with AI — The GitHub Blog](https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/) |
| S3 | [Specs — Kiro Docs](https://kiro.dev/docs/specs/) |
| S4 | [Feature Specs — Kiro Docs](https://kiro.dev/docs/specs/feature-specs/) |
| S5 | [gotalab/cc-sdd — Spec-Driven Development Workflow](https://github.com/gotalab/cc-sdd/blob/main/docs/guides/spec-driven.md) |
| S6 | [What spec-driven development gets wrong — Augment Code](https://www.augmentcode.com/blog/what-spec-driven-development-gets-wrong) |
| S7 | [Why Spec-Driven Development Tools Fail in the Enterprise — Martinelli](https://martinelli.ch/why-spec-driven-development-tools-fail-in-the-enterprise/) |
| S8 | [The Limits of Spec-Driven Development — Isoform](https://isoform.ai/blog/the-limits-of-spec-driven-development) |
| S9 | [Claude Code による仕様駆動開発の実践へ — CodeZine](https://codezine.jp/article/detail/23470) |
| S10 | [Claude Code で実践するライトな仕様駆動開発 — Simplex engineers, note](https://note.com/simplex_engineer/n/nd54b2f953b43) |

Collected 2026-08-29. Sources may change; when this file and a source disagree, the source wins.
