# Writing: Document Quality

## Scope

md files (Design Docs, READMEs, ADRs, reports), Notion drafts, PR descriptions, PRDs. Excludes code & code comments (code covered under `readability`).

## First principle

All checks derive from: "reduce reader cognitive load", "one read → understand", "avoid 'so what?'", "clarity over cleverness". When unsure: "does this reduce reader burden?". Details: `claude-code/guidelines/writing/PRINCIPLES.md`.

## Checklist

文書全体は `claude-code/guidelines/writing/PRINCIPLES.md` の「文書全体の読みやすさ」を canonical gate とし、文や単語の確認より先に見出しと各段落の主張を読む。語彙の single source of truth は `claude-code/lib/writing-self-check.sh` arrays `_WRITING_NG_EVAL` (evaluative) / `_WRITING_NG_STOCK` (stock) とし、語彙判定が divergent なら lib/ を優先する。

| Check | Bad example | Level |
|-------|-------------|-------|
| **Conclusion late** | "This document explains...", actual conclusion paragraphs later | Warning |
| **Unsupported claims** | Evaluative words ("appropriate", "optimal", "critical") without supporting sentence | Critical |
| **Vague abstractions** | "improve", "optimize", "enhance" with no verified mechanism, evidence, or example | Critical |
| **Term dump** | "Observability", "loose coupling", "scalability" strung together, no context | Critical |
| **Implicit knowledge** | "As you know", "obviously", prerequisite knowledge not supplied or linked | Warning |
| **Technical term undefined** | idempotency / Saga / RLS / CQRS first use without definition | Warning |
| **Paragraph role unclear** | Paragraph neither context / reason / example / conclusion / caveat | Warning |
| **Heading label-only** | Noun only ("Architecture", "Design decision") vs assertive ("Separate read/write to distribute load") | Warning |
| **Unanswered question** | Natural next question at end, not answered next | Info |
| **Implicit subject** | "Implemented", "will execute" — who/what unclear | Warning |
| **Missing decision context** | A necessary actor, timing, scope, or condition is absent | Warning |
| **Bullet relation unclear** | Reader cannot tell what the bullets enumerate or how they relate | Warning |
| **AI stock phrases** | "effectively", "seamlessly", "innovative", "is considered" | Warning |
| **No reader action** | A document intended to request a decision or action does not state it | Warning |
| **Purpose mixing** | Investigation log, decision, and procedure (or tutorial and reference content) require different reader actions in one document | Warning |
| **Incomparable options** | Decision candidates answer different questions or bundle independent decisions | Critical |
| **Duplicated conclusion** | Summary and detail sections restate the same conclusion and reasons | Warning |
| **Correction history residue** | Draft corrections or investigation order remain in a completed document | Warning |
| **Term drift** | The same subject is renamed without defining a distinction | Warning |
| **Causal discontinuity** | Actor, condition, cause, and result cannot be traced in order | Critical |

## Judgment

- **Critical**: 事実・意味・判断を誤らせる箇所は、範囲を特定して直す
- **Warning**: 文脈上の読み違えが起きる箇所だけ直す
- finding 数だけで全文 rewrite を決めない。意味を保てる最小範囲を修正する
- 字数、文数、section 数、接続詞の数を合否判定に使わない

## Example

```
🔴 Critical: [writing] Unsupported "required" (docs/design/<feature>.md:45)
Fix: "SET LOCAL required" → "SET LOCAL required; session-scoped SET on pool leaks tenant to next request"
```
