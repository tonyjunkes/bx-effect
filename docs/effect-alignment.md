# Effect Alignment and BoxLang-Native Choices

BX Effect adopts the ideas that make Effect useful—lazy values, distinct error
channels, explicit dependencies, scopes, structured concurrency, and recurrence
policies—rather than attempting a source-compatible port of TypeScript APIs.

## Current upstream check

Checked 2026-08-23 against Effect main at commit
[`1144032cedda7b5eacc1ebf980d06957c7a59ddf`](https://github.com/Effect-TS/effect/tree/1144032cedda7b5eacc1ebf980d06957c7a59ddf).
The Effect API site identified v4 as release candidate `4.0.0-rc.111` at that
review point. BX Effect tracks stable concepts rather than beta/RC spellings,
does not promise source compatibility, and pins each comparison so future
upstream changes are explicit.

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
- Fiber interruption remains best effort for arbitrary user code. It requests
  cancellation of the outer interpreter task and active nested BoxFuture, and
  directly interrupts the worker only while it is inside a known interruptible
  Semaphore, Queue, or PubSub runtime instruction. Scope ownership still runs
  finalizers.
- `Queue` uses a JDK `ReentrantLock` and conditions behind lazy Effect
  operations. It retains explicit shutdown and BoxLang-native `Attempt`
  polling instead of reproducing every Effect TypeScript Queue strategy.
  Queue state is application-owned, not automatically Scope-owned.
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
- `ManagedRuntime` explicitly owns one application Layer across repeated runs;
  it is never installed as a module-global singleton.
- BX Effect `Stream` is a pull-based Effect description using native array
  batches and `Attempt` end-of-stream. It is not Java `Stream`, and it does not
  introduce upstream Channel, Sink, Chunk, or scheduler layers.

These choices keep the library aligned with Effect's programming model while
making its runtime behavior honest about BoxLang's dynamic type system and
platform facilities.

## Sources

- [Effect home and documentation](https://effect.website/)
- [Pinned Effect source review](https://github.com/Effect-TS/effect/tree/1144032cedda7b5eacc1ebf980d06957c7a59ddf)
- [BoxLang asynchronous programming](https://boxlang.ortusbooks.com/boxlang-framework/asynchronous-programming)
- [BoxLang module configuration](https://boxlang.ortusbooks.com/boxlang-framework/module-development/configuration)
