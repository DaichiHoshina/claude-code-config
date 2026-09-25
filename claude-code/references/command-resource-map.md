# Command × Resource Map

全体像 (全 command / skill の配置) は `command-tree.md` に集約する。この doc は command ごとの resource 対応表に限定する。

## Legend

Resource coverage map for the four primary commands (`/dev` `/plan` `/review` `/flow`).

この表は上の 4 本だけを対象とする。大きい開発の spec 系 6 本 (`/sdd-design` / `/sdd-plan` / `/sdd-phase-design` / `/sdd-implement` / `/sdd-review` / `/sdd-converge`) は対象外で、このうち `/sdd-plan` と `/sdd-phase-design` と `/sdd-implement` は repo 規範を `scripts/resolve-repo-rules.sh` で対象 file から取得する方式を採る。`/sdd-implement` の実体は `/dev --plan` なので、実装時の resource は上の `/dev` の行と同じになる。3 track の判定は `references/design-phase-flow.md` 「Route selection (3 track)」が canonical となる。

| Resource type | Auto-fired | Notes |
|---------------|-----------|-------|
| **rule** | Auto-applied at launch | Loaded from `~/.claude/CLAUDE.md`, `~/.claude/rules/*.md`, `claude-code/CLAUDE.global.md`. Project `.claude/rules/*.md` added if present. No explicit invoke. |
| **hook** | Auto-fired via settings.json | PreToolUse, PostToolUse, SessionStart, UserPromptSubmit, Stop, Notification. **Same across all commands.** No explicit invoke. |
| **agent** | Via Task tool | Parent launches with `Task(subagent_type)`: po-agent, manager-agent, developer-agent, reviewer-agent. |
| **skill** | Lazy-loaded | Step 0 shows recommended list (text only). Body loaded on `Skill()` call or manual Read. |
| **guideline** | Tech-stack detection | `load-guidelines` skill auto-detects. Referenced in Step 0. |

---

## Four primary commands × resources

### /dev - Implementation mode

| Resource | Details |
|----------|---------|
| **guideline** | **Required core**: `common/code-quality-design.md` / Conditional: `languages/typescript.md` (TypeScript), `languages/nextjs-react.md` (Next.js), `languages/golang.md` (Go) |
| **skill** | Common: `code-comment` |
| **agent** | None (direct execution, no Agent Team) |
| **hook** | Common across all commands (see Legend) |
| **rule** | markdown rules, enterprise security (auto-applied) / plain JP 文体は on-demand `guidelines/writing/PRINCIPLES.md`, AI output rules は on-demand `references/on-demand-rules/ai-output.md` |

**Step 0**: Conditionally runs `load-guidelines` (summary mode).

---

### /plan - Design and planning mode

| Resource | Details |
|----------|---------|
| **guideline** | **Required**: `design/clean-architecture.md`, `design/domain-driven-design.md` / Conditional: `infrastructure/terraform.md` (Terraform), `languages/golang.md` (Go), etc. |
| **skill** | Recommended: `load-guidelines` |
| **agent** | po-agent (for complex planning) |
| **hook** | Common across all commands (see Legend) |
| **rule** | markdown rules (auto-applied) / plain JP 文体は on-demand `guidelines/writing/PRINCIPLES.md` / git merge 禁止は CLAUDE.global.md + permissions.deny |

**Step 0**: Required guidelines (A) + language auto-detect (B) + infra planning (C) + skill integration (D). Appends reference to `references/command-resource-map.md`.

---

### /review - Review mode

| Resource | Details |
|----------|---------|
| **guideline** | **Required**: `common/code-quality-design.md` / Conditional: `load-guidelines` auto-loads on language/framework detection |
| **skill** | Recommended: `comprehensive-review` (main) |
| **agent** | reviewer-agent (via PO/Manager path), pr-review-toolkit:* 6 types (with `--deep` option) |
| **hook** | Common across all commands (see Legend) |
| **rule** | AI output rules は on-demand `references/on-demand-rules/ai-output.md` (generated comment prohibition) |

**Note**: `comprehensive-review` already calls `load-guidelines` internally. No command body change needed.

---

### /flow - Automated workflow execution

| Resource | Details |
|----------|---------|
| **guideline** | Loads guideline of matched skill after task-type determination (e.g., RCA loads `root-cause` skill guidelines) |
| **skill** | Dynamically selected by task type: root cause → `root-cause` |
| **agent** | po-agent (Step 1) → manager-agent (Step 2) → developer-agent×N (Step 3) → reviewer-agent (final review) |
| **hook** | Common across all commands (see Legend) |
| **rule** | markdown rules (auto-applied) / plain JP 文体は on-demand `guidelines/writing/PRINCIPLES.md` / git merge 禁止は CLAUDE.global.md + permissions.deny / RCA 方針は CLAUDE.global.md `## Root Cause Analysis` |

**Step 0**: "Step 0: select skill / agent after task-type determination". Placed before determination table.

---

## Verification Procedures

### Static verification

**Link validity (check all references from command-resource-map.md exist)**:

```bash
grep -oE '`[^`]+\.md`' claude-code/references/command-resource-map.md | \
  sed 's/`//g' | sort -u | while read p; do
    [[ "$p" != */* ]] && continue
    [[ "$p" =~ []*{}+[] ]] && continue
    [[ "$p" =~ ^(~|/) ]] && continue
    if [[ "$p" =~ ^claude-code/ ]]; then
      target="$p"
    elif [[ "$p" =~ ^(common|design|languages|infrastructure|backend|operations)/ ]]; then
      target="claude-code/guidelines/$p"
    else
      target="claude-code/$p"
    fi
    test -e "$target" || echo "BROKEN: $p (resolved: $target)"
  done
```

**Markdown syntax check**:

```bash
mdl claude-code/references/command-resource-map.md
```

### Dynamic verification

1. **`/dev "dummy test task"`** → Step 0 shows skill list
2. **`/flow "dummy test task"`** → Step 0 shows skill list
3. **`/plan "dummy test task"`** → `command-resource-map.md` reference at end of Step 0
4. **`/review`** → `comprehensive-review` calls `load-guidelines` internally

### Resource coverage check

```bash
# 目安 (上限ではない): command 150 行 / skill 130 行。canonical は CLAUDE.repo.md 「Definition File Token Saving」
wc -l claude-code/commands/{dev,flow,plan,review}.md
wc -l claude-code/skills/load-guidelines/SKILL.md
```

---

## Related References

- `references/design-phase-flow.md` - Design phase transitions (規模で分かれる 3 track の選択)
- `references/natural-language-triggers.md` - Full natural language trigger list
