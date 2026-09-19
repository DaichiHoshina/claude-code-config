# Review Criteria

## Architecture (Design)

### Critical

| Item | Description |
|------|-------------|
| Layer violation | Domain referencing Infrastructure, UseCase with framework-specific logic |
| Dependency inversion broken | Domain depends on Repository impl, missing DI |
| Bypass access | Controller → DB direct, skipping UseCase |
| Business logic in wrong layer | Logic in Controller / Infrastructure |
| Anemic domain model | Entity is getter/setter only |
| Aggregate boundary violation | Direct access outside aggregate root |

### Warning

| Item | Description |
|------|-------------|
| Over-abstraction | Unnecessary interfaces / layers |
| Fat Service | Multiple responsibilities in one Service |
| Ubiquitous language mismatch | Naming diverges from domain terminology |
| OCP-violating conditionals | switch/if for type/carrier → suggest Strategy/Specification |
| Semantic type sharing | Same type for different domain concepts (coupling risk) |

## Quality

### Critical

| Item | Description |
|------|-------------|
| Type safety | `any`, unvalidated `as`, `interface{}` |
| Performance | N+1, memory leaks |
| Outdated patterns | See lang guidelines "detect old patterns" |
| Unused DB features | Can DB-specific SQL complete filtering/transform vs app-side? |

### Warning

| Item | Description |
|------|-------------|
| Code smell | Functions >100 lines, magic numbers |
| Inefficient algorithm | Possible O(n) or O(n log n) for O(n²) |
| Unused code in diff | PR includes unused interface methods / functions |
| HTTP status mismatch | 400 for server issue, BadRequest for not found, etc |

## Readability

### Critical

| Item | Description |
|------|-------------|
| Misleading names | Name ≠ actual behavior |
| Cryptic code | Intent unclear, complex one-liners |

### Warning

| Item | Description |
|------|-------------|
| Cognitive complexity | Deep nesting (3+ levels), long conditionals |
| Naming quality | Over-abbreviated (`usr`, `tmp`), lack of symmetry |
| Function size/arity | >50 lines: split, >4 args: objectify |
| Consistency | Inconsistent naming rules / patterns within project |
| Structure clarity | Missing guard clauses, negation chains, bool flags |
| Over-engineering (YAGNI) | Unused abstractions, helpers called once |
| Redundant shared code | Caller-side branching + internal branching, always-true conditionals |

## Security

### Critical

| Item | Description |
|------|-------------|
| Injection | SQL (string concat), XSS (innerHTML), command injection |
| Auth broken | Plaintext passwords, session leaks |
| Error suppression | Empty catch, ignored errors |
| Secret leaks | password/token/secret in logs |

### Warning

| Item | Description |
|------|-------------|
| Missing headers | CSP, HSTS, X-Frame-Options |
| No rate limit | Public API missing throttling |

## Docs & Testing

### Critical

| Item | Description |
|------|-------------|
| Missing public API docs | Exported types / functions undocumented |
| False comments | Comments diverge from implementation |
| No real assertion | `expect(user).toBeDefined()` only |
| Over-mocking | All mocks, no actual behavior verified |

### Warning

| Item | Description |
|------|-------------|
| Test isolation | Shared state, execution order dependency |
| Coverage gaps | Missing error/boundary case tests |
| Verbose test code | Excessive setup, over-dependency on implementation details |

## Regression Guard (差分外への劣化)

今は壊れていない箇所が、この変更で通知なく劣化しないかを見る観点。diff 内で完結しないため grep / 呼び出し元探索を要する。差分だけで判定できる項目 (Rationale not recorded / Unit mixing) から先に当て、grep が必要な項目 (Sibling divergence / Paired asymmetry) を後で確認する。

### Critical

| Item | Description |
|------|-------------|
| Paired asymmetry | 対になる処理の片側だけ変更 (合計と明細、追加と削除、encode と decode、set と reset) |
| Unit / scale mixing | 単価と合計、秒とミリ秒、税込と税抜、UTC と local を同一の変数 / 引数で扱う |
| Shared default blast radius | 共有 props / default 引数 / 共通定数の変更が、diff に現れない既存呼び出し元の挙動を変える |
| Orphan on delete | 参照先の削除後に、参照先を失った record が残存する。FK / NOT NULL / UNIQUE が実装の前提を保証していない |

### Warning

| Item | Description |
|------|-------------|
| Sibling divergence | 同じ処理が複数箇所にあり、変更が片方にしか入っていない (同名 symbol / 同義 SQL を grep で数える) |
| Duplicate definition | 別名 alias / 定数の二重定義。片方が本番 code から参照されていない |
| Rationale not recorded | magic number / timeout / retry 回数の根拠 (外部仕様・実測値・上流の制限値) が diff にも comment にも記録されない。指摘前に `git log -S <値>` で導入 commit を引き、根拠が履歴側にないか確かめる |
| Test shares the assumption | test が実装と同じ前提 (単位 / TZ / 境界) で書かれ、誤りを検出できない |
| Test depends on live environment | test が実行機の外部状態 (常駐 job の終了 status / 時刻 / network / 既存 DB 行) を mock せず参照し、今の環境で偶然成功している。stub を外す方向の diff もここで検出する |
| External behavior unverified | SDK / FW の実挙動を最新 doc と照合していない。lock file の version 差分で挙動が変わる |
| Timeout budget overrun | timeout 値が上流 (LB / gateway / client) の制限と合算で許容範囲を超える |
| UI state after action | 操作後の画面状態が意図どおりか (検索条件の保持、overlay が対話要素を覆う) |

## Root Cause (Permanent fix)

### Critical

| Item | Description |
|------|-------------|
| Symptomatic fix | Hiding with null checks / try-catch / conditionals |
| Error suppression | Ignoring errors (empty catch, `_ = err`) |
| Same pattern recurs | Issue exists elsewhere in codebase |

### Warning

| Item | Description |
|------|-------------|
| Local-only fix | Fixing 1 spot but pattern exists 3+ places |
| Structural conflict | Fix contradicts existing design patterns |
| Cause unexplained | Can't explain why fix works |

## Logging

See CLAUDE.md "logging design criteria" for details.

### Critical

| Item | Description |
|------|-------------|
| Secret in logs | password/token/Cookie/PII/full request body |
| Missing error context | No error object / stacktrace in logs |
| Unstructured logs | String concatenation (`"user " + id`) |
| Unreachable path wrong level | switch default, unhandled enum as warn/info |

### Warning

| Item | Description |
|------|-------------|
| Wrong log level | warn/error for success, info for errors |
| Rare event as info | Low-probability fallback downgraded to info |
| Missing fields | request_id/trace_id, event, duration_ms |
| NotFound confusion | 0 results as warn, ID lookup not found silent |
| Over-logging | Logs in loops / N+1 queries |
