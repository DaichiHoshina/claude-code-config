# Code Quality and Design Philosophy

> **Purpose**: Quality criteria and review perspectives for consistency, readability, and testability. Reference during code reviews and design decisions.

## Quick Reference

### Quality Standards

| Item | Rule |
|------|------|
| Consistency | Follow existing code style and design patterns |
| Readability | No self-indulgent coding |
| Magic numbers | Always extract as named constants |
| Naming | Apply the 3 naming criteria below to every function and variable name |

### Naming Criteria (user 決定 2026-09-24)

Apply in this order. When two criteria conflict, the earlier one wins.

| # | Criterion | How to check |
|---|-----------|--------------|
| 1 | Use the words the repo already uses | Before naming, grep the same layer for names with the same role and count each candidate (`Find` vs `Get`, `order` vs `purchase`). Take the majority. For domain words, reuse the English the repo already maps to the PRD / Design Doc term |
| 2 | Use plain, common English | Pick words a non-native reader knows (`get` / `list` / `check` / `count`). Avoid rare words (`ascertain`, `procure`, `reconcile`) and made-up abbreviations. A rare word the repo already uses is fine under #1 |
| 3 | Keep it as short as it stays clear | Drop words the context already gives: the package / receiver / type name, the type in the name (`userList` → `users`), and filler (`Data`, `Info`, `Process`, `Handle`). Stop cutting when the name alone no longer tells two similar things apart |

Example: in `order` package, `GetOrderDataByOrderID` → `GetByID` (drop the filler `Data` and the repeated `Order`; keep the verb, since `Get` and `Find` can mean different things).

### Naming Shape

After the 3 criteria pick the words, shape the name with these rules. Repo conventions still win (#1).

| Rule | Avoid | Use |
|------|-------|-----|
| Variables are nouns for what the value is; functions are verbs for what they do | `data`, `result`, `handle()` | `selectedSize`, `calculateShippingFee()` |
| Booleans read as a yes/no question: `is` (state) / `has` (owns, exists) / `can` (allowed) / `should` (ought to) / `needs` (required) | `active`, `flag`, `check` | `isActive`, `hasSelectedSize`, `canCancel` |
| Plural for collections, singular for one item | `order []Order`, `productID []ProductID` | `orders`, `productIDs` |
| Name a state change by the business action, not by CRUD | `order.UpdateStatus(Canceled)`, `UpdateData()` | `order.Cancel()`, `ConfirmPayment()` |
| When a name gets long, first ask whether the type or package should carry the context. Cut words only after that | `getActiveOripaPrizeSizeSelectionByShippingRequestID()` | `sizeSelection.FindActiveByShippingRequestID(id)` |
| Maps and records carry their key in the name | `userMap`, `orderArray` | `usersById`, `orders` |
| Filler words only when they add meaning: `data` / `info` / `item` / `value` / `result` / `obj` / `tmp` / `process` / `execute` / `handle` / `manager` / `util` / `helper` | `processData()`, `OrderData` | `calculateShippingFee()`, `Order` |

`handle` is fine for a React event handler (`handleSubmit`), because there it has one clear meaning.

**Verb meanings** (use when the repo has no convention; the repo's own usage wins under #1):

| Verb | Meaning | Example |
|------|---------|---------|
| `get` | Read a value that must exist | `getOrder(id)` |
| `find` | Search; the result may be missing | `findUserByEmail(email)` |
| `list` / `search` | Many items / many items by conditions | `listOrders()`, `searchProducts(query)` |
| `fetch` | Read over the network (HTTP / API) | `fetchOrders()` |
| `load` | Read and put into app or UI state | `loadUserPage(id)` |
| `new` / `create` / `build` | Make in memory / make and save / assemble from parts | `NewOrder()`, `createOrder(input)`, `buildShippingRequest(order)` |
| `parse` / `format` | Text to structured data / data to display text | `parseDate(text)`, `formatPrice(12800)` |
| `serialize` / `to` | Object to a storage or transfer form / A to B in general | `serializeForm(form)`, `toOrderDto(order)` |

Avoid `convert` / `process` when one of the verbs above fits.

**Same word across the stack**: the backend and the frontend use the same English word for one business concept. Do not name one thing `ShippingRequest` in Go and `DeliveryRequest` in TypeScript.

Check: translate the name into Japanese. It should be a word the PRD, Design Doc, or issue already uses.

### Comment Principles

Code comment canonical: `guidelines/writing/code-comment.md` 参照 (default 書かない / 行数上限なし / Why not 中心)。

### Design Philosophy

| Principle | Description |
|-----------|-------------|
| Layered architecture | Flexible design prioritizing ease of change |
| Readable code | Split hard-to-read code; avoid long functions |
| Dependencies | Keep loosely coupled; do not use components from other pages |
| API responses are raw data | Return raw data without UI-specific aggregations; enables reuse across multiple UIs and reduces server-side spec changes |
| Single point of change | Design so spec changes require changes in only one place; extract and consolidate any duplication |

## Common Mistakes

| Avoid | Use | Reason |
|-------|-----|--------|
| `const name = "太郎"; // 名前を設定` | `const name = "太郎";` | Obvious comment unnecessary |
| `const MAX = 100;` | `const MAX_RETRY_COUNT = 100;` | Name expresses intent |
| 200-line function | Split into 10-50-line functions | Improves readability and testability |
| Importing components from other pages | Commonalize or copy | Maintains loose coupling |
