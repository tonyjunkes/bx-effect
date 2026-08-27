# Quality and Performance Audit

Audited 2026-08-26 against the roadmap specification, public guides, focused
TestBox contracts, BoxLang 1.16.0 compatibility rules, and the invariants in
`AGENTS.md`. The runtime optimization work started from 179 passing specs.

## Behavior matrix

| Area | Contract checked | Coverage and result |
| --- | --- | --- |
| Focused operators | Laziness, ordering, expected failure, defect, interruption, handler failure, and Cause preservation | Core and async specs cover `forEach` accumulation, `tapError`, `tapCause`, `exit`, `zip`, and `zipWith`. |
| Managed runtime | Lazy and shared Layer build, failed-build retry, private Context, per-run Scope, close races, interruption, LIFO cleanup, native futures, and observer containment | Fifteen focused specs cover successful, expected-failure, defective, blocking, and concurrent lifecycles. |
| Stream | Fresh cursors, pull demand, all Cause channels, Context, cleanup, Queue/PubSub ownership, deterministic Clock use, stack safety, and bounded finite processing | Twenty-one focused specs cover every constructor/operator family and all source exit modes. Deep concat descriptions are normalized to avoid quadratic left-chain traversal. |
| Runtime cancellation | Active future cancellation, between-instruction observation, child termination ordering, and interruptible native condition waits | Fiber control tracks an executor thread only while the interpreter is inside Semaphore, Queue, or PubSub instructions; focused regressions prove loser termination before recovery and child termination before root resource release. |
| Runtime kernel | Stack safety, exact LIFO continuation order, failure unwinding, and profiler-confirmed interpreter cost | A per-run JDK `ArrayDeque` removes the BoxLang Array `pop()` hotspot while keeping the single BoxLang interpreter and public API unchanged. |
| Native integration | Existing logger, BoxCache, HTTP, JDBC, Scheduler, and file ownership | `LoggingObserver` has focused containment coverage. The other facilities remain documented recipes over native APIs rather than duplicate subsystems. |
| Module and packaging | Activated imports, executor override, supported runtime matrix, package exclusions, and installed use | Module specs and the isolated consumer import every supported public class through `@bxEffect`. CI performs package inspection and the clean install on minimum/latest BoxLang. |

## Findings and disposition

| Classification | Finding | Impact | Disposition |
| --- | --- | --- | --- |
| Missing lifecycle boundary | Per-run `EffectRuntime` could not safely retain one scoped application Layer. | High | Added explicit, lazy `ManagedRuntime` ownership with retryable build state and idempotent close. |
| Missing multi-value abstraction | Native collections did not combine lazy async demand, Cause, Context, and Scope cleanup. | High | Added the approved pull-based Stream MVP using native arrays and `Attempt`. |
| Correctness/cancellation | Canceling a Fiber blocked in a native Queue/PubSub/Semaphore condition could complete the public future before the worker finalized. | High | Track and interrupt only the known blocking worker section, plus retain a separate internal termination future. |
| Correctness/resource safety | Parent Scope cleanup and fail-fast recovery could proceed after requesting child cancellation but before the child interpreter terminated. | High | Make child creation/admission atomic, stop admission at the parent boundary, and await internal child termination before recovery or root resource release. |
| Correctness/cancellation | A cancellation request between interpreter instructions could allow the next user continuation to run. | High | Observe each Fiber cancellation once in the iterative interpreter and unwind it through `Cause::interrupt`. |
| Retention/concurrency visibility | Completed child Fibers, canceled TestClock sleepers, and lock-free subscription shutdown reads could retain state or observe stale state. | Medium | Remove children on internal termination, compact canceled sleepers, and publish subscription shutdown with `AtomicBoolean`. |
| Performance | Left-associated Stream concat repeatedly traversed prior cursors. | High | Normalize concat leaves into one sequential cursor; the 2,000-source stack-safety spec now completes linearly. |
| Performance | The interpreter continuation stack spent most sampled CPU in BoxLang Array removal. | High | Replaced only the local stack with `ArrayDeque`; isolated Map/FlatMap medians improved 3.87x/1.69x with full semantic parity. |
| Release confidence | Workspace-mapped tests did not prove installed module imports or package exclusions. | High | Added an isolated consumer fixture and minimum/latest CI install check. |
| Platform duplication risk | Cache, HTTP, JDBC, Scheduler, files, and logging already have BoxLang ownership models. | Medium | Added native integration recipes and only one thin diagnostic logger adapter. |

## Verification outcome

The canonical suite contains 181 passing specs across 17 bundles, with no
failures or errors. Focused runtime, stream, async, module, and observability
suites also pass independently. The executor override, package inspection, and
isolated installed-consumer checks are part of the handoff contract.

The complete runtime optimization evidence and terminal Phase 1 decision are
recorded in [Runtime Optimization Decision](runtime-optimization.md).

Benchmarks are local correctness-checked comparison tools, not CI gates. This
machine's roadmap-specific readings used one warmup and five samples:

| Scenario | Result |
| --- | ---: |
| 128 repeated ManagedRuntime boundaries | 352 ms median; one build and one release across all samples |
| 100,000 mapped Stream values | 494 ms median |
| 10,000 single-value pulls | 4,369 ms median |
| 1,000 Queue-backed values | 1,059 ms median |
| Blocked Stream interruption | 8 ms median |
| Indicative retained allocation for collecting 100,000 mapped values | 123,027,760 bytes |

Retained allocation is JVM-state-sensitive and should be compared only on the
same runtime and machine. Future performance work should use the repeatable
methodology in `benchmarks/README.md` and preserve EffectRuntime, Scope, Cause,
and Context semantics.
