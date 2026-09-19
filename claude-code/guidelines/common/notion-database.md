# Notion Database Design

> **Purpose**: Criteria for choosing Notion property types (Select / Multi-select / Date / Number, etc.). Reference when creating a new Notion Database or redesigning properties.

## Property Type Selection

| Data nature | Use | Avoid | Reason |
|-------------|--------------|-------------|------|
| Category / status | Select / Status | Text | Prevents notation drift, filterable |
| Multiple tags | Multi-select | Text (comma-separated) | Individually filterable and aggregatable |
| Date / time | Date | Text | Enables Calendar View and sorting |
| Amount / quantity | Number | Text | Automatic sum and average |
| Reference to another table | Relation | Text (copied name) | Single Source of Truth |
| Aggregated value | Rollup (via Relation) | Manual entry | Auto-updated |
| Calculation / decision | Formula | None | Used for conditional branching and auto-classification |
| Boolean | Checkbox | Select (Yes/No) | More intuitive to filter |

## Property Naming Rules

- Use **specific names** ("Info" → "ClientName", "PublishDate")
- English: PascalCase ("PublishDate", "ClientBudget")
- Japanese: keep short ("担当者", "期限", "優先度")
- Unify property names with the same meaning across Databases (standardize on "Status"; do not mix "状態" / "ステータス")

## Select / Multi-select Management

- **Predefine** the options (do not allow free entry)
- Unify notation (do not mix "進行中" and "In Progress")
- Keep options within 10; if more, group them or split into another property
- Give colors meaning (red = urgent, yellow = caution, green = done, etc.)

## View Design

| View type | Purpose | Example |
|-------------|------|-----|
| Table | Full listing / bulk edit | Master data management |
| Board | Manage by status | Task management (Todo / Doing / Done) |
| Calendar | Date-based management | Release schedule |
| List | Simple listing | Knowledge listing |
| Gallery | Card-style display | Portfolio / meeting notes |
| Timeline | Gantt chart | Project progress |

- Create **3 to 5 purpose-specific Views per Database**
- Always keep one unfiltered "Master View"
- Trim displayed properties per View (hide unnecessary columns)

## In-page Table Display

### Simple Table vs Database

| Purpose | Use | Reason |
|------|---------|------|
| Static comparison table / spec list | Simple Table | No filters needed, lightweight |
| Brainstorming stage | Simple Table | Flexibility is preferable before structure settles |
| Filter / sort required | Database | Enables dynamic narrowing |
| Each row needs a detail page | Database | Rows can expand into pages |
| Want to show in multiple Views | Database | Switch between Board / Calendar / Timeline |

**Decision criterion**: ≤10 rows and low update frequency → Simple Table; otherwise → Database.

### Inline Database

- Default to **inline** (embedded in a page)
- Up to **3 inline Databases** per page
- Limit the default number of displayed rows to **10**

### Building Readable Tables

- Turn on column and row headers (background color + bold improves visibility)
- Enable in-cell text wrapping
- Match the table width to the page width
- Limit displayed properties to **5 to 7 columns**

## Performance

- Keep properties within **15** (too many slows down display)
- Periodically move completed records to an Archive View
- Nest Formulas at most 2 levels deep

## Template Design

### Database Templates

- Define templates via the "▼" next to the "New" button on the Database → Add Template
- Set default values (Status = Draft, Date = today)
- Create multiple by purpose ("Meeting Notes", "ADR", "Incident Report", etc.)

### Using Buttons

- **Turn repetitive work into Buttons** (page creation + property setting in one click)
- Actions: add page, change property, insert block
- Add an icon and a short label ("＋ Create Meeting Notes", "＋ Create Incident Report")

### Content-type Templates

| Type | Required properties | Page structure |
|------|--------------|------------|
| Meeting Notes | Date, Attendees, Project | Purpose → Agenda → Discussion → Decisions → Actions |
| 1on1 | Date, Partner, Status | Well-being / recent updates → Topics → Feedback → Next actions |
| ADR | ADR Number, Status, Category | Context → Decision → Alternatives → Consequences |
| Incident Report | Date, Severity, Status | Overview → Timeline → Root cause → Impact scope → Prevention |
| Retrospective | Date, Sprint | Keep → Problem → Try → Actions |

## Anti-patterns

| Common mistake | Correct approach |
|---------|------------|
| Writing dates in Text | Use the Date property |
| Writing categories in Text | Use Select |
| Manually copying the same info across Databases | Reference via Relation + Rollup |
| Cramming all data types into one Database | Split by type and connect via Relation |
| Adding "Other" to a Select | Revisit the options or provide a separate Text remarks field |
