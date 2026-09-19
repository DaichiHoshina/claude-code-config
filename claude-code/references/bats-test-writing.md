# bats test writing standard

Canonical rule the developer agent (Sonnet) reads when editing bats. CI detects violations.

## Forbidden patterns (pass-by-coincidence)

Test passing even with implementation deleted = worthless. Absolute prohibitions:

| Pattern | Reason |
|---------|--------|
| `[ -f "${LIB_FILE}" ]` alone | File existence only, no function call |
| `grep "^funcname()" "$LIB_FILE"` | Definition check only |
| `[ "$status" -eq 0 ] \|\| [ "$status" -eq 1 ]` | Binary assert, all results pass |
| `grep -q ... \|\| true` | Swallow grep failure |
| `echo 'ok'` at end | Always succeeds unless abort |
| `unset PATH` teardown | Later mktemp/rm fail |

## Required patterns

- ✅ **Actual function call**: `run bash -c "source '$LIB_FILE' && <function> <args>"`
- ✅ **Actual value assert**: Verify exit code, stdout, files, env vars, nameref output
- ✅ **External command verify**: stub script via PATH for real invocation
- ✅ **teardown safety**: `export PATH="$ORIG_PATH"` (save in setup)
- ✅ **Output verify**: `[[ "$output" =~ "<string>" ]]` or `[[ "$result" -ge N ]]`

## Self-verify (required)

After new/modified bats: temp no-op target function with `return 0` → rerun bats → **confirm tests turn red** → `git checkout` restore.

Non-red tests = pass-by-coincidence confirmed, rewrite required.

## Execution pitfalls (avoid false green)

- `bats tests/` does not recurse. Without a `.bats` file directly under it, the run reports `1..0` (0 tests) + exit 0 and the gate silently no-ops. Always use `bats -r tests/`, and confirm the ok count with a standalone run before wiring it into a gate
- Piping bats output to tail / grep / head makes exit code inherit the last command, so fail is mistaken for green. Judge either by whether `grep -E "^not ok"` produces output, or by the exit code of an unpiped standalone run
- Run hook smoke tests via `bash hook.sh < /tmp/payload.json` with file-based stdin. `echo '{...}' | bash hook.sh` is cut short by the outer pre-tool-use reacting to a dangerous literal, and `$?` after the pipe captures the last command's rc, not the hook's
- For every new hook, run one smoke test at the real ghq path in addition to bats. Fixtures using only the symlink form (`<repo-root>/`) cannot detect a path-prefix bug (lesson from the 2026-06-08 social-hit block that lay dormant for six months)
- Running `pre-tool-use.bats` inside a worktree causes the cwd-guard to block Edits into `/tmp`, producing 16 failures. This is environmental noise — do not panic; run the final hook bats check on main
- Verify impact by directory (e.g. `bats tests/unit/hooks/`), not by enumerating individual files. Enumeration leaks (2026-08-13: adding a pre-tool-use trap dropped the prep-check and was mis-reported as "no impact"). When adding a trap or `set -E` to a hook body, always verify leakage into source + direct-function-call tests (details: `on-demand-rules/hook-implementation-pitfalls.md` pitfall 13)

## Report format enforcement

bats task completion **must include**:

```
## bats self-verify result
- Old / new test count: XX / YY
- Function A deleted → red: ✓ (N tests)
- Function B deleted → red: ✓ (N tests)
- Full run: ✓ (YY tests)
```

Missing self-verify → reviewer suspects pass-by-coincidence, returns diff.
