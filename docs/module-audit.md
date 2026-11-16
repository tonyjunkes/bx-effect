# Module audit

Audit against [AGENTS.md](../AGENTS.md),
the [accepted review scope](module-review.md), the [public inventory](public-api.md),
subsystem guides, callers, and focused specs. The discovery sections below
record observations against the original implementation; their source line
numbers describe that revision. Implementation dispositions and verification
follow at the end. Initial stable-runtime setup was blocked by incompatible
published ColdBox bytecode; the checked source-preparation runner resolved it.

## Discovery findings

### F1 — Closing during a failed application build can discard release failures

**Source-supported; reproduce with gated acquisition before implementation.**
Start a managed Layer acquisition, begin `closeFuture()` while acquisition is
gated, then let acquisition return a resource whose release fails. Interruption
causes the build to fail after registering release. `finishBuildAttempt()` closes
that failed build Scope, appends its release failure to the build Exit, and clears
`managedScope`. `completeClose()` awaits `buildToAwait.get()` but discards that
Exit. The canceled request waiters do not own the build's cleanup either.
Consequently close can return success despite failed release of an application
resource. Sources: [build cleanup and clearing](../models/effect/ManagedRuntime.bx#L262),
[discarded build outcome](../models/effect/ManagedRuntime.bx#L295),
[shared build Scope](../models/effect/ManagedRuntime.bx#L234), and the
[cleanup-retention contract](resources.md).

Retain build-cleanup provenance for the closing owner without replaying ordinary
build/business failures or interruption as cleanup. Add a deterministic
close-during-build case asserting release once, all remaining finalizers run,
the release failure appears once in close, and no managed service is released
before run finalization. Existing [ManagedRuntime specs](../tests/specs/runtime/ManagedRuntimeSpec.bx)
cover failed-build retry and active-run/service release failures separately,
but do not exercise this combined handoff.

### F2 — Accepted Schedule units can fail only on the live Clock

**Source-supported on the intended BoxLang 1.19.0 baseline.**
`Schedule.spaced(1, "s")` and singular units such as `"second"` pass
`Schedule.delayed()` validation; ordinary spaced/exponential `next()` returns
the original unit. TestClock accepts it. Live `Clock.sleep()` forwards it to
`BoxFuture.delayedExecutor()`, whose native conversion requires a Java TimeUnit
enum spelling. The recurrence therefore defects instead of waiting. Adding
`and(Schedule.recurs(1))` can conceal the problem because composition converts
the delay to milliseconds. Sources: [Schedule validation/decisions](../models/effect/Schedule.bx#L238),
[accepted aliases](../models/effect/Schedule.bx#L331),
[live Clock](../models/effect/Clock.bx#L25),
[TestClock](../models/effect/testing/TestClock.bx#L110),
[native delayedExecutor](https://github.com/ortus-boxlang/BoxLang/blob/v1.19.0/src/main/java/ortus/boxlang/runtime/async/BoxFuture.java#L404),
and [native enum conversion](https://github.com/ortus-boxlang/BoxLang/blob/v1.19.0/src/main/java/ortus/boxlang/runtime/types/util/DateTimeHelper.java#L581).

Normalize accepted units at the native boundary, preserving the accepted public
inputs. Test uncomposed spaced/exponential policies with aliases on both clocks;
the existing [clock](../tests/specs/schedule/ClockSpec.bx) and
[schedule](../tests/specs/schedule/ScheduleSpec.bx) specs use plural native units
or normalizing composition for the relevant live paths.

### F3 — A canceled close waiter poisons every subsequent close observation

**Source-supported; runtime reproduction still needed.**
Hold managed release on a gate, obtain `first = managed.closeFuture()`, and
cancel `first` (or give it a mutating native timeout). Both initial and later
calls expose `variables.closeOutcomeFuture` itself. `managed.close()` then
returns a defect immediately through its catch while release is still blocked;
later callers cannot await the actual close Exit through this field. This
violates the documented awaited/idempotent close boundary. The shutdown supplier
may continue; this finding does **not** establish that canceling the returned
BoxFuture stops it. Sources: [shared close future](../models/effect/ManagedRuntime.bx#L136),
[close contract](managed-runtime.md#closing), and native
[CompletableFuture cancellation/timeout behavior](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/CompletableFuture.html).

Keep shutdown completion private and give public waiters cancellation-isolated
views, as Deferred/build waiters already do. The existing
[close-before-build spec](../tests/specs/runtime/ManagedRuntimeSpec.bx#L183)
asserts identical future objects; review that assertion against the actual
contract of one shared shutdown/completed Exit. Cover canceling one waiter while
another still awaits all release work and receives the final cleanup outcome.

## Hypotheses requiring focused reproduction

- **H1 — Fast failed-build publication race.** In
  [contextBuildAccess](../models/effect/ManagedRuntime.bx#L237), the termination
  callback is attached before the three build fields are assigned. If the build
  has already terminated, `finishBuildAttempt()` can execute inline under the
  reentrant lock, clear those fields after failure cleanup, and return; the
  following assignments then reinstall the failed future. Later runs would reuse
  failure indefinitely instead of retrying. Native
  [BoxFuture.then](https://github.com/ortus-boxlang/BoxLang/blob/v1.19.0/src/main/java/ortus/boxlang/runtime/async/BoxFuture.java#L291)
  uses non-async `thenApply`. Prove the completed-before-attachment ordering with
  a controlled fixture or a bounded repeated immediate failed-then-successful
  Layer build. Existing retry specs do not force it. Any fix should publish an
  attempt identity before installing callbacks and prevent stale completion from
  clearing a newer attempt; changing to async callbacks alone changes scheduling.
- **H2 — Queue cancellation after signal can strand another waiter.** With two
  empty-Queue takers waiting, offer one value, then interrupt the signaled taker
  before it reacquires the lock/checks control. [takeNative](../models/effect/Queue.bx#L168)
  can return interrupted without consuming or signaling another taker, leaving
  an item buffered while the second taker sleeps indefinitely. The symmetric
  case is two blocked producers and one freed slot in
  [offerNative](../models/effect/Queue.bx#L134). OpenJDK's
  [ConditionObject.await](https://github.com/openjdk/jdk/blob/jdk-21%2B35/src/java.base/share/classes/java/util/concurrent/locks/AbstractQueuedSynchronizer.java#L1619)
  can return normally with interrupt status restored when interruption follows
  signal; it cannot compensate for a later BX Effect control-state rejection.
  Reproduce this exact signal/interrupt ordering before choosing targeted
  re-signaling versus `signalAll`, then benchmark contention. The single-waiter
  [Queue cancellation specs](../tests/specs/async/QueueSpec.bx#L84) do not cover
  abandoned notifications. PubSub already signals all relevant waiters.
- **H3 — Fractional live delays lose precision before unit conversion.**
  [Clock.sleep](../models/effect/Clock.bx#L25) accepts numeric durations but passes
  them directly to native `delayedExecutor(long, unit)`. TestClock converts
  `0.5 seconds` to 500 ms. Verify BoxLang's overload/cast behavior: the expected
  failure is a truncated zero-second live wait (or coercion defect), including
  fractional delays generated by jitter. Test fractional seconds and jitter
  with a deterministic multiplier against both clocks. Convert to an appropriate
  finer native unit before integer conversion if confirmed; do not reject
  fractional public inputs merely to match the native signature. Source:
  [native signature](https://github.com/ortus-boxlang/BoxLang/blob/v1.19.0/src/main/java/ortus/boxlang/runtime/async/BoxFuture.java#L404).

## Coverage and dispositions

Every assigned production class is listed below. “Retain” means the traced
purpose remains justified, not that an unrun suite establishes correctness.

| Area and classes reviewed | Disposition and evidence |
| --- | --- |
| [Cause](../models/effect/Cause.bx), [Exit](../models/effect/Exit.bx), [Result](../models/effect/Result.bx) | Retain separate expected/complete outcomes and iterative Cause traversal/rebuilding. Mixed-channel order, deep trees, nullable successes, eager Result mapping, and native Attempt conversion have distinct coverage in [CauseExitSpec](../tests/specs/core/CauseExitSpec.bx), [ResultSpec](../tests/specs/core/ResultSpec.bx), and [ReleaseApiSpec](../tests/specs/core/ReleaseApiSpec.bx). No removal justified. |
| [Scope](../models/effect/Scope.bx), [Fiber](../models/effect/Fiber.bx), [FiberControl](../models/effect/internal/FiberControl.bx) | Retain separate public completion and interpreter termination, atomic admission, child-cleanup retention, identity-based cleanup provenance, and lock-serialized worker registration/unregistration. Scope closes admission and awaits outside its admission lock before runtime LIFO release. [ScopeSpec](../tests/specs/resources/ScopeSpec.bx), [AcquisitionSpec](../tests/specs/resources/AcquisitionSpec.bx), [BracketSpec](../tests/specs/resources/BracketSpec.bx), [LocalScopeSpec](../tests/specs/resources/LocalScopeSpec.bx), and [CleanupSpec](../tests/specs/async/CleanupSpec.bx) protect different lifetimes/handoffs; they are not interchangeable duplicates. The runtime and ManagedRuntime call termination/cleanup hooks: these are live implementation APIs. External native-future cancellation classification is root-owned. |
| [Context](../models/effect/context/Context.bx), [ServiceTag](../models/effect/context/ServiceTag.bx), [Layer](../models/effect/context/Layer.bx), [LayerMemo](../models/effect/internal/LayerMemo.bx) | Retain native key identity, shallow map copying with shared service values, explicit-write entry identity, ordered recipes, conditional failed-attempt removal, and scope-local memoization. Runtime waiters use dependent futures. [ContextLayerSpec](../tests/specs/context/ContextLayerSpec.bx) protects inherited-binding isolation, equal-value explicit writes, failure/retry, order, and sharing; [ReleaseApiSpec](../tests/specs/core/ReleaseApiSpec.bx) protects case/non-ASCII/numeric key consistency. Builder closures supply no dependency graph to diagnose. |
| [ManagedRuntime](../models/effect/ManagedRuntime.bx) | Retain lazy private application Context/build ownership, per-run Scopes, atomic admission/close snapshot, and cleanup-before-retry. F1/F3 and H1 need focused work; they do not justify replacing the lifecycle protocol with a generic abstraction. [ManagedRuntimeSpec](../tests/specs/runtime/ManagedRuntimeSpec.bx) and native/framework lifetime specs trace real owners. |
| [Deferred](../models/effect/Deferred.bx), [Semaphore](../models/effect/Semaphore.bx) | Retain fresh dependent futures per execution and the fair JDK permit source. `withPermit` uses the existing acquisition/release handoff rather than inventing permit ownership. [DeferredSpec](../tests/specs/async/DeferredSpec.bx), [SemaphoreSpec](../tests/specs/async/SemaphoreSpec.bx), and the interrupt-during-acquire fixture cover distinct contracts. |
| [Queue](../models/effect/Queue.bx), [PubSub](../models/effect/PubSub.bx), [PubSubSubscription](../models/effect/PubSubSubscription.bx) | Retain condition loops, shutdown distinctions (Queue drains; PubSub discards), atomic broadcast, explicit hub/subscription ownership, and null rejection before capacity/shutdown. H2 needs reproduction. [QueueSpec](../tests/specs/async/QueueSpec.bx), [PubSubSpec](../tests/specs/async/PubSubSpec.bx), and [seeded stress cases](../tests/specs/stress/ConcurrencyStressSpec.bx) cover different behavior. FIFO buffered values do not promise FIFO admission of competing producers/consumers; only Semaphore promises fairness. Native [ReentrantLock](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/locks/ReentrantLock.html) documents the throughput cost of fairness; changing both locks to fair has no established contract justification. |
| [Clock](../models/effect/Clock.bx), [TestClock](../models/effect/testing/TestClock.bx), [Schedule](../models/effect/Schedule.bx) | Retain monotonic live time, native delayed execution, TestBox-independent deterministic time, completion-after-unlock, and stateless recurrence descriptions. F2/H3 concern the native boundary. [ClockSpec](../tests/specs/schedule/ClockSpec.bx), [ScheduleSpec](../tests/specs/schedule/ScheduleSpec.bx), [BoundedDelaySpec](../tests/specs/schedule/BoundedDelaySpec.bx), and [CooperativeTimeoutSpec](../tests/specs/schedule/CooperativeTimeoutSpec.bx) separately protect fixed overrun reanchoring, spaced completion delays, caps/composition, cancellation, and awaited cleanup. Keep these scenarios. |
| [ThrowablePolicy](../models/effect/internal/ThrowablePolicy.bx), [ErrorTagResolver](../models/effect/internal/ErrorTagResolver.bx) | Retain shared fatal-wrapper policy and the existing tag precedence; neither is dead indirection. Trace callers in the interpreter, Fiber, ManagedRuntime, and tagged recovery. [EffectOperatorsSpec](../tests/specs/core/EffectOperatorsSpec.bx) covers explicit/annotated tags and fatal errors bypassing try mapping; [CollectionFailureSpec](../tests/specs/async/CollectionFailureSpec.bx) covers fatal async aggregate completion. Wrapper-specific expected-async/cancellation coverage belongs with root's selected constructor work. |
| [LoggingObserver](../models/effect/observability/LoggingObserver.bx), [ModuleConfig](../ModuleConfig.bx) | Retain opt-in logger adapter with contained formatting/logger errors and the thin descriptor/default-executor setting. No kernel framework dependency or global lifecycle is introduced. [RuntimeObserverSpec](../tests/specs/observability/RuntimeObserverSpec.bx), [native logger acceptance](../tests/specs/native/ApplicationLifecycleSpec.bx), and [ModuleConfigSpec](../tests/specs/module/ModuleConfigSpec.bx) exercise adapter use, activation, checkout identity, metadata, and executor overrides. |

## Consumer paths and meaningful test improvements

- Read every class/template under `examples/application`, `examples/native`,
  `examples/wirebox`, and `examples/coldbox`. Native cache loading delegates
  atomic misses/TTL to the provider; validation stays lazy; SaveRecords maps
  database errors after leaving the transaction. The corresponding
  [native specs](../tests/specs/native) exercise the actual recipes, rollback,
  external cache ownership, and native application shutdown.
- WireBox's [binder](../examples/wirebox/config/EffectBinder.bx) owns the mapped
  runtime, supplies existing services through a Layer, and closes in onShutdown.
  ColdBox's [interceptor](../examples/coldbox/interceptors/EffectLifecycle.bx)
  closes before service teardown/reinit; application end forwards through the
  bootstrap. [WireBoxSpec](../tests/specs/frameworks/wirebox/WireBoxSpec.bx) and
  [ColdBoxSpec](../tests/specs/frameworks/coldbox/ColdBoxSpec.bx) exercise these
  paths, including real response transport and replacement-runtime behavior.
  Do not consolidate entry-point HTTP coverage with direct event dispatch:
  only the former establishes the complete example response path.
- Read [package metadata](../box.json), both
  [PR](../.github/workflows/pr.yml)/[release](../.github/workflows/release.yml)
  workflows, isolated [consumer smoke](../tests/consumer/Smoke.bxm)/config,
  framework [launcher](../tests/RunFrameworks.bx)/fixtures, and the
  [release automation checks](../tests/ci/release-workflow-test.sh). Current
  version metadata agrees; dependencies/examples/test tooling are development
  assets, not module lifecycle dependencies. Release waits for matrix checks,
  verifies installed consumer imports, and guards repeat publication. Windows
  launcher/process-tree and 1.19.0 compatibility remain verification gates,
  not results established by this research. Minimum-version/TestBox changes
  are already accepted implementation work, not new audit findings.
- **Strengthen actual waiting-path evidence.** Deferred's canceled-awaiter spec
  interrupts immediately after `runFork`; it can pass without registering a
  dependent future. Gate registration, keep a second waiter active, cancel the
  first, then rerun the same previously constructed await Effect. Add analogous
  gated cancellation of a non-builder Layer waiter and one managed first-run
  waiter; prove the other waiter succeeds with one build/release. These are
  coverage gaps despite the source using the correct isolation pattern.
- **Use completion guarantees precisely.** In
  [ScopeSpec's timeout case](../tests/specs/resources/ScopeSpec.bx#L174), polling
  release after the *normally completed timeout parent* can conceal return-before-
  cleanup regressions; assert directly at that boundary. Preserve waiting after
  `fiber.interrupt().await()` elsewhere: canceled public completion can precede
  interpreter finalization. Prefer bounded termination observation in tests that
  actually need finalization. Replace [AsyncTestSupport](../tests/resources/AsyncTestSupport.bx)
  deadlines with monotonic elapsed time per the repository's documented clock
  evidence; do not remove genuine asynchronous synchronization.
- **Acceptance gaps remain:** no dedicated native HTTP-client recipe, Scheduler
  callback, or file-recipe acceptance spec was located. The HTTP-server framework
  cases do not establish the guide's client cancellation/error mapping. Prioritize
  a loopback bounded HTTP batch with retry/deadline/partial-failure/cancellation,
  then file early-stop/failed-release behavior, following [module-review](module-review.md).
  No existing distinct regression scenario was proven redundant enough to delete.

## Performance candidates, not approved simplifications

- [LayerMemo.begin](../models/effect/internal/LayerMemo.bx#L17) allocates an unused
  native future even on memo hits. A read-before-propose fast path could avoid
  that work while preserving `putIfAbsent` election and conditional failure
  removal. [ManagedRuntime.contextBuildAccess](../models/effect/ManagedRuntime.bx#L225)
  similarly creates/completes a fresh source future on every already-built run;
  retaining a private completed build result while keeping fresh dependent
  waiters is a candidate. Measure allocation and repeated-hit throughput using
  [LayerRuntimeBench](../benchmarks/LayerRuntimeBench.bxm) and
  [ManagedRuntimeBench](../benchmarks/ManagedRuntimeBench.bxm), with contention,
  failed retry, and close races before retaining either change.
- [Context.add/merge](../models/effect/context/Context.bx#L33) copy a map and pass
  it to a constructor that copies again. Profile allocation before introducing
  a trusted internal construction path; preserving entry identity and public
  immutability is mandatory. Compare [ContextScopeBench](../benchmarks/ContextScopeBench.bxm)
  and Layer/managed workloads. Fewer copies in source alone is not evidence of
  acceptable end-to-end efficiency.
- Keep native BoxFuture/JDK coordination. Native
  [Condition documentation](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/locks/Condition.html)
  validates the two-condition buffer pattern; a plain native buffer does not
  by itself supply BX Effect shutdown/Cause/control-state semantics. PubSub's
  all-waiter notification supports distinct subscription predicates, so replacing
  it with one signal is not a harmless optimization. Do not unify Scope/runtime/
  ManagedRuntime loops or hide/remove live hooks solely to reduce lines.
  Follow [benchmark guidance](../benchmarks/README.md) and the accepted
  near-identical-or-better efficiency requirement; no new performance claim is
  established here.

## Implementation dispositions

- **F1/F3:** Reproduced close-during-failed-build cleanup loss and cancellation of
  a shared shutdown future before fixing them. `ManagedShutdownSpec` gates the
  acquisition/release handoffs and verifies retained cleanup and isolated close
  waiters. Managed shutdown still owns admission and service ordering explicitly.
- **F2/H3:** Normalize accepted short/singular time units at the native Clock
  boundary and convert fractional durations before native integer conversion.
  `ClockSpec` exercises real delays as well as deterministic Clock behavior.
- **H1:** Publish the managed build attempt before attaching its potentially
  inline completion callback. Keep the completed successful build result for
  subsequent runs, eliminating the redundant Context field/source future.
- **H2:** Deterministically reproduced an abandoned Queue notification for both
  producers and consumers. Re-signal the same condition on that interruption
  handoff; preserve the existing success path and native lock policy.
- **External cancellation:** `AsyncErrorSpec` distinguishes ordinary rejection,
  direct/wrapped native cancellation, requested cancellation, mapper defects,
  invalid/null returns, Context, retry, and awaited failed cleanup. Cancellation
  classification is limited to the native future boundary.
- **Collection split:** Remove only the duplicate small-width collection loop
  after comparing both strategies on immediate and delayed workloads. Retain
  the independent race/first-success completion helpers: they still have callers.
- **Test meaning:** Replace sleep-based race ordering and first-build readiness
  with gates; use direct cleanup assertions after normally completed race/timeout
  boundaries. Keep distinct cleanup ownership/error-channel cases. Switch the
  shared bounded polling helper to monotonic time without a second predicate call.
- **Native workflows:** Add actual asynchronous HTTP client/error/retry acceptance
  to the HTTP suite, file early-close/reopen coverage, and Scheduler callback
  outcome/cleanup coverage. These use the example code, not mocked equivalents.
- **Retained candidates:** Leave Context copies and LayerMemo hit allocation
  unchanged without allocation evidence. Keep the differing Scope/runtime/managed
  close protocols and live cross-class hooks; a generic lifecycle framework or
  new visibility workaround would add complexity without an established benefit.
  The optional gated-waiter coverage suggestions above remain future refinements;
  source inspection found the dependent-future isolation already implemented.

## Interpreter and Stream audit

`Effect.bx` keeps lazy immutable instruction construction and the public/internal
inventory boundary. `tryBoxFuture` follows the existing named `try`/`catch`
convention; ordinary `fromBoxFuture` rejection remains a defect. The interpreter
uses the existing native wait, active-future registration, fatal policy, and
iterative continuation loop rather than another execution engine.

`Stream.bx` and `internal/StreamCursor.bx` retain fresh per-consumer cursors,
exact sequential demand, acquisition fallback, and close-before-recovery.
The explicit concurrent path uses a private producer lifetime, a cursor-owned
mapper Scope, existing native Queue/Semaphore coordination and a local Scope per mapper. Admission remains
held through completed-but-undelivered values. Atomic producer admission and
handle installation avoid an interruption gap; cleanup provenance transfers
through the existing interpreter mechanism. `ConcurrentMapSpec` covers ordering,
blocked sources, failed mappers/releases, root interruption, Context, unjoined
children, and the total admission bound. No implicit concurrent flatMap,
configurable extra buffer, worker pool, or public cursor API was added.

## Retrospective

1. **High — reproducible dependency preparation:** Published framework bytecode
   did not match stable BoxLang. `test:prepare` now checks immutable source hashes,
   compilation results and checkout-local replacement targets. CI prepares with
   each selected runtime. The native compiler's per-file API avoids its CLI
   entry point exiting the hosting JVM.
2. **Medium — trustworthy test invocation:** Relative report paths and comma-list
   directory discovery produced misleading local results. CONTRIBUTING documents
   absolute paths and one directory/bundle selection; AGENTS links to the setup.
   Existing CI JSON checks already reject zero passes and are retained.
3. **Medium — application guidance:** README stays focused on adoption and public
   usage; contributor setup moved to CONTRIBUTING. The portable skill explains
   new async errors, concurrent mapper lifetimes, and isolated shutdown waiters.
   HTTP examples use `address`/`requestUrl` rather than a lambda argument named
   `url`, which collides with a native web scope in unscoped expressions.
4. **Low — tool economy:** Use narrow source excerpts and tool metadata queries;
   full upstream pages and unrelated tool declarations obscured the useful facts.
   This is session/tool practice rather than another always-loaded repository rule.

The agent-rules content verifier passed. Its command verifier reported no failures
but skipped eight entries because its language detection treated BoxLang paths
as command names; it did not validate the BoxLang commands. Actual native runs
and CI remain the command evidence. Root AGENTS stays below 150 lines. Existing
`.gitattributes` already enforces LF, and existing CI checks runtime behavior;
no duplicate formatting framework or speculative linter was introduced.

## Performance evidence

Local comparisons used Windows 11, BoxLang 1.19.0, Eclipse Temurin
21.0.12+101 and the native `io-tasks` executor. Each entry below contains the
medians from three fresh JVMs; each median follows one warmup and five samples.
These are workload observations, not CI timing gates or deployment promises.

The focused collection comparison changed only the small-width completion
strategy in the otherwise updated runtime. Width-eight immediate work improved
and delayed work remained equivalent; width-one variation overlapped. This
supports deleting the duplicate loop without inventing a new coordinator.

| Workload | Two strategies, ms | One queued strategy, ms |
| --- | --- | --- |
| 1,000 immediate, width 1 | 362 / 363 / 367 | 321 / 369 / 377 |
| 1,000 immediate, width 8 | 253 / 206 / 213 | 178 / 187 / 188 |
| 1,000 immediate, width 9 | 170 / 155 / 168 | 152 / 148 / 146 |
| 96 delayed 3 ms, width 1 | 1496 / 1501 / 1498 | 1499 / 1498 / 1496 |
| 96 delayed 3 ms, width 8 | 187 / 188 / 187 | 187 / 186 / 186 |
| 96 delayed 3 ms, width 9 | 171 / 171 / 171 | 171 / 172 / 171 |
| 96 delayed 3 ms, width 16 | 93 / 93 / 93 | 93 / 93 / 94 |
| 96 delayed 3 ms, unbounded | 31 / 30 / 30 | 30 / 31 / 32 |

Broader before/after comparisons include all changes. The collection comparison
uses the original benchmark scenario order; current benchmark widths now also
include 9 and 16. Kernel and Stream timings show run-to-run variation, including
a slower Stream-map median; no general interpreter or Stream speedup is claimed.
The sequential Stream map path is unchanged. Retained-heap readings varied with
GC (roughly 4–102 MB before and 102–153 MB after), so they establish neither a
retained-memory regression nor improvement; allocation profiling remains open.
The concurrent admission tests establish a count bound, not a byte-size promise.

| Workload | Before, ms | After, ms |
| --- | --- | --- |
| Sequential forEach, 10,000 | 2113 / 2095 / 2080 | 1874 / 1884 / 1907 |
| all, 1,000, width 8 | 254 / 247 / 245 | 147 / 153 / 154 |
| all, 1,000, unbounded | 190 / 192 / 187 | 150 / 145 / 157 |
| Kernel map, 100,000 | 1442 / 1452 / 1449 | 1462 / 1386 / 1741 |
| Kernel flatMap, 100,000 | 6175 / 6324 / 6297 | 5768 / 6357 / 6520 |
| Local Scope, depth 5,000 | 813 / 807 / 810 | 738 / 774 / 789 |
| Stream map, 100,000 | 308 / 299 / 302 | 350 / 338 / 301 |
| Stream repeated pulls, 10,000 | 3021 / 3119 / 3105 | 3828 / 2881 / 2901 |
| Stream Queue, 1,000 | 1017 / 989 / 961 | 1048 / 892 / 873 |
| ManagedRuntime, 128 runs | 256 / 206 / 261 | 215 / 167 / 188 |

`ConcurrentStreamBench` uses 96 mappings, every eighth delayed 60 ms and the
others 3 ms, with concurrency eight. Sequential medians were 2079 / 2077 / 2079
ms; grouped bounded batches 941 / 942 / 945; rolling ordered mapping
878 / 925 / 896; completion order 345 / 345 / 348. Ordering and values are
checked. The unordered advantage comes from admitting replacements without
waiting behind earlier slow values; it is not a native HTTP backpressure claim.

## Verification before PR review

- Stable BoxLang 1.19.0 and minimum 1.18.0: **322 passed, zero failures/errors**
  each; seven HTTP-only cases intentionally skipped by the CLI runner.
- Executor override: **4 passed, zero failures/errors** on each runtime.
- Real MiniServer/ColdBox HTTP on Windows, stable 1.19.0: **7 passed, zero
  failures/errors**, including actual client cancellation and awaited cleanup.
- Pinned ColdBox/cbproxies sources: **209 files compiled** successfully with
  each runtime; stable 1.19.0 dependencies restored after the minimum checks.
- Isolated production installation in a Windows path containing spaces:
  `BX_EFFECT_CONSUMER_SMOKE_OK`, including new async and concurrent Stream APIs.
- Executed all three README examples, the getting-started sequence and nine
  portable skill snippets (supplying the documented path/URL inputs). The HTTP
  snippet constructs a lazy description; actual HTTP execution is checked above.
- Checked 160 local Markdown links, BoxLang LF/tab indentation and `git diff
  --check`; package inspection passed. Release automation: **17 checks, zero
  failures**, including the updated Windows publication dependency.

Linux minimum/latest/snapshot and the reusable Windows lane are required PR CI
checks; local Windows results do not claim those remote jobs have run. A merge
into main triggers the existing automatic release workflow. This work opens a
PR for review and does not merge or publish it.

## Code review

### Standards

One hard finding: a queued mapper Exit could retain its cleanup failure after
producer shutdown had already claimed that mapper's cleanup. When upstream
failed while the consumer paused, close appended the same release failure again
(`mapped, release, release`). This violated exactly-once cleanup retention.

**Fixed:** A separate cursor-owned mapper Scope removes the competing producer
claim. Close first stops/awaits the producer, then interrupts/awaits mappers,
then releases upstream. The gated regression now returns `mapped, release`.
No actionable smell-baseline judgement calls were reported.

### Spec

One finding: simulated delayed work and admission counts did not fulfill the
agreed native-I/O and retained-memory measurement requirement.

**Addressed:** `NativeStreamBench` measures real native 64 KiB file reads and
stalls the first ordered mapping at windows 8, 32 and 128 before draining 2,048
items without collecting their payloads. Three fresh JVMs check the exact count
bound and complete draining. Indicative post-GC heap deltas are below; each
column contains the three trials, in bytes.

| Window | Stalled heap minus baseline | Drained heap minus baseline |
| --- | --- | --- |
| 8 | 926896 / 928848 / 904112 | 101200 / 97880 / 98752 |
| 32 | 2715512 / 2706232 / 2694056 | 336 / 2272 / 5360 |
| 128 | 10249064 / 10257864 / 10260008 | 336 / 1216 / 2088 |

The stalled deltas grow with the window and return near baseline after draining,
consistent with bounded payload retention for this source. Full-GC requests
remain indicative and do not replace a native allocation profile.

For 256 native cached-file reads, sequential medians were 158 / 159 / 182 ms,
grouped batches 217 / 230 / 219, ordered concurrent 368 / 336 / 347, unordered
361 / 340 / 341. This fast local workload favors sequential execution; the guide
now explicitly explains that concurrency is useful for waiting-heavy work and
must be measured. It remains opt-in. The earlier delayed benchmark represents
latency overlap, not a claim that concurrency accelerates cached disk access.

Review totals: **Standards 1, Spec 1**, both addressed. No additional correctness
or scope findings were reported by the Spec reviewer. Changes were checked
against the fixed main revision `7e2f7d4598d15df796a77a814a7e2f192b361549`.

After the review fix, both full runtime suites passed **323 tests with zero
failures/errors**; Windows HTTP passed all seven cases again and a fresh
production consumer installation in a path with spaces passed. The post-fix
delayed benchmark medians were sequential 2073 / 2077 / 2069 ms, grouped
939 / 943 / 946, ordered 940 / 907 / 913, unordered 347 / 344 / 349.
Ordered mode remains close to grouped throughput for this bounded skewed window;
completion order overlaps more waiting work. The expanded collection benchmark
also completed with all correctness assertions intact.
