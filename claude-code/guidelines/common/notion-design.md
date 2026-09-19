# Notion Design Patterns

> **Purpose**: Design rules for Notion page icons, cover images, and layout. Reference when formatting Notion pages.

## Cover Images and Icons

- **Set an icon on every page**
- Keep icon style consistent (emoji or custom icon, do not mix)
- Pick custom icons from a single set (recommended: [Phosphor Icons](https://phosphoricons.com/), monochrome)
- Cover image: gradient or Unsplash photo. Recommended size 1500x600px
- Match the cover image tone to the page's accent color

## Color Rules

| Element | Rule |
|---------|------|
| Accent color | Limit to one color (blue or green family, etc.) |
| Background | Default white + only a pale background of the single accent color |
| Text color | Black (default) + gray (supplementary) + accent color (emphasis) |
| Red | Warnings and top-priority items only. Never for decoration |

- Use **at most 3 colors** per page (base + accent + emphasis)
- Align Select colors inside databases to the accent color

## Fonts

| Font | Impression | Use |
|------|-----------|-----|
| Default (sans-serif) | Modern, clean | General documents |
| Serif | Formal, intellectual | Long-form text, reports |
| Mono | Technical, engineer-oriented | Technical documents |

- Use **one font** per page

## Spacing and Section Breaks

- **Place a divider before every H2 heading** (`/divider`) to visually separate sections
- Do not insert blank lines between a heading and its content (Notion inserts spacing automatically)
- Do not pack content tightly. Leave adequate whitespace between information blocks

## Callouts

| Pattern | Icon | Background | Use |
|---------|------|-----------|-----|
| Overview | 💡 | Gray background | Page-top summary |
| Important | ⚠️ | Yellow background | Cautions |
| Prohibited | 🚫 | Red background | Things not to do |
| Tip | ✅ | Green background | Recommendations, best practices |

- Default (gray border only) looks the most polished
- **At most 3 callouts** per page

## Toggles

- Store supplementary information and detailed steps inside toggles (keep the body clean)
- Give the toggle a title that conveys its content ("Details" → "Detailed steps of the auth flow")
- **No nesting** (toggles inside toggles get lost)
- Do not toggle content of 3 lines or fewer (show it inline instead)

## Layout

### Multi-column

- `/2c` for two columns, `/3c` for three columns
- Left column = overview table, right column = detailed explanation reads well
- Inline databases inside a column suit a small view (List or Gallery)
- **Balance the information volume** between left and right (uneven columns are hard to read)

### Tabbed Layout

- Related databases can be shown as tabs via Relation
- Uses: Project → tabs for Tasks/Meeting notes, Client → tabs for Deals/Contact history
- Keep tab names short ("Tasks", "Notes", "History")
- **At most 4 tabs**

### Dashboard / Home Page

```
[Cover image] / [Icon + title]
> 💡 Callout: state the page's purpose in one line
--- (divider)
## Section 1 [inline DB] / ## Section 2 [inline DB] (two columns)
--- / ## Links
```

## Common Design Mistakes

| Mistake | Fix |
|---------|-----|
| Mixing emoji and custom icons | Pick one and stick to it |
| A page with 5+ colors | Keep to 3 colors or fewer |
| Callouts everywhere | Cap at 3, vary by importance |
| Top page without a cover image | Always set a cover |
| Everything in the same text size | Layer with H2/H3, emphasize with bold |
| Long page without dividers | Divider before every H2 |
