# layer-boundaries

What each layer must know, and must not know (DDD / Clean Architecture / CQRS). The `architecture` lens runs by default on every code diff, so this file is the judgement table behind it.

**This file does not restate the layer model.** `guidelines/design/clean-architecture.md` is loaded with this skill (`requires-guidelines`) and is canonical for the layer table, the dependency inversion rule, how to measure the dependency graph with a command, and how to weigh the ideal form against repo convention. Read it there and do not duplicate it in a finding. What follows is only what that guideline does not give a reviewer: the negative side of each boundary, where a decision belongs, and the false positives.

## What each layer must NOT know

The canonical guideline states what each layer depends on. For review, the useful half is the prohibition.

| Layer | Must not know |
|---|---|
| **domain** (entity / aggregate / value object / domain service) | DB / SQL / ORM, HTTP / gRPC types, framework and DI container, repository implementations, other bounded contexts' internals, request-scoped context values, logging and metrics infrastructure, clock and randomness (inject them) |
| **application** (use case / command handler / query handler) | Concrete adapter implementations, HTTP request / response types, presentation formatting, SQL and ORM (with the CQRS read-lane exception below), **the business rule decision itself** |
| **interface adapter** (handler / presenter / controller) | domain model internals, SQL, business rule decisions, which adapter implementation is wired in |
| **infrastructure** (repository impl / query impl / external client) | application, interface adapter, **business rule decisions** |

A port declared in the infrastructure package and imported inward inverts nothing and is a violation even though it is "an interface". Frameworks stay in infrastructure; decorator-style annotations on inner-layer classes are the tolerated exception.

## The extraction test

When placement is genuinely unclear, apply this: **could you lift the domain layer out as-is, throw away the entire infrastructure, and rebuild it on a different database and framework without editing a line of domain code?**

If the answer is no, the domain has absorbed something that belongs outside. This settles most arguments faster than reasoning about layer names, and it is the test to cite in the review comment.

## Where a decision belongs

The line between "input validation the use case may hold" and "a business rule that belongs to domain" is the most common source of both violations and false positives. Decide by what the judgement needs to look at.

| The judgement looks at | Belongs to | Example |
|---|---|---|
| One input field alone (required, type, length, range, format) | use case `Input.Validate()` | `len(name) > 0`, `page >= 1` |
| One entity's own state and fields | that entity / aggregate | "a cancelled order exposes no payable amount" |
| Relationships or states **across** entities | **domain service** | "this size code belongs to that product" |
| What is permitted in a given state | entity or domain service | "a shipped order can no longer choose a size" |
| Whether a transition between two states is allowed | the entity holding that state | "has_size cannot go from true back to false" |
| Whether a combination of inputs is valid in business terms | domain service | "has_size products require a size, others must not carry one" |
| Which adapter, transaction, or retry to use | application | "wrap these two writes in one transaction" |

**Name the destination.** A rule evicted from a use case rarely fits inside a single entity — that is usually why it ended up in the use case. A comment saying "move this to domain" without naming the domain service tends to get ignored.

**An application service operates on scalar types and delegates.** Fetching, looping, assembling an Output, opening a transaction, and calling a domain function are its job. If it reaches into a domain model's fields to compute a verdict, the verdict belongs inside the model.

## CQRS lane rules

`guidelines/design/cqrs.md` is not loaded on a normal `/review`, so keep these here. Do not import its "a command returns an id only" rule — that guideline marks it as a false-positive source against implementations that also return an Output.

**The read lane is deliberately allowed to skip layers.** A query handler may query the database directly, without loading aggregates, without a repository, and without mapping to domain entities. That is the point of CQRS, not a layering defect. Report SQL in a query handler only when the repo's own convention requires a query port — many do.

| Check | Bad | Level |
|---|---|---|
| Query lane mutates state | query handler performs INSERT / UPDATE / DELETE, calls a command handler, or writes an audit row | Critical |
| Command decides from the read model | command handler reads a denormalized / eventually-consistent read model to make its verdict | Critical |
| Query reaches into the command lane | query imports the command lane's domain, aggregates, or repositories | Critical |
| Invariant enforced on one side only | validation exists on the read path but not on the write path, so a direct write bypasses it | Critical |
| Query returns write-model entities | query handler returns domain aggregates instead of a read DTO | Warning |

