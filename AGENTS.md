<!-- FOR AI AGENTS | Verify commands and runtime assumptions against README.md and CI. -->
<!-- Last updated: 2026-09-23 | Last verified: 2026-09-23 -->

# AGENTS.md

Explicit user instructions override this file. A more deeply nested `AGENTS.md`
overrides it for files in that subtree.

## Project

BX Effect is a BoxLang 1.16.0+ and Java 21+ module that adds lazy, composable
Effect semantics while reusing BoxLang's runtime facilities. It is
Effect-inspired, not an API-compatible TypeScript Effect port.

Treat implementation and focused tests as the executable contract. Use the
focused guides in `docs/` for public semantics; use `README.md` for supported
entry points and setup.

## Architecture

| Area | Responsibility |
| --- | --- |
| `models/effect/Effect.bx` | Lazy constructors, combinators, and instruction graph |
| `models/effect/EffectRuntime.bx` | Iterative interpreter and sync/async execution boundaries |
| `models/effect/Cause.bx`, `Exit.bx`, `Result.bx` | Failure trees and outcome values |
| `models/effect/Scope.bx`, `Fiber.bx` | Resource safety and structured concurrency |
| `models/effect/ManagedRuntime.bx` | Explicit application-lived Layer ownership across repeated runs |
| `models/effect/Schedule.bx`, `Clock.bx` | Retry, repeat, live delay, and timeout policies |
| `models/effect/Stream.bx`, `internal/StreamCursor.bx` | Pull-based multi-value descriptions and private single-run cursors |
| `models/effect/testing/TestClock.bx` | Published deterministic-clock test support for module consumers |
| `models/effect/context/` | `Context`, `Layer`, and `ServiceTag` dependency model |
| `models/effect/Deferred.bx`, `Semaphore.bx`, `Queue.bx`, `PubSub.bx`, `PubSubSubscription.bx` | Explicit coordination and interruptible waits |
| `models/effect/internal/` | Private Fiber control, Layer memoization, Stream cursors, and throwable/tagged-error policies |
| `ModuleConfig.bx`, `box.json` | Module settings, identity, packaging, and version metadata |
| `tests/specs/` | TestBox contracts grouped by subsystem |
| `.github/workflows/pr.yml` | PR TestBox checks on `latest` and `snapshot`, including the executor override |
| `.github/workflows/release.yml` | TestBox on `latest` and `snapshot`, plus an installed-consumer smoke check before publishing from `main` |

BX Effect is module-first: its BoxLang module must be installed, registered,
and activated. Public applications import `models.effect.Effect@bxeffect` and
then call `Effect::...`; library classes import peers through
`bxModules.bxEffect...`. Keep those public and internal resolver paths
distinct. The kernel is lifecycle-independent, not activation-independent:
keep it free of hidden application lifecycle, interceptor, WireBox, or
annotation-scanning requirements.

## Semantic Invariants

- Effect construction and transformation are lazy. User work starts only at an
  explicit runtime boundary.
- Keep the interpreter iterative and stack-safe. Do not replace its instruction
  graph and continuation stack with recursively executed nested thunks.
- Preserve the three failure channels: expected failure (`Cause::fail`), defect
  (`Cause::die`), and interruption (`Cause::interrupt`).
- `catchAll` handles expected failures only. Full-cause recovery must remain an
  explicit `catchCause` operation.
- Use native `Attempt` for presence/absence, `Result` for success or expected
  failure, and `Exit` plus `Cause` for complete runtime outcomes.
- Treat Effects, Causes, Exits, Results, Contexts, Layers, and Schedules as
  immutable values. Avoid exposing mutable semantic state.
- Preserve Context isolation and restore the previous Context after nested
  provisioning on both success and failure.
- `ManagedRuntime` is explicitly instance-owned and lazy. Concurrent first runs
  share one Layer build; failed builds clean partial resources and remain
  retryable. Closing rejects new work, waits for active run finalization, and
  only then releases managed services once. Never expose its Context or memo,
  install it globally, or release a managed Scope while a run may still use it.
- Missing services are wiring defects. Preserve `bxeffect.context.MissingServiceException` and
  include only deterministic requested/available tag diagnostics; do not infer
  a Layer graph from builder closures.
