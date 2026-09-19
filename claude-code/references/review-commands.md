# Review Command Guide

| Command | Purpose |
|---------|---------|
| `/review` | Daily review (comprehensive-review skill, 11 perspectives + confidence-80 filter) |
| `/review --codex` | Second opinion (comprehensive + codex plugin parallel, shared findings → Critical) |
| `/review --adversarial` | codex adversarial-review delegation (design decisions / tradeoffs / failure modes) |
| `/review --panel` | 3-lens parallel fan-out (style/security/test-coverage)。旧 `--deep` は 2026-07-23 disable 済で代替は `--panel` + `--codex` |
| `/review --multi <PR>` | 4 methods parallel + auto PR comment post (pre-release, max token cost) |
| `/code-review ultra` | Cloud parallel multi-agent (**user explicit trigger only**, separate billing。built-in slash command。`/ultrareview` は deprecated alias) |

Details: [`commands/review.md`](../commands/review.md)

## Natural language activation

Can launch from natural language: "レビュー", "設計レビュー", "深掘りレビュー" etc. (see `natural-language-triggers.md`). On `/review` standalone launch, **mode is auto-detected** (diff size / PR presence / change type) → heavy modes require user confirmation. Details: [`commands/review.md`](../commands/review.md) Step 0.

## Selection guide

| Situation | Recommended |
|-----------|------------|
| Small–medium (1–3 files) daily | `/review` |
| Strict error handling / type design | `/review --panel --codex` |
| Design decisions / architecture validity | `/review --adversarial` |
| Pre-merge / pre-release / security patch | `/review --multi <PR>` |
| Large branch overall | `/code-review ultra` (user instruction, built-in slash command) |
| PR comment post only | `/code-review:code-review <PR>` direct call |

## Auto review (on PR creation, opt-in)

`/git-push --pr --auto-review` launches `code-review:code-review` + `coderabbit:code-review` in parallel. Details and failure behavior: [`commands/git-push.md`](../commands/git-push.md)

## Related

- [`review-modes-advanced.md`](review-modes-advanced.md) — Deep / Multi mode execution details and aggregation policy
- [`review-patterns-universal.md`](review-patterns-universal.md) — Common review finding patterns for design decisions and SQL dialects
