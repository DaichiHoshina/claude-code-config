# Silent Failure Detection

Detect error suppression, empty catch blocks, inappropriate fallbacks.

## Checklist

| Check | Bad example | Level |
|-------|-------------|-------|
| **Empty catch / except** | `catch (e) {}` / `except: pass` | Critical |
| **Error suppression** | Go `_ = err` / `if err != nil { return nil }` (no log) | Critical |
| **Broad catch + log only** | Catch all, log, swallow | Critical |
| **Inappropriate fallback** | API fails → return empty array as success | Critical |
| **Unhandled Promise.catch** | `.catch(() => {})` / unhandled rejection | Critical |
| **Boolean return masks cause** | `success bool` only, root cause hidden | Warning |
| **Error type info lost** | `throw new Error(String(e))` loses stack | Warning |
| **Default suppresses error** | `parseInt(x) \|\| 0` (hides NaN) | Warning |
| **Error never surfaces** | 例外は伝播するが、到達先で UI にも log にも現れない (握り潰しはないので上の行では拾えない)。error の発生点から user が気づく地点までの経路を確認する | Warning |

## Exclusions (false-positive sources, with measurements)

Applying the checklist mechanically hits normal repo idioms. Do not flag the following.

| Exclusion | Rationale and measurement |
|---|---|
| Branches returning `err = nil` for "expected absence" | The shape that receives `errors.Is(err, sql.ErrNoRows)` and returns `nullable.None` or an empty struct with nil error. This is not suppression but the specified normal case. In a measured repo there were 60 NoRows branches, all of the same shape. Flagging as Critical makes review unworkable |
| `\|\| 0` not paired with `parseInt` / `Number` | The checklist targets only `parseInt(x) \|\| 0` that hides NaN. In a measured repo all 45 occurrences of `\|\| 0` were defaults for optional values (`a?.b \|\| 0`), and 0 came from `parseInt`. Do not pick up a bare `\|\| 0` |
| Re-wrapping an error that the caller does not swallow | `fmt.Errorf("...: %w", err)` is propagation, not suppression |

When judgment is unclear, first decide whether entering the branch means an abnormal state or a state allowed by the spec. If the latter, it is not suppression.

## Fix principles

- Error must **propagate OR be handled** (no suppression)
- If handled: express cause & recovery via type (Result, Either)
- Logging necessary but insufficient (caller must decide action)
