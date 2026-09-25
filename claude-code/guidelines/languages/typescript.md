# TypeScript Guidelines

TypeScript 7.0 (released 2026-07-08, native port). Common guidelines: `~/.claude/guidelines/common/`.

---

## Core Principles

- **strict: true required**: enable all strict options
- **Maximize the type system**: catch errors at compile time
- **Latest ECMAScript**: ES2024 support (5.7+)
- **Functional**: immutability, pure functions

---

## Directory Structure

- `domain/` — entities, value objects
- `application/` — use cases
- `infrastructure/` — DB, external APIs
- `presentation/` — controllers, DTOs

---

## Type Definitions (strict)

Prohibitions (no `any` / no `as` / no `!`): see `~/.claude/guidelines/common/type-safety-principles.md`.

### Type Usage
- `interface` — object shape
- `type` — union/intersection types
- **Branded Type** — ID type safety
- **const assertion** — `as const`
- **Utility Types** — `Partial<T>`, `Pick<T,K>`, `Omit<T,K>`, `Record<K,V>` etc. (see Quick Reference > Utility Types table)

---

## Naming Conventions

- Variable/Function: camelCase
- Type/Class: PascalCase
- Constant: UPPER_SNAKE_CASE
- Private: # prefix
- Types: name what the value is (`Order`), not `OrderData` / `UserInfo`. No `I` / `T` prefix (`User`, not `IUser`). Add a suffix only for a role: `CreateOrderInput` / `OrderResponse` / `OrderCardProps`
- Maps / records: `xxxByKey` (`productsById: Record<string, Product>`)
- Status: a union type (`'pending' | 'paid'`), not `string`. Use a discriminated union when each status carries different fields
- Class getters: no `get` in the name (`get name()`, not `getName()`)
- Module names are not part of the call site (`import { formatQuality } from './quality'`), so keep the concept word in the function name

### React

- Props callback: `onXxx`. The handler inside the component: `handleXxx` (`onClick={handleSubmit}` calls `onSubmit`)
- Components: name the role, not the look (`SubmitButton` / `OrderSummary`, not `BlueButton` / `LeftArea`). Generic names are fine for design-system primitives (`Button` / `Dialog`)
- Hooks: `useXxx` naming the concept the hook provides (`useOrder(orderId)` / `useShippingForm()`). Avoid `useHelpers` / `useCommon`

---

## null/undefined

- `?.` — Optional Chaining
- `??` — Nullish Coalescing
- Type guard: `function isUser(data: unknown): data is User`

---

## Function Design

- Prefer pure functions
- Isolate side effects explicitly
- Early return

---

## Quick Reference

### Type Definitions

| Use | Code | Description |
|-----|------|-------------|
| Type-safe unknown | `unknown` + type guard | alternative to any |
| Union | `type Status = "active" \| "inactive"` | either |
| Intersection | `type A & B` | both types |
| Branded Type | `type UserId = string & { __brand: "UserId" }` | distinguish ID types |
| const assertion | `as const` | literal type |

### Utility Types

| Type | Use |
|------|-----|
| `Partial<T>` | make all properties optional |
| `Required<T>` | make all properties required |
| `Readonly<T>` | make all properties read-only |
| `Pick<T, K>` | extract specific properties |
| `Omit<T, K>` | exclude specific properties |
| `Record<K, V>` | key-value map |
| `NonNullable<T>` | exclude null/undefined |
| `ReturnType<F>` | extract function return type |
| `Parameters<F>` | extract function parameter types (tuple) |
| `Awaited<T>` | extract resolved Promise type |

### Error Handling

| Pattern | Code | Use |
|---------|------|-----|
| Result type | `type Result<T, E> = { ok: true; value: T } \| { ok: false; error: E }` | functional error handling |
| Custom error | `class NotFoundError extends Error` | typed errors |
| try-catch | `try { ... } catch (error) { ... }` | exception handling |

## Common Mistakes

