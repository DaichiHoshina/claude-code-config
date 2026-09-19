# Go Modern Idioms (stdlib replacement candidates / version-specific new idioms)

Companion to `golang.md` 「Deprecated Pattern Detection」, holding replacement candidates that do not fit its Critical / Warning tables plus Go 1.26 / 1.27-specific changes. Kept out of the always-loaded review path; read when writing new Go code, raising the go directive in `go.mod`, or when a modernize request comes in (trigger: `references/guideline-triggers.md`).

## Modern stdlib deltas (1.0-1.26)

Replacement candidates not covered by the two tables above. Apply only entries at or below the go directive in `go.mod`. Use them by default in new code; for existing code, keep the scope to what the intended change requires (no incidental bulk substitutions). Source: [JetBrains/go-modern-guidelines](https://github.com/JetBrains/go-modern-guidelines). The 1.27 entries include language-spec changes and are split into 「Go 1.27 new idioms」 (end of this file).

### slices

| BEFORE | AFTER | Since |
|---|---|---|
| Handwritten loop searching an index | `slices.Index(s, v)` (returns -1 if absent) | 1.21 |
| Loop searching an element by predicate | `slices.IndexFunc(s, f)` | 1.21 |
| Loop computing max / min | `slices.Max(s)` / `slices.Min(s)` | 1.21 |
| Loop reversing via swap | `slices.Reverse(s)` | 1.21 |
| Loop removing consecutive duplicates | `slices.Compact(s)` | 1.21 |
| Passing a slice while still holding excess capacity | `slices.Clip(s)` | 1.21 |
| Loop assembling a slice from an iterator | `slices.Collect(seq)` | 1.23 |
| Collecting from an iterator then sorting | `slices.Sorted(seq)` | 1.23 |

### maps / clear

| BEFORE | AFTER | Since |
|---|---|---|
| Loop deleting every entry / rebuilding a map | `clear(m)` (on a slice, zero-fills the elements) | 1.21 |
| Handwritten iteration to clone a map | `maps.Clone(m)` | 1.21 |
| Loop deleting keys matching a predicate | `maps.DeleteFunc(m, f)` | 1.21 |
| Loop collecting keys / values into a slice | `maps.Keys(m)` / `maps.Values(m)` (iterator) | 1.23 |

### errors

| BEFORE | AFTER | Since |
|---|---|---|
| Combining multiple errors via string concatenation | `errors.Join(errs...)` (works with `errors.Is` / `As`) | 1.20 |
| The two-line `var t *MyErr` + `errors.As(err, &t)` | `errors.AsType[T](err)` | 1.26 |

### context

| BEFORE | AFTER | Since |
|---|---|---|
| Carrying the cancel reason in a separate variable | `context.WithCancelCause` + `context.Cause(ctx)` | 1.20 |
| A goroutine that only waits on `<-ctx.Done()` for cleanup | `context.AfterFunc(ctx, f)` | 1.21 |
| Caller cannot tell whether cancellation was a timeout | `WithTimeoutCause` / `WithDeadlineCause` | 1.21 |

### sync / atomic

| BEFORE | AFTER | Since |
|---|---|---|
| Untyped functions such as `atomic.AddInt64(&n, 1)` | `atomic.Int64` / `atomic.Bool` / `atomic.Pointer[T]` | 1.19 |
| `sync.Once` + wrapper closure | `sync.OnceFunc(f)` | 1.21 |
| `sync.Once` used to memoize a computed value | `sync.OnceValue(f)` | 1.21 |
| `wg.Add(1)` + `go func() { defer wg.Done() }()` | `wg.Go(f)` (structurally eliminates the "Add-location mistake" in [golang.md 「Failure Pattern Catalog」](golang.md#failure-pattern-catalog)) | 1.25 |

### strings / bytes / fmt

| BEFORE | AFTER | Since |
|---|---|---|
| `strings.Index` + handwritten slice split | `strings.Cut(s, sep)` | 1.18 |
| `bytes.Index` + handwritten slice split | `bytes.Cut(b, sep)` | 1.18 |
| `append(b, fmt.Sprintf(...)...)` | `fmt.Appendf(b, ...)` (avoids building the intermediate string) | 1.19 |
| `HasPrefix` check followed by a second `TrimPrefix` read | `strings.CutPrefix` / `strings.CutSuffix` | 1.20 |
| Holding a substring blocks releasing the source buffer | `strings.Clone(s)` | 1.20 |
| Handwritten copy to duplicate a byte slice | `bytes.Clone(b)` | 1.20 |
| Only looping over the return value of `strings.Split` | `strings.SplitSeq` / `strings.FieldsSeq` | 1.24 |

### time

| BEFORE | AFTER | Since |
|---|---|---|
| `time.Now().Sub(start)` | `time.Since(start)` | 1.0 |
| `deadline.Sub(time.Now())` | `time.Until(deadline)` | 1.8 |
| Avoiding `time.Tick` in favor of `NewTicker` + `Stop` for GC reasons | Once the reference is gone it is collected, so `time.Tick` is enough | 1.23 |

### testing / net/http / reflect / cmp

| BEFORE | AFTER | Since |
|---|---|---|
| `context.Background()` inside a test | `t.Context()` (cancelled when the test ends) | 1.24 |
| `if` branching on method and path inside a handler | `mux.HandleFunc("GET /items/{id}", ...)` + `r.PathValue("id")` | 1.22 |
| `reflect.TypeOf((*T)(nil)).Elem()` | `reflect.TypeFor[T]()` | 1.22 |
| A fallback `if` chain | `cmp.Or(a, b, c)` (first non-zero value) | 1.22 |

### encoding/json (with application limits)

`json:",omitzero"` (1.24) can omit the zero value of bool / numeric / struct / `time.Time`. However [golang.md 「API Design」](golang.md#api-design) bans `omitempty` because it breaks parsers on the client side. `omitzero` shares the same risk for outward-facing API response types, so keep it to internal structs and config-file serialization.

## Info

- `go fix ./...` auto-fixes many patterns; RECOMMENDED for bulk detections (1.26)
- `new(T, val)` new with initial value (1.26)

## Go 1.26 GODEBUG / stdlib strictification

For DoS mitigation and post-quantum readiness, 1.26 tightens default behavior. When running existing code on 1.26, review the following.

| GODEBUG | default | Impact | revert |
|---|---|---|---|
| `urlstrictcolons` | `1` | `net/url.Parse` rejects `http://localhost:1:2` / `http://::1/`; IPv6 now requires brackets | `=0` |
| `urlmaxqueryparams` | `10000` | Parsing fails above the limit; backported to 1.25.6 / 1.24.12 | `=0` for unlimited |
| `httpcookiemaxnum` | limited | Excessive cookies are rejected; backported to 1.25.2 / 1.24.8 | Raise the setting |
| `cryptocustomrand` | `0` | `crypto/*` silently ignores an `io.Reader` argument (an implementation that passes a mock rand in tests will pass through) | `=1` |
| `tracebacklabels` | `0` | `=1` includes `runtime/pprof` labels in goroutine headers | `=0` |
| `tlssecpmlkem` | new schemes on | Adds PQ key exchanges `SecP256r1MLKEM768` / `SecP384r1MLKEM1024` to TLS 1.3 | Revert the setting |

Added APIs: `net.Dialer.DialTCP` / `DialUDP` accept `netip.AddrPort`; `net/http.ClientConn` added; `reflect.Value.Fields()` / `Methods()` return `iter.Seq2`.

## Go 1.27 new idioms

Released 2026-08-19. Use only in repositories whose `go.mod` is at 1.27 or above. Contains two language-spec changes, so read the constraints below alongside.

| BEFORE | AFTER | Kind |
|---|---|---|
| Package-level generic helper (`Map(s, f)`) | Method with type parameters (`func (s Set[T]) Map[U any](f func(T) U) []U`) | language |
| `Embedded: Embedded{Field: v}` | Write `Field: v` directly in the outer literal | language |
| `strings.LastIndex` + handwritten slice split | `strings.CutLast` / `bytes.CutLast` (returns before, after, found) | stdlib |
| Manually re-populating fields such as `User` after `*dst = *src` | `URL.Clone()` / `Values.Clone()` (net/url) | stdlib |
| External dependency such as `github.com/google/uuid` | Standard `uuid` package (`New` / `NewV4` / `NewV7` / `Parse`) | stdlib |
| `encoding/json` for new JSON code | `encoding/json/v2` | stdlib |

Application constraints:

- **generic method**: interface methods cannot declare type parameters, and a generic method cannot implement an interface. Move only operations that naturally belong on the receiver; leave the rest as package functions
- **promoted field literal**: cannot be mixed with a literal that already targets the same embedded field it was promoted from; pointer-embedded paths are also out of scope
- **`encoding/json/v2`**: swap the import of existing code only when explicitly instructed. v2 emits nil slice / map as `[]` / `{}` and rejects duplicate keys and invalid UTF-8, so wire-level behavior changes even when compilation succeeds. When migrating, start from `DefaultOptionsV1()` (the full v1-compatibility option set) on the `encoding/json` side, pin output and accepted input in tests, then intentionally peel off compatibility options (later options win)
- **`uuid.NewV7`**: the upper 48 bits carry a timestamp so values sort by generation order; prefer v7 over v4 for DB primary keys and identifiers used in index columns

Choosing v2 for a new API satisfies "return `[]` for empty arrays (never `null`)" from [golang.md 「API Design」](golang.md#api-design) by default. Under v1, a nil slice becomes `null`, so an initialization step is required.
