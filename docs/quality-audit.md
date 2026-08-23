# Quality and Performance Audit

Audited 2026-08-22 against the public guides, focused TestBox contracts,
BoxLang 1.16.0 compatibility rules, and the semantic invariants in
`AGENTS.md`. The starting point was 127 passing specs on a clean `main` branch.

## Behavior matrix

| Area | Contract checked | Coverage and result |
| --- | --- | --- |
| Construction and operators | Laziness; success, expected failure, and defect separation; stack safety | Focused core specs cover constructors and operators. `map` now has a direct iterative instruction; stack-safety work remains in the default suite at 10,000 nodes and at 100,000 nodes in benchmarks. |
| Cause, Exit, and Result | Channel preservation, ordered trees, transformations, diagnostics | Added deep iterative Cause predicate and mapping coverage. Existing specs cover value conversion and matching. |
| Context and Layer | Isolation, restoration, deterministic missing-service diagnostics, runtime-local memoization | Existing context specs cover nested success/failure restoration and concurrent sharing. Failed memo entries are now removed before waiters are completed so a later caller cannot observe a stale failed entry. |
| Scope and finalizers | LIFO, idempotence, all exit modes, closed-Scope rejection, sequential cleanup Causes | Existing tests already covered closed-Scope rejection. Added coverage proving an outer cleanup continues when an `onExit` handler throws. |
| Futures and Fibers | Native BoxFuture boundaries, Context inheritance, cancellation, child ownership | Cancellation state is atomic. Added parent-interruption coverage for `all`, `race`, and `firstSuccessOf`, including finalization. |
| Concurrent collection | Ordering, bounded execution, fail-fast, deterministic accumulation | Added mixed expected-failure/defect/interruption accumulation coverage. Completion waits reuse dependent BoxFutures instead of launching new blocking wrapper tasks on every selection round. |
| Schedule and Clock | Retry channel, fixed/spaced timing, timeout, deterministic downstream testing | Existing specs cover recurrence semantics. `TestClock` now locks shared time and sleeper state and has concurrent registration/advancement coverage. |
| Deferred, Semaphore, Queue, PubSub | Laziness, interruption, backpressure, shutdown, ownership | Focused specs cover each documented state transition and failure tag. No public behavior changes were needed. |
| Observer | Diagnostic isolation and terminal-event rules | Existing specs cover observer failure containment and recovered versus unhandled defects. |
| Module and packaging | Activated imports, setting override, supported runtime metadata, excluded development assets | Module specs, executor-override suite, and `box package show` remain the verification contract. |

## Findings and disposition

| Classification | Finding | Impact | Disposition |
| --- | --- | --- | --- |
| Correctness/concurrency | Fiber interruption and active-future references lacked explicit cross-thread memory semantics. | High | Replaced with JDK atomics. |
| Correctness/concurrency | Concurrent operators did not expose their active `asyncAny` wait to Fiber cancellation. | High | Register and clear the native wait through `FiberControl`; normalize cancellation through `Cause::interrupt`. |
| Correctness/concurrency | `TestClock` mutated published test-support state from runtime and test threads without synchronization. | High | Added a lock and complete due futures after releasing it. |
| Correctness/concurrency | Failed Layer memo completion preceded removal, leaving a small stale-failure window. | Medium | Remove conditionally before completing existing waiters. |
| Performance | `map` allocated a succeeding Effect for every mapped value at interpretation time. | High | Added a dedicated `Map` instruction and frame. |
| Performance | Synchronous boundaries resolved an executor they never use. | Medium | Default executor resolution is now cached and lazy. |
| Performance | Cause predicates collected arrays and deep Cause mapping was recursive. | Medium | Use iterative traversal without predicate allocations. |
| Performance | Repeated completion selection created fresh blocking wrapper tasks. | Medium | Attach one dependent completion future per child and reuse it. |
| Missing coverage | Parent cancellation, mixed accumulation, deep Cause mapping, throwing finalizers, and concurrent TestClock use were not explicit. | High | Added focused regression specs. |
| Low-value duplication | Four specs carried equivalent polling loops. | Low | Consolidated under `tests/resources/AsyncTestSupport.bx`. |
| Test runtime | The default suite used the same 100,000-node scale as the benchmark. | Medium | Default correctness depth is 10,000; benchmark coverage remains 100,000. |

## Feature-gap review

No public API addition is justified by this pass. Stream/Sink integration,
Layer dependency graphs, replay or dropping PubSub policies, and additional
coordination primitives all require separate contracts. They remain explicitly
out of scope rather than being inferred from upstream Effect APIs.

## Verification outcome

The completed suite contains 132 passing specs and runs in approximately
3.8 seconds on the audit machine, down from the 13.8-second starting run. The
executor-override module suite and package metadata inspection also pass.

The original one-shot benchmark readings and the new warmup/five-sample
medians are not identical methodologies, so they should be treated as a strong
directional comparison rather than a published absolute ratio:

| Scenario | Starting reading | Current repeated median |
| --- | ---: | ---: |
| 100,000 maps | 9,600 ms | 4,108–4,125 ms across three invocations |
| 100,000 flatMaps | 8,292 ms | 7,903–7,959 ms across three invocations |
| 10,000 Context provisions | 5,247 ms | 2,654–2,675 ms across three invocations |
| 256 delayed concurrent branches | 747 ms | 117–131 ms across three invocations |
| 128 branches sharing one Layer | 823 ms | 90 ms median |

Future comparisons should use the repeatable methodology in
`benchmarks/README.md` on both sides of a change.