- Finalizers run idempotently in LIFO order after success, failure, defect, or
  interruption. Continue cleanup after a failed finalizer and retain failures
  in the resulting Cause.
- Successful acquisition must register release before observing pending
  interruption; acquisition waits remain interruptible. If Scope registration
  is rejected, release immediately and retain cleanup failure with the defect.
  See `docs/resources.md` and `tests/specs/resources/AcquisitionSpec.bx`.
- Root shutdown stops child admission, interrupts and awaits admitted Fibers,
  then runs Scope cleanup. A closing Scope rejects new finalizers and children;
  no work may escape its root lifetime after cleanup starts.
- Reuse `BoxFuture`, `AsyncService`, named executors, and `asyncAll`/`asyncAny`.
  Do not add a promise, thread-pool, scheduler, cache, logger, optional-value, or
  testing subsystem that duplicates BoxLang.
- `Effect::all` defaults to fail-fast. Its explicit `accumulate` mode must wait
  for all branches and combine their Causes in input order; it must not cancel
  siblings merely because one branch fails.
- Async interpretation deliberately waits inside BoxLang's `io-tasks`
  virtual-thread executor. `runFuture` remains non-blocking to its caller; do
  not replace this with a custom continuation scheduler unless a documented
  BoxFuture API and benchmark evidence show a material improvement.
- Fiber cancellation is best effort because it delegates to BoxFuture. Scope
  ownership must still request child interruption and run cleanup. The internal
  `FiberControl` must continue to request cancellation of the active nested
  BoxFuture as well as the outer runtime task.
- When a cancellation request causes an async, sleep, or semaphore wait to
  throw, preserve `Cause::interrupt`; do not normalize the native cancellation
  wrapper as a defect.
- `Schedule::spaced()` delays from completion, whereas `Schedule::fixed()`
  targets recurrence start times and skips missed intervals after an overrun.
  Preserve this distinction through the runtime Clock and TestClock coverage.
- `models/effect/testing/TestClock.bx` is shipped test support for downstream
  consumers, not a repository test fixture. Keep it independent of TestBox;
  repository-only fixtures and specs belong under `tests/`, which packaging
  excludes.
- The optional `EffectRuntime` observer is diagnostic-only. Its failures must
  not alter an Exit or prevent cleanup; do not add a module observability
  setting, interceptor bridge, or telemetry dependency without its own focused
  design, docs, and tests.
- Observer terminal events report completed/interrupted Fibers and defects that
  reach a runtime boundary. Do not report recovered defects as unhandled.
- Current Layers are ordered recipes with arbitrary builder closures, not a
  declared dependency graph. Do not add heuristic cycle detection; require an
  explicit dependency/composition API before graph diagnostics. Runtime-local
  Layer memoization shares in-flight builds and root Scope ownership across
  child Fibers; keep that state private and never promote it to a global cache.
- `Deferred` is a one-shot coordination primitive backed by one BoxFuture. Its
  awaiters must use dependent futures so interrupting one Fiber cannot cancel
  the shared outcome. Do not broaden it into Queue, PubSub, or Semaphore
  behavior without their own cancellation/backpressure design and tests.
- `Semaphore` is a mutable, native-JDK permit source. Keep acquisition as an
  interruptible runtime instruction and prefer `withPermit()` for scoped
  release. Do not implement it as an uncancelable nested worker future.
- `Queue` is a mutable, application-owned FIFO buffer. Its bounded backpressure
  waits must remain interruptible interpreter instructions, with explicit,
  idempotent shutdown; allow buffered values to drain, then represent closed
  `take`/`offer` operations as the expected tagged `QueueShutdown` error. Do
  not give Queue implicit Scope ownership or broaden it into PubSub/Stream.
- `PubSub` is a mutable, application-owned broadcast hub. Bounded publication
  waits for the slowest active subscription; every active subscription receives
  one accepted value. Keep subscription ownership explicit through
  `unsubscribe()` or `withSubscription()`, make blocking publish/take
  interpreter instructions, and preserve tagged PubSub/Subscription shutdown
  errors. Do not add replay, dropping/sliding strategies, implicit Scope
  ownership, or Stream behavior without a separate contract and tests.
