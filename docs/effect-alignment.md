# Effect Alignment and BoxLang-Native Choices

BX Effect adopts the ideas that make Effect useful—lazy values, distinct error
channels, explicit dependencies, scopes, structured concurrency, and recurrence
policies—rather than attempting a source-compatible port of TypeScript APIs.

## Current upstream check

Checked 2026-08-16 against the canonical Effect repository. Effect v4 remains
in beta on its `main` branch, while v3 remains the `latest` npm release. BX
Effect therefore tracks stable Effect concepts and reviews concrete v4 beta
changes, without promising source-compatible TypeScript APIs or following beta
renames without a BoxLang benefit.

## Deliberate differences

- BoxLang has no TypeScript-style `Effect<A, E, R>` compile-time encoding.
  Success, expected failure, defects, and requirements are instead preserved at
  runtime through `Exit`, `Cause`, and `Context`.
- BoxLang lambdas replace `pipe` and generator-based `Effect.gen`; `map`,
  `flatMap`, and `tap` are the direct, idiomatic composition surface.
- Native `BoxFuture`, `asyncAll`, `asyncAny`, and named BoxLang executors power
  async work. The iterative interpreter blocks only its `io-tasks` virtual
  thread while it awaits a nested BoxFuture; `runFuture` remains non-blocking to
  its caller. BX Effect does not introduce a Promise, scheduler, or thread-pool
  subsystem.
- Fiber interruption delegates to `BoxFuture.cancel(true)`, so it is best
  effort. It requests cancellation of the outer interpreter task and its active
  nested BoxFuture; Scope ownership still requests cancellation and runs
  finalizers.
- `Queue` uses a JDK `ReentrantLock` and conditions behind lazy Effect
  operations. It retains explicit shutdown and BoxLang-native `Attempt`
  polling instead of reproducing every Effect TypeScript Queue strategy or
  Stream API. Queue state is application-owned, not automatically Scope-owned.
- `PubSub` adopts Effect v4's active-subscriber broadcast and slowest-subscriber
  bounded backpressure semantics, but begins with explicit subscription
  ownership. BX Effect defers replay buffers, dropping/sliding strategies,
  batches, and implicit Scope-owned subscriptions until their contracts fit the
  current Scope API.
- `Context` and `Layer` remain focused on Effect dependencies. BX Effect does
  not replace WireBox or application-wide dependency injection.
- `Schedule` is an in-process retry/repeat policy, not BoxLang Scheduler or a
  cron replacement.
- Native `Attempt` remains the absence/presence abstraction; `Result` and
  `Cause` are reserved for the richer expected-error and execution outcomes.

These choices keep the library aligned with Effect's programming model while
making its runtime behavior honest about BoxLang's dynamic type system and
platform facilities.

## Sources

- [Effect home and documentation](https://effect.website/)
- [Effect canonical repository and v4 beta status](https://github.com/Effect-TS/effect)
- [BoxLang asynchronous programming](https://boxlang.ortusbooks.com/boxlang-framework/asynchronous-programming)
- [BoxLang module configuration](https://boxlang.ortusbooks.com/boxlang-framework/module-development/configuration)
