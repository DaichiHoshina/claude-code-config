# Investigation Session Contract

Investigation and implementation run in separate sessions. The handoff artifact is the complete implementation specification, not a context summary.

## State machine

```text
PREFLIGHT -> INVESTIGATING -> READY_FOR_IMPLEMENTATION -> fresh IMPLEMENTING
```

- `PREFLIGHT`: record repository identity, branch, HEAD, scope, and exclusions before investigating.
- `INVESTIGATING`: gather and verify requirements, decisions, evidence, affected symbols, and implementation steps.
- `READY_FOR_IMPLEMENTATION`: freeze a complete handoff artifact after blockers are resolved.
- `IMPLEMENTING`: start only in a fresh session after validating the handoff.

Transitions do not skip states. A partial artifact remains `INVESTIGATING`. `/compact` only compresses context within the current phase; it is not a phase handoff and does not create a fresh implementation session.

## Handoff artifact

Use `templates/investigation-handoff.md.template`. Every artifact contains:

- Metadata: `state`, `source_session`, `source_repo_root`, `source_branch`, `git_head`, `next_command`
- Sections: `scope`, `out_of_scope`, `requirements`, `decisions`, `evidence`, `files_and_symbols`, `implementation_steps`, `verification_commands`, `open_questions`, `residual_risks`

All fields must have substantive content. Use `None` only when a section genuinely has no entries. Evidence must identify reproducible sources. Implementation steps and verification commands must be executable without recovering investigation context from the source session.

SessionStart injects `current_session_id: <id>` into additional context from its stdin `session_id`. The source session copies that injected value into `source_session`; it must not use `CLAUDE_CODE_SESSION_ID`.

`READY_FOR_IMPLEMENTATION` means the artifact itself is the implementation specification. Before writing that state, replace all angle-bracket placeholders and remove template comments. Once the source session writes that state, the source session must stop all new Agent work and write-class work. It may only report the handoff path and exit.

If an unresolved blocker exists, add `UNRESOLVED_BLOCKER: <reason>` and keep the state `INVESTIGATING`. A handoff containing that marker cannot enter implementation.

## Fresh implementation session

Start a new session with:

```text
/dev --handoff <absolute-handoff-path>
```

Before implementation, run:

```bash
claude-code/scripts/validate-investigation-handoff.sh \
  --expected-repo-root "$PWD" \
  --current-head "$(git rev-parse HEAD)" \
  --current-session "<newly-injected-current_session_id>" \
  "<absolute-handoff-path>"
```

Pass the fresh `/dev` session's newly injected `current_session_id` to `--current-session`. Do not read the value from `CLAUDE_CODE_SESSION_ID` (a stale session value may remain).

### Validator command rule (shared by source and implementation sessions)

The `<...>` notation is assembly notation for documentation only. Before invoking the validator, substitute each placeholder with the literal value and issue a single Bash tool call. The executed command must contain no shell variables, command substitutions, chaining, redirection, or remaining placeholders.

Preparation for both modes:

1. Run read-only `git rev-parse --show-toplevel` and `git rev-parse HEAD` as separate Bash tool calls and keep each literal stdout in context.
2. Read the `current_session_id` from the machine-readable context injected by SessionStart. Never read `CLAUDE_CODE_SESSION_ID`.
3. Substitute the fetched repo root, HEAD, session id, and the absolute path of the handoff artifact into the command below.

Source session (mode = `source`, before writing `READY_FOR_IMPLEMENTATION`):

```bash
~/.claude/scripts/validate-investigation-handoff.sh --mode source --expected-repo-root "<repo root>" --current-head "<HEAD>" --current-session "<current_session_id>" "<absolute-handoff-path>"
```

Fresh implementation session (mode = `implementation`, at start of `/dev --handoff`):

```bash
~/.claude/scripts/validate-investigation-handoff.sh --mode implementation --expected-repo-root "<repo root>" --current-head "<HEAD>" --current-session "<current_session_id>" "<absolute-handoff-path>"
```

On failure (repo/HEAD mismatch, source vs. current identity failure, missing schema / evidence, `PREFLIGHT` / `INVESTIGATING` / `UNRESOLVED_BLOCKER`), stop without transitioning state and report the reason.

Validation rejects:

- any state other than `READY_FOR_IMPLEMENTATION`, including partial investigation state
- a missing source session or a current session equal to the source session
- a repository root or HEAD that differs from the current implementation checkout
- missing or empty required fields
- unresolved angle-bracket placeholders or template comments
- an unresolved blocker marker
- a malformed fresh-session command

Repository or HEAD drift requires a new investigation decision. Do not silently update the artifact in the implementation session.