- `Stream` is an immutable reusable description whose private cursor pulls
  native `Attempt<Array>` batches on demand. Empty Attempt is normal completion;
  failures remain in Cause. Every consumer opens a fresh cursor and closes it on
  success, failure, defect, or interruption, before following Effect work or
  outer recovery. Cursor opening must retain an idempotent release fallback.
  Queue sources never own the Queue; PubSub sources own only their per-consumer
  subscription. Shutdown becomes normal completion. Keep the MVP sequential and
  demand-driven: no implicit read-ahead, Channel/Sink/Chunk layer, concurrent
  flatMap, Java Stream wrapper, or Queue/PubSub ownership changes.
- Fiber interruption tracks the actual worker thread only while the interpreter
  is inside a known interruptible Semaphore, Queue, or PubSub instruction. Keep
  that registration tightly scoped and always clear it in `finally`; do not
  interrupt executor threads around arbitrary user code.
- Benchmark elapsed times must use imported `java.lang.System.nanoTime()` and
  convert to milliseconds. Do not use `getTickCount()` for recorded baselines;
  it has produced anomalous elapsed readings under the BoxLang CLI runtime.

Before adding a low-level facility, check current official BoxLang
documentation/source for an existing primitive. Prefer platform behavior over
a custom abstraction unless a tested semantic requirement proves otherwise.

## Imports and BoxLang Conventions

- Custom exception types use `bxeffect[.<namespace>].<DescriptiveName>Exception`,
  with lowercase namespaces and PascalCase names. Use stable public namespaces
  such as `context` and `observability`; omit implementation directories such
  as `models`, `effect`, and `internal`. Shared exceptions stay at the root,
  including duration/unit validation in TestClock. Repository-only exceptions
  use `testing` or `benchmarks`. Expected error tags such as `QueueShutdown`
  retain their names. See `docs/error-model.md` for the public contract.
- Public examples and tests import activated module classes with paths such as
  `models.effect.Effect@bxeffect`.
- Library classes resolve peers through paths such as
  `bxModules.bxEffect.models.effect.Cause`; keep those internal and public
  import styles distinct.
- Static semantic classes (`Effect`, `Cause`, `Exit`, `Result`, `Schedule`,
  `Context`, and `Layer`) are imported value APIs, not WireBox services. Any
  WireBox adapter must be optional and explicitly map an `EffectRuntime` or
  application Layer without coupling the kernel to WireBox.
- Imported identifiers are reserved case-insensitively. Do not use locals or
  parameters named `effect`, `cause`, or another imported class name. Prefer
  names such as `program`, `effectCause`, and `failureCause`.
- `Effect::try( try: ..., catch: ... )` is verified on the minimum runtime; keep
  its named-argument form covered when changing constructors or parser-facing
  syntax.
- BoxLang has had parser trouble with some typed annotations involving `Exit`.
  If encountered, remove only the problematic annotation; do not weaken types
  throughout unrelated code.
- Match surrounding BoxLang style: tabs in `.bx`/`.bxm` code, descriptive
  named arguments, and LF line endings. Avoid unrelated formatting churn.
- Document functions with a description and argument descriptions. Declared
  return types make `@return` comments unnecessary. Use ordinary descriptive
  names for internal methods; the public compatibility boundary is the
  supported inventory in `docs/public-api.md`.

## Commands

Run commands from the repository root. Install development dependencies with:

```bash
box install
```

The canonical local suite is the package script declared in `box.json`:

```bash
box run-script test
```

For a narrow iteration, run the underlying command with `box boxlang cli` and
change `--directory` to a package such as `tests.specs.core`,
`tests.specs.context`, or `tests.specs.schedule`. In CI or with a standalone
executable, use `boxlang` in place of `box boxlang cli`.

Keep `--bx-home .boxlang/test` on checkout test and benchmark commands so an
installed module cannot shadow the checkout. The supported minimum remains
BoxLang `1.16.0`, but the current PR matrix runs `latest` and `snapshot`; verify
minimum-runtime compatibility separately for parser-facing or platform changes.

