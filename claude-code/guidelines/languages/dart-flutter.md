# Dart / Flutter Guidelines

Dart 3.x + Flutter (hooks_riverpod + freezed + OpenAPI Client dio family). Common guidelines: `~/.claude/guidelines/common/`.

## Core Principles

Java-style translations (IF/Impl split for a single implementation, splitting a Widget into methods, raw use of `Map<String, dynamic>`, raw `int` IDs, nested if-else) fail to exploit Dart 3 language features. Reach for the wins of lint / null safety / pattern matching / sealed classes.

## 5 Rules

### 1. No abstract class (when there is only one implementation)

Write the Repository as a single `FooRepository` class. Do not create `FooRepositoryImpl`. Abstracting a single implementation is over-cost.

```dart
// NG: IF/Impl split for a single implementation
abstract class ProductRepository { Future<Product> find(ProductId id); }
class ProductRepositoryImpl implements ProductRepository { ... }

// OK: one class
class ProductRepository {
  Future<Product> find(ProductId id) { ... }
}
```

This is the opposite direction to what generic clean architecture / DDD recommends for IF/Impl splitting; it is a **Dart / Flutter-specific decision**. Introduce the IF only when multiple implementations (mock implementation / per-environment implementations) actually exist.

### 2. Split Widgets with a private class

Split a Widget with a `private class extends StatelessWidget` such as `_Body` / `_Header`. Avoid a method split like `Widget _buildBody()`.

**Why**: a method split ties the Widget tree's rebuild unit to the parent and coarsens the change-detection granularity. A private-class split keeps the rebuild scoped to the relevant sub-tree.

```dart
// NG: method split
class MyPage extends StatelessWidget {
  Widget _buildBody() => Column(children: [...]);
  Widget _buildHeader() => AppBar(...);
  @override
  Widget build(BuildContext context) => Scaffold(appBar: _buildHeader(), body: _buildBody());
}

// OK: private class split
class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Scaffold(appBar: _Header(), body: _Body());
}
class _Header extends StatelessWidget { ... }
class _Body extends StatelessWidget { ... }
```

### 3. IDs as extension types

Do not pass raw `int` around; separate types with `extension type`.

```dart
extension type ProductId._(int value) implements int {}
extension type UserId._(int value) implements int {}

// NG: raw int makes ProductId and UserId interchangeable
void addToCart(int productId, int userId) { ... }

// OK: separated by type; a swap is a compile error
void addToCart(ProductId productId, UserId userId) { ... }
```

Adding `implements int` lets the JSON serialize / DB layer treat it as an int, while the application layer treats it as a distinct type.

### 4. Typedef `Map<String, dynamic>`

At the JSON conversion boundary, give the type a name with `typedef` and confine it.

```dart
typedef Json = Map<String, dynamic>;

// NG: raw Map<String, dynamic> leaks through API / repository / usecase
Product fromJson(Map<String, dynamic> json) { ... }

// OK: typedef marks the JSON conversion boundary
Product fromJson(Json json) { ... }
```

When `Json` (=`Map<String, dynamic>`) appears in application-layer logic, that is a signal it has leaked past the conversion boundary.

### 5. Pattern matching with Dart 3 switch expressions

The combination of the `switch` expression + destructuring + sealed class detects null / missing branches at compile time.

```dart
sealed class OrderStatus {}
class Pending extends OrderStatus {}
class Shipped extends OrderStatus { Shipped(this.trackingNo); final String trackingNo; }
class Cancelled extends OrderStatus { Cancelled(this.reason); final String reason; }

String label(OrderStatus s) => switch (s) {
  Pending() => '準備中',
  Shipped(:final trackingNo) => '発送済 ($trackingNo)',
  Cancelled(:final reason) => 'キャンセル ($reason)',
};
```

With sealed class + exhaustive check, adding `Refunded` later makes `label` a compile error. An if-else / instanceof chain cannot catch that.

## Testing

- Unit tests: `test` package + `mocktail`
- Widget tests: `flutter_test` + `pumpWidget` / `find.byType` / `find.text`
- When a model is built with freezed, `copyWith` / `==` are generated, so write test assertions as equality comparisons
- Scan dependency vulnerabilities with `dart pub audit` (the concrete check for the DoD item "Security clean")

## Reference implementation pattern

hooks_riverpod + freezed + OpenAPI Client (dio) family projects. For Riverpod, consult the Riverpod 3.x docs for the split among `Provider` / `Notifier` / `FutureProvider`.

## Out of scope

- Dart servers (Shelf / Dart Frog etc.) — Widget-related items (Section 2) do not apply
- Go / TypeScript / Kotlin projects — follow the generic clean architecture / DDD recommendation for IF/Impl

## Related

- `guidelines/languages/README.md` (list of per-language norms; if missing, add this file)
- `guidelines/design/clean-architecture.md` (this file flags that Section 1 runs opposite to that norm)
