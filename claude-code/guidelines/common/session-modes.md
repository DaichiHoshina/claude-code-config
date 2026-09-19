# Session Modes

> **Purpose**: Defines the operation mode for the entire session. Confirmation flow and constraint level change based on mode.

---

## Mode List

| Mode | Confirmation Level | Use Case |
|------|--------------------|---------|
| **strict** | Confirm all Boundary operations | Production work, critical refactoring |
| **normal** | Standard confirmation (default) | Normal development |
| **fast** | Minimize confirmation | Prototyping, exploratory development |

---

## Mode Operation Matrix

操作単位の confirm/auto 一覧 (git / file / package / config) は `guardrails.md` の Boundary table を正とする。session-modes.md では mode ごとの想定 use case のみ扱う。

| Mode | Use scenario |
|------|--------------|
| strict | Production / critical refactor / security changes / large teams |
| normal | Daily dev / feature add / bug fix |
| fast | Prototype / exploratory dev / personal project |

---

Mode is a guide for thinking strictness. Operation guard (3-layer classification) is enforced by `hooks/pre-tool-use.sh`.

---

## Mode Persistence

Mode is saved in Serena Memory and persists across sessions.

```yaml
memory_key: "session-mode"
content:
  mode: "strict" | "normal" | "fast"
  activated_at: ISO8601
  previous_mode: string | null
```

---

## Context Management

| Item | Limit / Threshold | Action |
|------|-------------------|--------|
| MCP configured | ≤20 | (exceeding this greatly reduces context) |
| MCP enabled | ≤8 | Disable unused MCPs |
| MCP tools | <50 | — |
| Usage 70% | — | Consider `/compact` |
| Usage 85% | — | Disable unnecessary MCPs |
| Usage 95% | — | Start new session |

**Memory management**: Load once at startup / delete completed tasks immediately / no repeated loading

---

## Related

- `guardrails.md` — operation classification (Safe/Boundary/Forbidden)
