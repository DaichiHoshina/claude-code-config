# Session Management

Claude Code session operations for long-running tasks (multi-day, large features, complex investigations).

## Commands

| Command | Purpose |
|---------|---------|
| `claude --continue` | Resume previous session (most frequent) |
| `claude --resume` | Select from recent sessions. Paste PR URL in search box to find session that created it (GitHub/GHE/GitLab/Bitbucket, 2.1.122+) |
| `/rename <name>` | Name the current session |
| `Esc + Esc` / `/rewind` | Restore checkpoint (persists after session end) |
| `/clear` | Full context reset (when switching tasks) |

## Permission mode policy

| Mode | Purpose |
|------|---------|
| Normal mode | Default. Approve important operations one by one |
| Auto Mode (Max/Team/Enterprise only) | See `claude --help` `auto-mode` subcommand. Suppresses per-operation approval in prepared allowlist environments |
| `--dangerously-skip-permissions` | Not for daily use. Sandbox/isolated environments only. From 2.1.126+, also bypasses writes to `.claude/`, `.git/`, `.vscode/`, shell config files (catastrophic deletion continues to require confirmation) |

> Source: Post-Opus 4.7 release operations guide ([Qiita @ot12 2026-04-16](https://qiita.com/ot12/items/06420caf41a34a910c53), secondary source). Not officially documented by Anthropic; treat as operational reference.

Discontinue always-attaching `--dangerously-skip-permissions`. If caused by insufficient allowlist, use `/fewer-permission-prompts` for semi-automated maintenance, then check `~/.claude/settings.json` `permissions.allow` and manually add missing entries.

## Naming convention

Recommend `{type}-{scope}` format. Easy to identify in grep/list.

| type | Example |
|------|---------|
| `migration-` | `migration-oauth`, `migration-react-19` |
| `debug-` | `debug-memory-leak`, `debug-flaky-test` |
| `investigate-` | `investigate-latency-spike` |
| `feature-` | `feature-billing-v2` |
| `refactor-` | `refactor-auth-middleware` |

Jira/Linear ticket linked: `{ID}-{brief}` format (e.g., `PROJ-1234-oauth-flow`). Find immediately in `--resume` list by ID.

## Selection guide

| Situation | Recommended |
|-----------|------------|
| Under 5 min, one-off task | No naming needed, reset with `/clear` |
| 30+ min investigation / implementation | Name with `/rename`, OK to close terminal |
| Resume from different machine / next day | Select with `--resume`, `--continue` is previous only |
| Transition from investigation to implementation phase | **Fresh session** (`/clear` or new terminal) + validated handoff artifact. Do not carry investigation context |
| Multiple features in parallel | Separate terminal tabs with individual sessions, each with `/rename` |

## Fresh launch pattern (required after investigation)

After investigation, persist `templates/investigation-handoff.md.template` to an absolute artifact path according to `references/investigation-session-contract.md`. Write the exact `current_session_id` injected as machine-readable context by SessionStart to `source_session`; never read `CLAUDE_CODE_SESSION_ID` because it may contain a stale session value. Set state to `READY_FOR_IMPLEMENTATION`, validate it with `claude-code/scripts/validate-investigation-handoff.sh`, and stop the source session. This is a semantic phase boundary regardless of context percentage.

**Why**: Failed approaches and unrelated file reads from investigation phase remaining in context degrade implementation quality. A validated artifact preserves evidence and decisions without carrying the investigation context.

```bash
# Phase 1: Investigation (create and validate handoff artifact)
claude --rename investigate-oauth-design

# Phase 2: Implementation
claude  # new launch
/dev --handoff /absolute/path/to/investigation-handoff.md
```

The implementation session passes the newly injected `current_session_id` directly to the validator before editing; it does not read `CLAUDE_CODE_SESSION_ID`. Validation checks the artifact against its repo root, full HEAD, and source session identity. It accepts only `READY_FOR_IMPLEMENTATION`; `PREFLIGHT` / `INVESTIGATING`, `UNRESOLVED_BLOCKER`, or any identity mismatch stops with a report. Do not re-investigate in the implementation session. `/compact` only compresses context within the current phase and cannot replace this fresh-session boundary.

Planning that performs no investigation and simple `/dev` work remain in one session; fresh launch is not a context-percentage threshold.

## Common failures

- **Kitchen sink session**: mixing unrelated tasks in one session → context contamination, performance degradation
- **Compacted phase transition**: using `/compact` to continue from investigation into implementation → handoff validation and source/current session separation are bypassed
- **Extended session fix loop**: 2+ failed fixes → `/clear` and restart with better prompt
- **Multiple parallel sessions unnamed**: `--resume` list all `Untitled`, cannot identify

## Project state reset (`claude project purge`)

Last resort when session history / tasks / file history / config entries are corrupted or bloated (CLI 2.1.126+).

| Command | Behavior |
|---------|---------|
| `claude project purge --dry-run [path]` | Show deletion targets, no execution |
| `claude project purge -y [path]` | Delete without confirmation |
| `claude project purge -i [path]` | Interactive selective deletion |
| `claude project purge --all` | Delete all projects (use with care) |

- `path` defaults to CWD project if omitted
- Deletes: transcripts (`~/.claude/projects/<sanitized>/`) / tasks / file history / config entries
- Session history also deleted, so `--resume` not possible; export before deletion if needed

## Relationship with checkpoints

- Checkpoints persist after session end (survive terminal close)
- Implement in session A → resume with `--resume` another day → restore checkpoint with `Esc+Esc`
- git commits are a separate layer; checkpoints track Claude changes only

## Multi-session parallel operation

Pattern for running complex features and independent tasks in parallel. Boris Cherny's public approach (howborisusesclaudecode.com) treats multiple parallel sessions as the main circuit. Reason: thinking / tool execution wait time in a single session becomes a serial bottleneck; running multiple sessions simultaneously eliminates human idle time.

| Item | Recommended |
|------|------------|
| Simultaneous sessions | 3–5 (Boris's public upper limit; beyond that: notification flood and context tracking breakdown) |
| Working directory | Separate git worktree per session (`git worktree add`) |
| Identification | Terminal tab numbers 1–5, `/rename {type}-{scope}` |
| Notifications | `hooks/teammate-idle.sh` for OS notifications on input prompts |
| Use cases | Independent tasks (FE/BE/test), A/B trials, long-running verify and parallel implementation |

**Distinction from worktree automation:**

- Short-term, auto independent tasks → `/flow --parallel` / `/dev --parallel` `isolation: "worktree"` (auto create/cleanup)
- Long-term, human judgment involved → manual `git worktree add` + individual terminal sessions

Formula, conditions, cleanup policy: see `references/PARALLEL-PATTERNS.md`.

**Patterns to avoid:**

- Same-file parallel editing (guaranteed conflict)
- Sharing context between sessions verbally (not reproducible)
- Over 5 parallel (humans cannot track, notification flood)

Root of all 3 anti-patterns: "humans cannot track the situation". Prioritize traceability over parallelism.

Reference: [howborisusesclaudecode.com](https://howborisusesclaudecode.com/)
