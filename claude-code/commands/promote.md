---
allowed-tools: Bash, Read, Edit, Grep, Glob, AskUserQuestion
argument-hint: "<memory-file> | --topic <name>"
description: memory の知見を CLAUDE.md / ai-tools skill / command へ昇格する半自動 flow
effort: medium
---

# /promote - memory → SoT promotion

Semi-automated flow to integrate memory files into CLAUDE.md / ai-tools / project rules and delete the memory side.

Detailed routing criteria & proper-noun dictionary: `~/.claude/references-private/memory-promotion-flow.md`

> **Fallback**: `references-private` is machine-local and out of sync scope, so on machines where the file is absent, judge only from the Step descriptions in this command.

## Input

| Arg | Action |
|---|---|
| `<memory_file>` | promote single file (also pass `feedback-<slug>.md` / `project-<slug>.md` produced by `/memory-save` here) |
| `--topic <name>` | aggregate-promote multiple files with same topic |

## Auto invocation via memory-save

Route entered automatically from step 4 of the permanent-knowledge promotion in `/memory-save` (clear mode). The user did not invoke it explicitly, so minimize confirmations and run through to the end.

- Run Step 1 / Step 2 without user confirmation (read-only and dictionary judgment; nothing is rewritten)
- **Do not take** the routing approval in Step 3. Decide a single placement from dictionary + technical-layer judgment and print a one-line rationale to chat
- **Keep** the diff presentation + approval in Step 4. Edits to SoT are hard to notice after the fact and costly to revert, so this is the one point where the destination file and diff are shown for a single confirmation
- On skip decisions (100% duplicate with an existing section / placement undecidable), leave the memory in place without asking and report the reason in one line
- When multiple candidates exist, process them one file at a time. Move on to the second file even if the first is skipped

If the user runs `/promote <file>` directly, execute Step 1-6 below as-is, including confirmations.

## Flow (Step 1-6)

### Step 1: Target memory + same-topic candidate scan

```
ls <repo-root>/memory/
```

- Read the argument memory_file
- With `--topic`: list same-kind files from MEMORY.md by topic prefix
- Show candidate list in chat

### Step 2: Proper-noun grep (project / ai-tools routing)

Read `~/.claude/references-private/memory-promotion-flow.md` Section 7 dictionary each time (no literal heredoc; avoids desync on dictionary update).

```bash
# dictionary hit check
grep -iE "<dictionary regex from Section 7>" <memory_file>
```

- 1+ word hit → **project placement confirmed** (ai-tools placement blocked)
- 0 hit → route to ai-tools / project by technology-layer judgment

### Step 3: Show placement candidates + user approval

For placements that create a new skill / command / hook, first pass the lifecycle gate (friction evidence + cap judgment, `references/on-demand-rules/toolchain-lifecycle.md`).

AskUserQuestion with routing candidates + destination file path:

- destination path
- duplicate sections with existing SoT (detect via Read + grep)
- judgment: new section / append to existing section / separate new file

Accept approval / rejection / alternate path proposal.

### Step 4: Integration edit (Read + diff + Edit)

⚠️ **Critical**: Required to avoid overwrite risk on existing SoT.

1. **Full Read** of destination file
2. Show integration diff to user (which section to add what)
3. Wait for approval
4. After approval, atomically integrate with `Edit`
5. For duplicate sections, confirm priority via AskUserQuestion: memory side / existing side / merge

#### Step 4a (optional): Insert a claude-md-improver plugin audit for CLAUDE.md-family only

Only when the destination file is in the CLAUDE.md family, call the `claude-md-improver` skill before applying `Edit`. Targets are the four files `~/.claude/CLAUDE.md` / `claude-code/CLAUDE.global.md` / repo-local `CLAUDE.md` / `CLAUDE.repo.md`.

- Invocation: `Skill(claude-md-management:claude-md-improver)` (enabled when plugin `claude-md-management@claude-plugins-official` is enabled)
- Read the output; if existing sections should be removed after integration, reflect that in the Step 4 diff
- If the plugin is not enabled or the skill call fails, fall back to the current manual audit flow and report one line to chat: "plugin `fallback`: continuing with manual audit"
- **Not delegated to the plugin**: Step 2 (proper-noun dictionary judgment) / Step 3 (routing approval) / Step 5 (sync.sh) / Step 6 (memory deletion) stay complete on the ai-tools SoT side

#### Step 4b: Work location and verification

ai-tools forbids direct main work (`references/on-demand-rules/ai-tools-worktree-flow.md`), but split by destination. Since the point of isolation is to avoid mixing pre-verification broken behavior into main, SoT files that are not executed are exceptions.

| Destination | Work location |
|---|---|
| `rules/` / `guidelines/` / `references/` / CLAUDE.md family | **main direct edit OK**. Worktree round-trips do not pay for 1-3 line additions |
| `hooks/` / `scripts/` / `lib/` / `skills/` / `commands/` | **Cut a worktree**. Follow the worktree flow through commit → ff-merge → push |

Either way, close only after reverse-lookup via `grep -rl '<destination file name>' tests/ | xargs bats`. **Prose SoT is also under test** (contract tests grep for body sentences; `thinking-principles.md` has codex / cursor drift detection). If it fails, revert the Edit. Print count and result to chat in one line.

### Step 5: Run sync.sh (ai-tools placement only)

```bash
cd "$HOME/ghq/github.com/<owner>/ai-tools/claude-code" && ./sync.sh to-local --yes
```

Apply to `~/.claude/` side (CLAUDE.md "Editing Rule" compliant, local-edit wipe protection).

If Step 4b chose direct-main editing, finish through commit + push in the same turn after sync (do not leave uncommitted SoT changes in the main working tree).

### Step 6: Delete memory file + MEMORY.md index entry

- `rm <memory_file>` (request user manual `! rm ...`; Bash rm permission restricted)
- `Edit`-delete the relevant 1 line from `MEMORY.md`
- Report deletion complete in chat

## Routing blocks

| Detected | Action |
|---|---|
| 1+ proper-noun hit with `--scope ai-tools` | Error; force project placement |
| Destination file not found | Confirm new-file creation path with user |
| 100% duplicate content with existing section | Skip + delete memory only |

## When to use

- On detecting 3+ files with same topic (`~/.claude/references-private/memory-promotion-flow.md` Section 6 trigger B)
- Single file exceeds 5KB / 150 lines (trigger D)
- `feedback-<slug>.md` / `project-<slug>.md` written by `/memory-save`'s permanent-knowledge promotion. This route is auto-invoked from the memory-save side (see 「Auto invocation via memory-save」 above)
- Do not use MEMORY.md line-count overflow as a trigger (dropped 2026-08-24). The index is designed to list every memory file, so line count grows proportionally to file count and overflow is not a signal that knowledge worth promoting has accumulated
- User explicit judgment

## Fallback

| Scenario | Action |
|----------|--------|
| `Bash rm` permission deny | Request user manual `! rm <path>` |
| Destination file conflict (edit by another session) | Report conflict, wait for user resolution |
| sync.sh fail | Show error; template side is already edited, retry recommended |
| Routing judgment impossible | Delegate to AskUserQuestion with candidates |

## Related

- `~/.claude/references-private/memory-promotion-flow.md` — routing criteria SoT
- `references/memory-usage.md` — memory usage basics
- `commands/memory-save.md` — memory write side
- `~/.claude/CLAUDE.md` "## auto memory" — type definitions
