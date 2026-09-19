# Notion Operations (AI, Permissions, External Integrations)

> **Purpose**: Operational rules for Notion AI usage, permission management, and external integrations. Reference when configuring a Notion workspace.

## Using Notion AI

### AI Autofill Properties

- **AI Summary**: automatically generate a summary from page content (useful for scanning a database)
- **Custom AI Autofill**: prompt-driven auto-classification, tagging, and translation

### Recommended Uses

| Use | AI property setup | Example |
|-----|-------------------|---------|
| Auto summary | AI Summary | Meeting notes → 3-line summary |
| Auto category | Custom Autofill "Pick a category from Backend/Frontend/Infra" | Auto-classify knowledge base |
| Keyword extraction | Custom Autofill "Extract 3 technical keywords" | Improve searchability |
| Translation | Custom Autofill "Translate the title to English" | Multilingual teams |

### What AI Is Bad At

- Judgments that require external context (it cannot reference other databases)
- Complex multi-step reasoning
- Properties that require 100% accuracy — use manual input instead

## Permission and Sharing Design

### Core Principles

- **Least privilege**: grant only the minimum necessary access
- **Control at the parent page**: parent-page permissions cascade to children
- **Workspace permission > Teamspace permission**: full access at the workspace level cannot be restricted at the teamspace level

### Teamspace Design

| Type | Visibility | Use |
|------|-----------|-----|
| Open | All employees can view | Company-wide knowledge, internal wiki |
| Closed | Members only | Department-specific documents |
| Private | Invitees only | HR, executive, confidential information |

### Database Permissions

- **can create pages**: view + add rows only (cannot edit existing rows)
- Use "can create pages" for operational databases and "can edit" for master databases

## External Tool Integrations

### Link Previews (Recommended)

| Tool | Displayed content |
|------|-------------------|
| GitHub PR/Issue | Title, status, assignee |
| Jira ticket | Ticket name, status, priority |
| Figma | Live preview of the design |
| Slack message | Snapshot of the message |
| Google Docs | Document preview |

### Embed vs. Link Preview

| Method | Use | Caveat |
|--------|-----|--------|
| `/embed` | Interactive embeds like Figma, Miro | Makes the page heavy |
| Link preview | Reference only (GitHub, Jira, etc.) | Lightweight, recommended |
| Mention link | Reference to a Notion page | Displays the page title automatically |

- **At most 2 embeds** per page (they slow the page down)
- Prefer link previews when the goal is reference

### Notion AI Connect

Lets Notion AI search external sources such as Slack, Google Drive, GitHub, and Jira across the workspace with natural language.
