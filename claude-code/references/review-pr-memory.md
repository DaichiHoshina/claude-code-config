# /review の PR-scoped Memory (read → append)

`commands/review.md` から移動した on-demand 手順。PR を対象にした review でのみ読む。

Fires only when the target is a PR (URL/number argument, or a state retrievable via `gh pr view`). Local diff review (no target argument) skips this step.

**Purpose**: When review of the same PR repeats across worktrees / sessions, carry over the existing per-angle status so already-checked angles are not re-inspected from scratch each time.

### Read (before Step 0)

1. Identify the target repo (org-internal short name) and PR number
2. Check the PR state with `gh pr view <number> --json state -q .state`. If `MERGED` / `CLOSED`, do not start review; ask a single question about whether to continue. If continue is instructed, proceed as usual. `OPEN` proceeds to next as-is (reviewing a closed PR invites user pushback like "isn't this already merged?". 2026-07-21 retrospective P2)
3. Check for `$MEM/pr_<repo>_<number>_review.md` (`MEM=$(bash ~/.claude/scripts/memory-save-helper.sh resolve-dir)`; resolves to the org-side memory dir when cwd is an org repo, otherwise to `<repo-root>/memory/`). If present, Read it and fold the per-angle status table into judgment material for this scope. Do not re-present angles marked `check済` / `user却下`; prioritize re-verifying `保留` / `対応中` angles
4. If absent, prepare the template below for new creation and initial-write it via Append after review completes

### Append (after Stage B completes)

Update the memory file. For existing angles, update only the status column and keep the row. For newly found angles, add a row.

### Naming convention and template

- path: `$MEM/pr_<repo>_<number>_review.md`. `$MEM` is the resolve-dir result above, `<repo>` is the org-internal short name, and `<number>` is the PR number. For org-repo reviews, place in the org-side memory dir; do not leave product-specific PR information on the ai-tools side (2026-07-16 org separation policy)
- **Naming resolution procedure (fixed 2026-07-27 to prevent drift)**: use the value of `gh repo view --json name -q .name` for `<repo>` as-is (do not add owner or `.git`, and do not strip suffixes like `.com`). Before writing, glob `$MEM/pr_*_<number>_review.md`; if a file for the same PR number already exists, append to it using that filename as the canonical one (do not create a second file under a new name; short / full name drift once produced two files for the same PR on 2026-07-23)
- frontmatter:

```yaml
---
name: pr_<repo>_<number>_review
description: <repo> PR #<number> review 状態追跡
metadata:
  type: knowledge
---
```

- body (per-angle status table; column headers and status values are Japanese literals written into memory):

| 観点 | status | comment link | 更新日 |
|---|---|---|---|
| (example) N+1 query | 対応中 | `<PR comment URL>` | 2026-07-17 |

status values: `check済` / `user却下` / `保留` / `対応中`.

**MEMORY.md sync is out of scope**: `pr_*_review.md` is per-PR ephemeral state that does not pass `/memory-save`'s Tier judgment, so it is not auto-appended to `$MEM/MEMORY.md` (to avoid index bloat). Only when content should be promoted to long-term knowledge, manually run `/memory-save` or append a single line.

Related: for memory update linkage when running post-comment, see `commands/post-comment.md` `### Step 3.5`.
