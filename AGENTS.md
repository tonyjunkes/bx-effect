<!-- FOR AI AGENTS | Verify commands and runtime assumptions against README.md and CI. -->

# AGENTS.md

Explicit user instructions override this file. A more deeply nested `AGENTS.md`
overrides it for files in that subtree.

## Project

BX Effect is a BoxLang 1.16.0+ module that adds lazy, composable Effect
semantics while reusing BoxLang's runtime facilities. It is Effect-inspired,
not an API-compatible TypeScript Effect port.

Treat these sources as authoritative, in order:

1. `specs/bx-effect-design-spec.md` for architecture, semantics, and scope.
2. `specs/next-development-spec.md` for the approved post-baseline delivery
   order, decisions, and acceptance criteria.
3. `specs/implementation-status.md` for what is actually implemented.
4. Focused guides in `docs/` for public behavior and deliberate BoxLang-native
   differences, especially `docs/effect-alignment.md`.
5. Tests for executable contracts and `README.md` for the public entry points.

If implementation needs to depart from the design spec, prefer a documented
BoxLang-native facility and record the semantic difference in the appropriate
guide. Do not silently broaden the public API.

## Architecture

| Area | Responsibility |
| --- | --- |
| `models/effect/Effect.bx` | Lazy constructors, combinators, and instruction graph |
| `models/effect/EffectRuntime.bx` | Iterative interpreter and sync/async execution boundaries |
| `models/effect/Cause.bx`, `Exit.bx`, `Result.bx` | Failure trees and outcome values |
| `models/effect/Scope.bx`, `Fiber.bx` | Resource safety and structured concurrency |
| `models/effect/Schedule.bx`, `Clock.bx`, `testing/TestClock.bx` | Retry, repeat, deterministic delay, and timeout policies |
| `models/effect/context/` | `Context`, `Layer`, and `ServiceTag` dependency model |
| `models/effect/internal/` | Central throwable and tagged-error policies |
| `ModuleConfig.bx`, `box.json` | Module settings, identity, packaging, and version metadata |
| `tests/specs/` | TestBox contracts grouped by subsystem |
| `.github/workflows/` | Supported-runtime tests and ForgeBox release gates |

BX Effect is module-first: its BoxLang module must be installed, registered,
and activated. Public applications import `models.effect.Effect@bxEffect` and
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
- Missing services are wiring defects. Preserve `BXEffect.MissingService` and
  include only deterministic requested/available tag diagnostics; do not infer
  a Layer graph from builder closures.
- Finalizers run idempotently in LIFO order after success, failure, defect, or
  interruption. Continue cleanup after a failed finalizer and retain failures
  in the resulting Cause.
- A closing Scope must reject both new finalizers and child Fibers; no work may
  escape its root lifetime after cleanup starts.
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
- Benchmark elapsed times must use imported `java.lang.System.nanoTime()` and
  convert to milliseconds. Do not use `getTickCount()` for recorded baselines;
  it has produced anomalous elapsed readings under the BoxLang CLI runtime.

Before adding a low-level facility, check current official BoxLang
documentation/source for an existing primitive. Prefer platform behavior over
a custom abstraction unless a tested semantic requirement proves otherwise.

## Imports and BoxLang Conventions

- Public examples and tests import activated module classes with paths such as
  `models.effect.Effect@bxEffect`.
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

## Commands

Run commands from the repository root. Install development dependencies with:

```bash
box install
```

The canonical local suite when BoxLang is supplied by CommandBox is:

```bash
box boxlang cli --bx-config tests/boxlang.json \
  testbox/system/runners/BoxLangRunner.bx \
  --directory=tests.specs \
  --stream \
  --write-report=false \
  --properties-summary=false \
  --stacktrace=short
```

With a standalone executable, replace `box boxlang cli` with `boxlang`. For a
narrow iteration, change `--directory` to a package such as
`tests.specs.core`, `tests.specs.context`, or `tests.specs.schedule`.

Additional checks:

| Task | Command |
| --- | --- |
| Module executor override | `box boxlang cli --bx-config tests/boxlang.executor-override.json testbox/system/runners/BoxLangRunner.bx --directory=tests.specs.module --stream --write-report=false --properties-summary=false --stacktrace=short` |
| Package metadata | `box package show` |
| Stack-safety benchmark | `box boxlang cli --bx-config tests/boxlang.json benchmarks/EffectRuntimeBench.bxm` |
| Layer-sharing benchmark | `box boxlang cli --bx-config tests/boxlang.json benchmarks/LayerRuntimeBench.bxm` |
| Async runtime baseline | `box boxlang cli --bx-config tests/boxlang.json benchmarks/AsyncRuntimeBench.bxm` |
| Concurrency baseline | `box boxlang cli --bx-config tests/boxlang.json benchmarks/ConcurrencyBench.bxm` |
| Context/Scope baseline | `box boxlang cli --bx-config tests/boxlang.json benchmarks/ContextScopeBench.bxm` |

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
| Scope or finalizers | All exit modes, LIFO order, idempotence, and sequential Cause composition |
| Futures, Fibers, or concurrency | Native BoxFuture return types, Context inheritance, child ownership, cancellation, and async specs |
| Schedule or timeout | Laziness, expected-failure-only retry, cleanup, timing semantics, and schedule specs |
| Module settings | `ModuleConfig.bx`, both test configs, module specs, and executor-override check |
| Version or release metadata | `box.json`, `ModuleConfig.bx`, `CHANGELOG.md`, release docs, and workflows |
| Public API | README/guides, module-resolved imports, focused tests, and implementation status |

Add focused TestBox coverage with behavior changes. Tests should assert failure
channel distinctions, not merely that an operation failed.

## Packaging and Release Safety

- `box install` with no package argument is the normal dependency install.
- Never run `box install /absolute/path/to/this/repository` or install the
  source tree into a global module directory. A source-folder install has
  removed the workspace before.
- For installation smoke tests, use a disposable archive or production-only
  copy outside the source tree and an explicit BoxLang module configuration.
  Verify that tests and TestBox are excluded from the packaged module.
- Do not commit, push, tag, publish, or change CI/release behavior unless the
  user explicitly requests it. Publishing requires the repository's
  `FORGEBOX_API_TOKEN` secret.
- Local tests, package inspection, and smoke tests are not hosted CI evidence.
  CI must independently pass both BoxLang `1.16.0` and `latest` before claiming
  the hosted release gate is satisfied.

## Working Practices

1. Read the relevant design section, implementation, guide, and specs before
   editing.
2. Check `git status --short` and preserve all user changes. Never reset or
   rewrite unrelated work.
3. Make the smallest coherent change. Ask before adding dependencies or
   intentionally changing a public contract.
4. Validate proportionally: focused spec first, then the broader checks above.
5. Report changed files, exact commands run, results, and any checks not run.

Never expose secrets, hand-edit runner output, use destructive Git commands, or
claim external release verification from local evidence.
