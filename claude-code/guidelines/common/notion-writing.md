# Notion Knowledge Management - Core Rules

> **Purpose**: Hierarchy structure and category organization rules for the Notion knowledge Database. Reference when creating a new Notion page or reorganizing categories.

## Design Principles

### Hierarchy Structure

- **Up to 3 levels** (Workspace → Category → Page)
- A need for a 4th level is a signal to split
- Cap top-level categories at 5 to 8

### Leveraging Databases

- Prefer **Databases** over static pages (better searchability and filterability)
- Move tags into a separate Database via Relation (no free-text tags)
- Use Linked Databases to surface the same info in multiple places (Single Source of Truth)
- Split Views by purpose (all items / by category / recently updated / created by me)

### Naming Rules

| Type | Format | Example |
|------|------|-----|
| Category page | Noun | "認証", "決済", "インフラ" |
| Knowledge page | [Category] specific content | "[認証] OAuth2.0フロー設計" |
| Incident response | [YYYY/MM/DD] incident summary | "[2026/04/14] API 504多発" |
| ADR | ADR-NNN: decision | "ADR-012: セッション管理をRedisに移行" |

### Tag Design

| Tag type | Example values | Purpose |
|---------|--------|------|
| Category | Backend, Frontend, Infra, Design | Technical area |
| Type | ADR, Runbook, Recipe, Incident, API | Document type |
| Status | Draft, Published, Archived | Lifecycle |
| Severity | High, Medium, Low | Priority filter |

## Page Creation Rules

### Structure

- 1 knowledge = 1 page (do not mix multiple topics)
- Target 800 to 1,500 characters per page; split if over 2,000
- Put the summary and conclusion in a Callout at the top

### Headings and Structure

- H2 = major heading, H3 = minor heading (do not use H1)
- A need for H4 is a signal to split
- Add a table of contents when the volume is large

### Visual Elements

- Templates go in code blocks
- Flow diagrams use Mermaid syntax
- Always describe images in text so the page stands on its own
- See `notion-design.md` for design details

### Writing Style

For general document style rules, follow the "Document basic rules" section of `../writing/PRINCIPLES.md` (subject required / no demonstratives / no abbreviations / express as IF-THEN).

### Notation

- Halfwidth for alphanumerics
- Dates as YYYY/MM/DD
- No merged cells in tables; fill blanks with "なし"

## Improving Searchability

- **List keywords** at the top of the page (for full-text search)
- Note links to related pages under a "References" section
- Include synonyms and aliases in the body (write out "認証", "ログイン", and "auth")

## Maintenance

| Frequency | Action |
|------|-----------|
| At creation | Status = Draft, add tags, set category |
| At publication | Status = Published, share with the team |
| Quarterly | Review old pages; if invalid, change to Archived |
| As needed | Update the relevant page when things change (do not create a new one) |

- **Update over new**: if a page on the same topic already exists, update it
- Do not delete Archived pages (keep them so past context is searchable)

## Pre-publish Checklist

- [ ] Every sentence has a subject
- [ ] Demonstratives are replaced with concrete words
- [ ] Figures are also described in text
- [ ] Tags (Category / Type / Status) are set
- [ ] Links to related existing pages are included
- [ ] No confidential information (API keys, passwords, internal URLs)

## Related Guidelines

- Design: `notion-design.md`
- DB design: `notion-database.md`
- Operations (AI, permissions, integrations): `notion-operations.md`
