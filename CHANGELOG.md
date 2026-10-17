# Changelog

All notable changes to BX Effect are documented here.

## 1.3.2 - 10-16-2026

- Add runnable standalone WireBox and ColdBox recipes with explicit ManagedRuntime
  mappings and lazy Layers that reuse container-owned application services.
- Close active Effect work before framework service teardown, including ColdBox
  reinitialization, and retain expected validation errors as HTTP 400 responses.
- Add standalone injection/shutdown coverage and real HTTP handler, reinit, and
  application-end checks through BoxLang MiniServer in PR and release verification.
- Pin development-only ColdBox for BoxLang 8.3.0+36 and its HTTP compatibility
  support. The kernel and production dependencies remain independent of the frameworks.

## 1.3.1 - 10-14-2026

- Add runnable application-owned ManagedRuntime, native BoxCache loading/TTL,
  and native validation recipes with integration coverage.
- Verify JDBC rollback, nested synchronous Effects, async context visibility,
  explicit savepoints, failure values, and cooperative interruption with real
  in-memory Derby transactions.
- Replace the shared JDBC connection example with named datasource bindings;
  document native transaction ownership and rollback boundaries.
- Pin a development-only Derby driver and exclude installed development modules
  from packaging. No public Effect API or production dependency changes.
- Update the development TestBox dependency to stable 7.2.0+21.
- Raise the minimum supported BoxLang version to 1.18.0 and update both CI matrices.

## 1.3.0 - 10-12-2026

- Add `Effect::scoped(program)` for local resource and child-Fiber lifetimes.
  Interrupt and await children, then release resources in LIFO order before
  following work or outer recovery, retaining all cleanup failures.
- Isolate Layer memoization per local lifetime while sharing builds with its
  children and preserving inherited Context and ManagedRuntime services.
- Add `Schedule.maxDelay(duration, unit)` for capped retry/repeat waits,
  including deterministic fixed-schedule anchors and finite retry composition.
- Cover local interruption, asynchronous cleanup, Layer ownership, and capped
  TestClock retry timing; benchmark deeply nested local scopes for stack safety.

## 1.2.0 - 10-12-2026

- Propagate Stream element demand through transformations, resources, provisioning,
  recovery, grouping, and concatenation. Unrequested array callbacks no longer run;
  see the Stream guide for the side-effect timing compatibility note.
- Execute sequential `forEach` in the iterative interpreter and collect concurrent
  completions through operation-local native BoxFuture notifications.
- Document cooperative timeouts that await work termination and cleanup, and
  preserve fatal native rejection through both collection completion strategies.
- Strengthen sequential cancellation, cleanup, and concurrent coordination
  coverage. Add collection and selective Stream measurements.
- Verify BoxLang 1.16.0 alongside latest/snapshot, verify main updates, and publish
  only explicit matching version tags without forced republishing.

## 1.1.0 - 9-23-2026

- Add `acquireUseRelease`, `fromExit`, `failCause`, `die`, and `catchTags`, plus
  sequential Stream `takeWhile`, `scan`, and `grouped`.
- Retain failed child cleanup through races, fail-fast collections, root shutdown,
  and managed runtime shutdown. Serialize worker interruption with wait
  unregistration.
- Reject null Queue and PubSub messages lazily, align ServiceTag equality and
  hashing with native BoxLang keys, and use a monotonic live Clock for recurrence.
- Improve Cause traversal, discarded concurrent collections, and deep Stream
  concatenation without changing their public results.
- Define the 1.x public compatibility boundary, check TestBox JSON totals in
  CI, and test on BoxLang `latest` and `snapshot`. Verify installed-module
  activation before publication.

## 1.0.0 — 09-08-2026

Initial release of BX Effect for BoxLang 1.16.0+ and Java 21+, bringing lazy
workflow composition, explicit error handling, structured concurrency, and
resource safety to BoxLang applications. Inspired by Effect, with a dedicated
BoxLang API built on native runtime facilities.