Inspect TestBox totals, not only the process exit code: the runner can exit zero
with failing specs. Both workflows write JSON reports and check
`totalFail == 0`, `totalError == 0`, and `totalPass > 0`. Module specs verify
activation and checkout resolution. The release workflow additionally installs
the package in an isolated consumer and runs `tests/consumer/Smoke.bxm` once on
`latest`. Keep CI on BoxLang `latest` and `snapshot`.

Additional checks:

| Task | Command |
| --- | --- |
| Module executor override | `box boxlang cli --bx-home .boxlang/test --bx-config tests/boxlang.executor-override.json testbox/system/runners/BoxLangRunner.bx --directory=tests.specs.module --stream --write-report=false --properties-summary=false --stacktrace=short` |
| Package metadata | `box package show` |
| Stack-safety benchmark | `box boxlang cli --bx-home .boxlang/test --bx-config tests/boxlang.json benchmarks/EffectRuntimeBench.bxm` |
| Layer-sharing benchmark | `box boxlang cli --bx-home .boxlang/test --bx-config tests/boxlang.json benchmarks/LayerRuntimeBench.bxm` |
| Managed runtime benchmark | `box boxlang cli --bx-home .boxlang/test --bx-config tests/boxlang.json benchmarks/ManagedRuntimeBench.bxm` |
| Stream benchmark | `box boxlang cli --bx-home .boxlang/test --bx-config tests/boxlang.json benchmarks/StreamBench.bxm` |
| Managed runtime specs | `box boxlang cli --bx-home .boxlang/test --bx-config tests/boxlang.json testbox/system/runners/BoxLangRunner.bx --directory=tests.specs.runtime --stream --write-report=false --properties-summary=false --stacktrace=short` |
| Stream specs | `box boxlang cli --bx-home .boxlang/test --bx-config tests/boxlang.json testbox/system/runners/BoxLangRunner.bx --directory=tests.specs.stream --stream --write-report=false --properties-summary=false --stacktrace=short` |
| Async runtime baseline | `box boxlang cli --bx-home .boxlang/test --bx-config tests/boxlang.json benchmarks/AsyncRuntimeBench.bxm` |
| Concurrency baseline | `box boxlang cli --bx-home .boxlang/test --bx-config tests/boxlang.json benchmarks/ConcurrencyBench.bxm` |
| Context/Scope baseline | `box boxlang cli --bx-home .boxlang/test --bx-config tests/boxlang.json benchmarks/ContextScopeBench.bxm` |

Run the narrowest relevant spec while iterating. Before handoff, run the full
suite when feasible. Also run the override check for module settings/runtime
changes, `box package show` for metadata or packaging changes, and the benchmark
for interpreter or composition changes.

## Change Heuristics

| When changing | Keep in sync and verify |
| --- | --- |
| Constructors or operators | Laziness, success path, expected failure, defect behavior, public docs, and core specs |
| Cause/Exit/Result | Information preservation, conversion semantics, pretty diagnostics, and error-model docs |
| Context or Layers | Isolation, restoration, dependency order, scoped cleanup, and context specs |
| Managed runtime | Build sharing/retry, run isolation, close races, interruption, cleanup ordering, runtime specs, and Layer benchmark |
| Scope or finalizers | All exit modes, LIFO order, idempotence, and sequential Cause composition |
| Futures, Fibers, or concurrency | Native BoxFuture return types, Context inheritance, child ownership, cancellation, and async specs |
| Schedule or timeout | Laziness, expected-failure-only retry, cleanup, timing semantics, and schedule specs |
| Stream | Pull/acquisition laziness, Cause channels, early cleanup, Context on every pull, interruption, coordination ownership, stream specs, and Stream benchmark |
| Module settings | `ModuleConfig.bx`, both test configs, module specs, and executor-override check |
| Version or release metadata | `box.json`, `ModuleConfig.bx`, `CHANGELOG.md`, and `.github/workflows/release.yml` |
| Supported runtime matrix | `box.json`, README requirements, test configs, `.github/workflows/pr.yml`, and `.github/workflows/release.yml` |
| Public API | README/guides, module-resolved imports, and focused TestBox specs |

Add focused TestBox coverage with behavior changes. Tests should assert failure
channel distinctions, not merely that an operation failed.