| Avoid | Use | Reason |
|-------|-----|--------|
| `function process(data: any)` | `function process<T>(data: T)` | type safety |
| `const user = data as User` | `if (isUser(data))` | runtime safety |
| `user.name!.toUpperCase()` | `user.name?.toUpperCase()` | null safety |
| `throw new Error()` | `Result<T, E>` type | clear control flow |

---

## Deprecated Pattern Detection (review / implementation)

Check `tsconfig.json` `target` and `package.json` TypeScript version before flagging.

### Critical (always flag)

| Deprecated | Modern | Since |
|------------|--------|-------|
| `enum Foo { ... }` (numeric enum) | `as const` object or union type | general TS |
| `namespace` | ES Modules (`import`/`export`) | general TS |
| `/// <reference>` | `import` statement | general TS |
| `require()` | `import` (ESM) | ES2015+ |
| `any` type usage | `unknown` + type guard or generics | strict |

### Warning (proactively flag)

| Deprecated | Modern | Since |
|------------|--------|-------|
| `Promise.then().catch()` chain | `async`/`await` + `try`/`catch` | ES2017 |
| `Object.assign({}, obj)` | spread `{ ...obj }` | ES2018 |
| `arr.indexOf(x) !== -1` | `arr.includes(x)` | ES2016 |
| `Object.keys(obj).forEach(...)` | `Object.entries(obj)` / `for...of` | ES2017 |
| `arr.filter(...)[0]` | `arr.find(...)` | ES2015 |
| `arr.reduce` for array grouping | `Object.groupBy()` / `Map.groupBy()` | ES2024/TS5.7 |
| `lodash.get(obj, 'a.b.c')` | Optional chaining `obj?.a?.b?.c` | TS3.7/ES2020 |
| `x === null \|\| x === undefined` | `x ?? fallback` (Nullish Coalescing) | TS3.7/ES2020 |
| `x != null ? x : fallback` | `x ?? fallback` | TS3.7/ES2020 |
| `@decorator` (legacy/experimental) | Stage 3 Decorators | TS5.0 |
| Repeated `typeof x === 'string'` | `satisfies` for type assurance | TS4.9 |

### Info

| Item | Detail | Since |
|------|--------|-------|
| TS 7.0 (Project Corsa) | native compiler for 10x speedup; 6.0 is last JS version | released 2026-07-08 |
| `--erasableSyntaxOnly` | detect runtime-affecting syntax | TS5.8 |

---

## tsconfig.json Required Settings

```json
{
  "compilerOptions": {
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "target": "es2024"
  }
}
```

---

## Tools

- ESLint + typescript-eslint
- Prettier
- TypeDoc

## Security

- Dependency vulnerabilities: scan with `npm audit` / `osv-scanner` (the concrete check behind DoD "Security clean")

## Failure Pattern Catalog

10 common pitfalls in TS implementation. Use as a self-check before implementation and during review.

| Symptom | Common mistake | Correct move |
|---|---|---|
| Type errors won't go away | Escape to `any` and disable type checking | Narrow with `unknown` + type guard |
| Missed branches in union types | Handle only some variants and let the rest slip through | Split every variant via discriminated union + narrowing |
| Async work advances before it completes | Leave a floating promise by forgetting `await` | Add `await`; enable the `no-floating-promises` lint |
| A partial failure in parallel work rejects the whole batch | Use `Promise.all` without considering partial failures | Judge each result individually with `Promise.allSettled` |
| Runtime crash from `undefined` access | Stack `!` (non-null assertion) right after optional chaining | Handle the `?.` result with early return or a default value |
| Enum and literal types don't line up | Mix an enum with union literals and compare/convert them | Unify on union literals (`as const`) |
| A change after copying leaks back to the original object | Shallow-copy a nested object with spread | Deep-copy with `structuredClone` |
| `switch` goes silent when a new variant is added | Fall through to `default` without an exhaustiveness check | Assign to `never` in `default` (exhaustive check) |
| Types pass but values break at runtime | Force an invalid type with an `as` assertion | Verify with a type guard function or runtime validation such as zod |
| Key types disappear from the result of `Object.keys` | Index into a `string[]` as-is, causing type errors or overusing `as` | Use a helper that narrows keys to a union (`keys<T>()`) or a `Map` |
