# BX Effect

BX Effect is a BoxLang-native structured effect system inspired by Effect. It
models effectful work as lazy program descriptions with separate channels for
success, expected failure, unexpected defects, and interruption.

The project targets BoxLang 1.16.0 and newer. The full architecture and roadmap
live in [the design specification](specs/bx-effect-design-spec.md).

## Current status

The project currently contains its validated synchronous kernel:

- lazy `Succeed`, `Fail`, `Sync`, `Try`, and `Suspend` instructions;
- `FlatMap` and `FoldCause` composition;
- fluent success and expected-error operators, including `tap`, `mapError`,
  `catchIf`, `catchTag`, `orElse`, and `filterOrFail`;
- distinct expected failure and defect semantics;
- `Result`, `Cause`, and `Exit` values;
- native `Attempt` interop;
- `runSync` and `runSyncExit` execution boundaries;
- centralized fatal JVM throwable handling;
- explicit `ServiceTag` and immutable-by-contract `Context` services;
- Context provisioning with nested restoration on success and failure;
- basic `Layer.succeed`, `Layer.effect`, and dependency-aware `Layer.merge`;
- `Scope`, `ensuring`, `onExit`, and `acquireRelease` resource finalization;
- scoped Layers with LIFO cleanup and sequential Cause composition for cleanup
  failures;
- lazy BoxFuture interop plus native-BoxFuture `runFuture` boundaries;
- BoxFuture-backed Fibers, `all`, `forEach`, `race`, and `firstSuccessOf` concurrency;
- BoxFuture-backed `Deferred` for one-shot Fiber coordination;
- native-JDK `Semaphore` permits with interruption-safe `withPermit` cleanup;
- bounded and unbounded native-JDK `Queue` buffers with FIFO backpressure,
  interruption-aware waits, and explicit shutdown;
- bounded and unbounded native-JDK `PubSub` hubs with active-subscriber
  broadcast, slowest-subscriber backpressure, and explicit subscriptions;
- `Schedule` policies with retry, repeat, runtime-Clock sleep, TestClock, and
  typed timeout failures backed by BoxFuture timing by default;
- an opt-in runtime observer boundary for diagnostic lifecycle events;
- an iterative interpreter that runs 100,000 nested `flatMap` operations
  without growing the JVM stack;
- a minimal BoxLang module descriptor;
- TestBox coverage on BoxLang 1.16.0, with CI configured to also run the current
  stable runtime.

Milestones 1 through 6 plus Deferred, Semaphore, Queue, and PubSub
coordination are locally complete, including module-resolved imports,
configured runtime defaults, package-install smoke coverage, and the release
audit. A successful hosted CI matrix run remains the final external release
gate after the changes are pushed.

BX Effect is module-first: applications import public classes such as
`models.effect.Effect@bxEffect` and then use normal `Effect::...` static calls.
Classes inside BX Effect use `bxModules.bxEffect...` for internal resolution.
The kernel is lifecycle-independent, but module activation is required; it does
not offer a separate direct-source loading mode.

## Guides

- [Getting started](docs/getting-started.md)
- [Expected errors, defects, and Exit](docs/error-model.md)
- [Services and Layers](docs/services-and-layers.md)
- [Resource safety](docs/resources.md)
- [BoxFutures and Fibers](docs/concurrency.md)
- [Schedules, retry, and timeout](docs/schedules.md)
- [Runtime observability](docs/observability.md)
- [Incremental migration](docs/migration-from-imperative-code.md)
- [Effect alignment and BoxLang-native deviations](docs/effect-alignment.md)
- [Release process](docs/releasing.md)

## Development specifications

- [Design and implementation specification](specs/bx-effect-design-spec.md)
- [Implementation status](specs/implementation-status.md)
- [1.0 release audit](specs/release-audit.md)
- [Next development specification](specs/next-development-spec.md)

## Example

```boxlang
import models.effect.Effect@bxEffect;

program = Effect::try(
    try: () -> riskyOperation(),
    catch: error -> {
        _tag: "OperationFailed",
        message: error.message
    }
).map( value -> value * 2 );

exit = Effect::runSyncExit( program );
```

Constructing `program` does not invoke `riskyOperation()`. Execution begins only
at `runSyncExit`.

`Effect::fail` and `Effect::try` produce expected failures. An unhandled
exception thrown by `Effect::sync`, a mapper, or a handler becomes a defect.
Ordinary `catchAll` recovers expected failures only; `catchCause` is the explicit
full-cause recovery boundary.

`runSync` returns the success value and throws a `BXEffect.EffectFailure` at a
failed runtime boundary. The thrown exception retains the complete `Cause` in
its `extendedInfo`; use `runSyncExit` when failure should remain a value.

## Development

Install development dependencies:

```bash
box install
```

Run the suite with a standalone `boxlang` executable:

```bash
boxlang --bx-config tests/boxlang.json testbox/system/runners/BoxLangRunner.bx \
  --directory=tests.specs \
  --stream \
  --write-report=false \
  --properties-summary=false
```

When BoxLang is provided by the CommandBox BoxLang module, use:

```bash
box boxlang cli --bx-config tests/boxlang.json testbox/system/runners/BoxLangRunner.bx \
  --directory=tests.specs \
  --stream \
  --write-report=false \
  --properties-summary=false
```

Run the interpreter stress benchmark with:

```bash
box boxlang cli --bx-config tests/boxlang.json benchmarks/EffectRuntimeBench.bxm
```

Run async and concurrency baseline benchmarks with:

```bash
box boxlang cli --bx-config tests/boxlang.json benchmarks/AsyncRuntimeBench.bxm
box boxlang cli --bx-config tests/boxlang.json benchmarks/ConcurrencyBench.bxm
box boxlang cli --bx-config tests/boxlang.json benchmarks/ContextScopeBench.bxm
```

TestBox is the only test framework. BX Effect should continue to reuse native
BoxLang facilities such as `Attempt`, `BoxFuture`, `AsyncService`, executors,
caching, logging, and module lifecycle rather than replacing them.
