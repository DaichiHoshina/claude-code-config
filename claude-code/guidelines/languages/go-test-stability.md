# Go Test Stability Guidelines

> **Purpose**: Patterns to prevent flaky tests.

## Dynamic Data Validation

```go
// ❌ Bad: auto-generated IDを期待値に含める
assert.Equal(t, entity.Order{Id: 1, BuyerId: 101}, actual)
// ✅ Good: 動的フィールドは個別検証
assert.Greater(t, actual.Id, 0); assert.Equal(t, 101, actual.BuyerId)
```

## Parallel Safety for Shared Data

```go
// ❌ Bad: 並列テストで共有スライスをsort → race condition
// ✅ Good: deep copyしてから操作
cp := make([]map[string]any, len(tt.expected))
copy(cp, tt.expected)
sort.Slice(cp, ...) // Safe
```

## Test Types and Build Tags

| Type | Target | DB | Build tag |
|------|--------|----|-----------|
| Unit Test | pure functions without DB access | not needed | `parallel` |
| Repository Test | Repository layer CRUD | real DB | `serial` |
| Usecase Test | business logic | gomock | `parallel` |
| Integration Test | full API (HTTP response) | real DB | `integration` |

## Test Rules

| Rule | Detail |
|------|--------|
| Table-driven tests | `map[string]struct{}` required |
| Parallelization | `t.Parallel()` required (except Repository Test) |
| Struct comparison | use `go-cmp` |
| Test data | Repository Test uses `testfixtures` (YAML) |
| Mocks | Usecase Test uses `gomock` |

## Log-only Branch Testing

The global `var logger *zap.Logger` pattern (initialized via `Setup()`) offers no test injection hook, so log output cannot be asserted. For PRs that add log-only branches (suppression conditions, deduplication, rate limiting), apply the following compromises.

- Decision axis: absence of a setter hook / zero usages of `zaptest` or `zap/zaptest/observer` in the codebase means no observation hook is in place
- Do not test the log branch itself. State in the PR body that 「log-only 分岐なのでユニットテスト対象外」
- Instead, cover the behavior via other side effects triggered on that branch (metrics / return values / DB state)
- Introducing an observer injection hook tends to exceed scope and draw over-edit review comments. Split "logger test hook setup + tests for the branch" into a follow-up issue

## Flaky Test Prevention Checklist

- [ ] No auto-generated IDs (DB auto_increment etc.) in expected values
- [ ] DB foreign key errors handled appropriately
- [ ] Shared data deep-copied in parallel tests
- [ ] Test fixtures standardized and unified
- [ ] Time-dependent tests use `clock` interface
- [ ] Test DB data initialized for each test
