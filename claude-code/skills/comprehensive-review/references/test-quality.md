# test-quality

How strictly a test pins the contract, and whether its data says what it means. Read when the diff touches test files.

**Scope.** `review-criteria.md` 「Docs & Testing」 already covers the absent assertion, over-mocking (everything mocked, no real behaviour exercised), isolation, and coverage gaps. This file covers what it does not: a mock that *is* justified but matches too loosely, and test data that hides the point of the test. **A repo rule always wins** — many repos pin matcher policy and fixture naming themselves, and where they do, cite the repo rule instead of this file.

## Matcher strictness

A mock expectation is a written contract. `Any()` on an argument the test already knows erases that argument from the contract: the call passes whatever the implementation happens to send, including a wrong value introduced later.

| Check | Bad | Level |
|---|---|---|
| **Deterministic argument matched as Any** | the test constructs the value, then passes `gomock.Any()` for it | Critical |
| **Every argument is Any** | `EXPECT().Save(Any(), Any())` — asserts only that the method was called, not with what | Critical |
| **ctx matched as Any where the ctx is known** | the test owns the `ctx` it passes into the use case, yet matches `Any()` | Warning |
| **Return-only stub for a call whose arguments carry the behaviour** | the assertion under test is *what was written*, but only the return value is pinned | Critical |
| **`DoAndReturn` that discards its arguments** | the closure ignores the parameters and returns a constant, where a matcher would have expressed it | Warning |
| **Loose matcher hiding a changed call** | matcher was widened in the same diff that changed the call site, so the test cannot fail | Critical |
| **Loosened because "this case only checks the error path"** | the stub returns an error, so its arguments were left as `Any()` even though the test constructed them | Critical |

**What the case asserts does not narrow the contract.** A stub that returns an error still receives the arguments the test built, and leaving them as `Any()` means a defect in assembling those arguments slips through the very case meant to exercise the failure. Fixability decides the matcher, not what the case is named after — if the test can construct the value, pin it, on the success path and the error path alike.

**Counting procedure.** Do not judge by impression. Count the added expectations and the loose ones side by side, and put both numbers in the finding:

```
git diff origin/main...HEAD -- '*_test.go' | grep '^+' | grep -c '\.EXPECT()'
git diff origin/main...HEAD -- '*_test.go' | grep '^+' | grep -c 'gomock\.Any()'
```

A finding that says "Any is overused" without the ratio is not actionable. One that says "of 231 added expectations, 133 hold `Any()` and 95 of those are the ctx the test itself created" is.

## Test data

Test data has one job: make the reader see why this input produces that output. Data that merely satisfies the compiler does the opposite.

| Check | Bad | Level |
|---|---|---|
| **Expected value transcribed from the implementation** | the expectation restates the code's arithmetic or string building, so both change together and the test can never fail | Critical |
| **Unexplained significant value** | a boundary or threshold appears as a bare literal with nothing tying it to the rule under test | Warning |
| **The point buried in full-struct literals** | every field is populated on every case, so the one field that drives the branch is invisible | Warning |
| **The same literal repeated across cases** | identical construction copied into each case; a change to the type edits N places and they drift | Warning |
| **Field values that contradict their meaning** | `IsShipped: true` alongside a nil shipped_at, encoding a state the domain cannot reach | Warning |
| **Fixture built inline where the repo prescribes a fixture file** | rows constructed in the test body in a repo whose rule names a per-test fixture file | follow the repo rule |

**What good looks like.** Vary only the field under test between cases and let a shared base supply the rest, so the diff between two cases *is* the reason they differ. Derive the expectation from the specification, not from the code path. Give a significant number a name or a comment stating the rule it comes from.

## Inspection procedure

1. **Count first.** Run the two counts above and keep the numbers for the finding.
2. **For each added expectation, ask what would still pass.** Name a wrong value the current matcher would accept. If you can name one and the test claims to cover that behaviour, it is a finding.
3. **For each expected value, ask where it came from.** Specification or implementation. If reading the implementation was required to write it, the test asserts the code against itself.
4. **Diff two cases of a table-driven test.** If more than the field under test differs, the extra fields are noise; if nothing meaningful differs, one of the cases is not pulling its weight.
5. **Check the repo rule before writing the finding.** Where the repo pins matcher policy or fixture naming, quote that rule as the authority.
6. **State the outcome of every step, including the empty ones.** "Compared two table cases, nothing to report" and skipping the step are indistinguishable to the reader otherwise, and the data half of this file goes unexamined the moment the matcher half produces findings.

## Exclusions (false-positive sources)

| Exclusion | Rationale |
|---|---|
| `Any()` for a value the test genuinely cannot fix | Generated IDs, timestamps taken inside the implementation, a ctx created downstream or in another goroutine. The test cannot name what it never sees. **This does not cover a value the test harness merely fails to hand over** — when a `setup` closure matches `Any()` only because its signature takes no ctx, the value is fixable and the finding is that the harness should pass it. Say so instead of excluding |
| `Any()` where identity is deliberately irrelevant | A pass-through argument the assertion is not about. Being uninteresting is a reason, but it should be visible from the test's intent. **Sitting on an error path is not what makes an argument irrelevant** — that is a statement about the return value, not the arguments |
| Struct literals per case in a table-driven test | This is the idiom, not duplication. Report only when the repeated part dwarfs the varying part |
| A literal expectation for a value with no derivation | Not every expectation has a formula behind it. The defect is transcribing the implementation, not writing a constant |
| Exhaustive field population in a serialization or mapping test | When the subject *is* the full mapping, every field is the point |
| Existing tests in the file left as they are | Matching a legacy style in surrounding code is the minimal-diff rule working as intended. Raise the pattern once, against the newly added tests only |