The asymmetry to remember: **the read lane may skip the domain; the write lane may not.** Every rule protecting an invariant must exist on the write path, because that is the only path that can break it.

## Checklist

| Check | Bad | Level |
|---|---|---|
| **Inward import violated** | domain imports infrastructure / HTTP / ORM / framework packages | Critical |
| **Port declared outward** | the interface lives in the infrastructure package and inner layers import it | Critical |
| **Business rule in application** | use case holds `if` / `switch` branches deciding what is permitted, instead of calling a domain function | Critical |
| **Business rule in infrastructure** | repository impl decides validity beyond mapping and persistence | Critical |
| **One rule, two implementations** | the same judgement, serving the same purpose, is written twice in different layers, each reading its own data source (see the exclusion before reporting) | Critical |
| **Concrete injected past the port** | use case field or argument typed as an impl instead of its interface | Critical |
| **Ambient dependency in domain** | domain reads the clock, generates randomness or IDs, or pulls values out of a request context | Warning |
| **Domain leaked outward** | handler or response type exposes a domain model's internal structure directly | Warning |
| **Infrastructure error crossing inward unmapped** | a driver / ORM error type propagates into an application or domain signature instead of being mapped at the boundary | Warning |
| **Anti-corruption layer missing** | another bounded context's or a legacy system's model is consumed directly in domain or application code | Warning |

## Inspection procedure

1. **Imports first.** For every changed file, read its import block and place the file in a layer. An import pointing outward is a violation on its own and needs no further reasoning. To claim a zero, follow the measurement command in the canonical guideline — a grep non-hit is not a count.
2. **Then the branches.** For each `if` / `switch` added to a use case or a repository impl, ask which row of "Where a decision belongs" it falls in. Anything past the first row belongs to domain — and name the destination.
3. **List the guard functions by name.** In every changed use case, enumerate the private methods and helpers named `check*` / `validate*` / `ensure*` / `can*` / `is*`, and put each one through the table above. This class of function is where evicted rules accumulate, and a short one reads as harmless orchestration unless it is judged deliberately.
4. **Then look for the twin.** When a new rule appears, grep the rule's *subject* (the field or the concept, not the function name) across the other layers, then compare the purposes of what you find.
5. **Then run the extraction test** on anything still unclear.
6. **Do not treat an existing placement as a precedent.** A validation loop already sitting in a use case is not evidence that the use case is where new rules go.

## Exclusions (false-positive sources)

| Exclusion | Rationale |
|---|---|
| Infrastructure importing domain models | Mapping rows to models requires the model type. This is the specified direction, not a violation |
| Application orchestration that reads as logic | Fetching, looping, assembling an Output, opening a transaction, and calling a domain function are the application's job. Only the decision itself has to move. **A branch that merely compares field values and declares a result forbidden is not orchestration**, however short it is and whatever I/O sits around it — that is the decision, and it moves |
| Format validation in `Input.Validate()` | Required / length / range checks stay in the application layer. See "Where a decision belongs" |
| A query handler holding SQL | Legitimate under CQRS. Report it only when the repo's convention requires a query port |
| **Duplicated conditions with different purposes** | Cutting a dependency legitimately leaves the same condition in two places — one side judging what to display, the other emitting an inconsistency log. When the purposes differ, do not force sharing; the canonical guideline says so explicitly. Report the duplicate only when both copies serve the same purpose and differ merely in the data source they read |
| Re-validation at the write boundary | Checking again on the primary DB before persisting is defence in depth, not duplication — **provided both call the same domain function**. Duplication is about two implementations, not two call sites |
| Domain depending on another domain package in the same context | Inner-layer coupling within one bounded context is normal. Only cross-context reach needs an anti-corruption layer |
| Placement that follows a consistent repo convention | The canonical guideline's rule applies: never yield on the direction of dependency, but pull responsibility granularity toward the convention, and count the distribution before claiming the convention is otherwise |