### Effects and error handling

- Lazy constructors and reusable composition through `map`, `flatMap`, `tap`,
  `zip`, and `zipWith`, with synchronous, BoxFuture, and Fiber execution boundaries.
- Distinct expected-failure, defect, and interruption channels represented by
  immutable `Cause` trees and `Exit` outcomes; `Result` for expected-error values
  and integration with native `Attempt` for presence and absence.
- Expected-error recovery and transformation, tagged and conditional recovery,
  explicit full-Cause handling, and outcome inspection with `tapError`,
  `tapCause`, and `exit`.

### Resources and services

- Scoped acquisition and release, `ensuring`, and `onExit`, with idempotent LIFO
  finalization on every exit and preservation of cleanup failures.
- Immutable `Context`, named `ServiceTag` identities, and lazy, composable
  `Layer` recipes with scoped services, nested Context restoration, deterministic
  missing-service diagnostics, and runtime-local sharing across child Fibers.
- Explicitly owned `ManagedRuntime` for one application Layer shared across
  repeated runs, including concurrent first-build sharing, retry after failed
  builds, and shutdown that waits for run cleanup before releasing services.

### Concurrency and coordination

- Native BoxFuture integration and BoxLang executor reuse, with non-blocking
  `runFuture` calls, scoped child Fibers, and best-effort interruption.
- Concurrent `all` and `forEach` with configurable limits, fail-fast defaults,
  and failure accumulation in input order; first-completion racing and
  first-success selection.
- One-shot `Deferred`, scoped Semaphore permits, bounded and unbounded Queue
  buffers, and PubSub broadcast with explicit subscription ownership,
  interruptible backpressure, and shutdown semantics.

### Schedules and streams

- Expected-error retries, successful repetition, sleep, and timeouts, with
  recurrence counts, spaced and fixed timing, exponential backoff, jitter,
  and composable Schedule policies.
- Injectable live Clock and synchronized `TestClock`, shipped for downstream
  deterministic testing without a TestBox dependency.
- Reusable, demand-driven `Stream` descriptions with sequential transformations,
  effectful mapping, filtering, concatenation, recovery, and collection, folding,
  or draining consumers. Each consumption owns a fresh cursor and cleans up on
  completion, failure, early termination, or interruption.
- Resource-backed Stream sources and Queue/PubSub bridges with explicit ownership.

### Diagnostics, performance, and verification

- Optional runtime observer and native logging adapter for execution, Fiber,
  retry, cleanup, and unhandled-defect events; observer failures cannot alter
  outcomes or prevent cleanup.
- Iterative, stack-safe interpretation with a JDK `ArrayDeque` continuation
  stack, direct `map` handling, lazy executor resolution, and reusable concurrent
  completion futures. Cause inspection, transformation, and rendering are also
  stack-safe.
- Correctness-checked benchmarks for deep composition, async work, concurrency,
  Layer sharing, managed runtimes, Streams, Context, and Scope, with warmup,
  monotonic timing, and minimum/median reporting.
- Focused TestBox contracts and CI for BoxLang `1.16.0` and `latest`, including
  executor overrides, package inspection, and isolated installed-consumer checks.
- Public API inventory and guides for error handling, resources, services,
  concurrency, Streams, scheduling, observability, native integrations,
  incremental adoption.

### Correctness fixes included in 1.0

- Correct native live delays and zero-duration TestClock futures, and handle
  fixed-schedule overruns without replaying missed intervals.
- Protect successful acquisition handoffs from interruption and release PubSub,
  Semaphore, and Stream resources before following work or outer recovery.
- Memoize Layer output bindings without leaking the first caller's input Context.
- Strengthen Fiber cancellation so it reaches active nested futures and known
  interruptible waits while preserving interruption as a distinct failure channel.
- Add focused regressions for timing, acquisition, cleanup, and Layer isolation,
  plus elapsed-time lower-bound checks for delay benchmarks.
