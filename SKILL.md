---
name: bx-effect
description: "Use this skill when building BoxLang application workflows with bx-effect: lazy Effects, expected errors and defects, scoped resources, Context and Layers, ManagedRuntime ownership, concurrency, retries, and Streams."
---

# bx-effect: Compose BoxLang Workflows

## Installation and imports

Requires BoxLang 1.18.0+ and Java 21+. Install the module with either CLI:

```bash
install-bx-module bx-effect
# CommandBox
box install bx-effect
```

The package slug is `bx-effect`; its activated module name is `bxeffect`.
Use module imports after registration and activation:

```boxlang
import models.effect.Effect@bxeffect;

program = Effect::sync( () => 21 ).map( value => value * 2 );
println( Effect::runSync( program ) ); // 42
```

BX Effect has its own API; TypeScript Effect APIs are not interchangeable.
Use native BoxLang HTTP, JDBC, cache, logging, and Scheduler facilities inside
Effects. The module adds execution and ownership semantics around them.

## Build lazily, run at the boundary

Put work inside the supplied callback. `Effect::sync( () => loadUser() )`
defers the call; invoking `loadUser()` before constructing the Effect does not.
Use `Effect::suspend( () => ... )` when the callback itself returns an Effect.

| Operation | Callback/result |
| --- | --- |
| `sync(thunk)` | Synchronous success value; thrown exceptions become defects. |
| `map(mapper)` | Transform a success value synchronously. |
| `flatMap(mapper)` | Return the next Effect. |
| `tap(callback)` | Return an Effect while retaining the original success value. |
| `fromBoxFuture(factory)` | Lazily obtain a native BoxFuture; exceptional completion is a defect. |

Choose one outer execution boundary. Compose nested operations with `flatMap`
rather than repeatedly running them, so they share Context and Scope.

| Boundary | Result |
| --- | --- |
| `Effect::runSync(program)` | Value, or thrown `bxeffect.EffectFailureException`. |
| `Effect::runSyncExit(program)` | Exit containing the value or complete Cause. |
| `Effect::runFuture(program)` | Native BoxFuture of the value; failure completes exceptionally. |
| `Effect::runFutureExit(program)` | Native BoxFuture of an Exit. |
| `Effect::runFork(program)` | Fiber with `await`, `join`, `poll`, and `interrupt`. |

`runFuture` does not wait for completion; calling its future's `get()` does.
Imported class names are reserved case-insensitively: use locals such as
`program`, `outcome`, and `failureCause`, not `effect`, `exit`, or `cause`.

## Expected errors, defects, and interruption

Use `fail(error)` for domain failures, preferably with a stable `_tag`.
Use the named-argument `try` constructor to map an operation's exceptions:

```boxlang
program = Effect::try(
	try: () => JSONDeserialize( "invalid JSON" ),
	catch: error => { _tag: "InvalidInput", message: error.message }
).catchTag( "InvalidInput", error => Effect::succeed( { name: "Guest" } ) );

outcome = Effect::runSyncExit( program );
if ( outcome.isSuccess() ) {
	println( outcome.value().name ); // Guest
} else {
	println( outcome.cause().pretty() );
}
```

`catchAll` and `catchTag` recover pure expected failures only. Exceptions from
`sync`, transformations, and handlers remain defects; cancellation remains
interruption. Use `catchCause` only when deliberately handling the full Cause,
and `Effect::failCause(failureCause)` to re-emit it without losing information.
Use native Attempt for presence/absence, Result for success/expected failure,
and Exit for complete outcomes including defects and interruption.

## Services and application ownership

Import service APIs separately and provide explicit implementations:

```boxlang
import models.effect.context.Layer@bxeffect;
import models.effect.context.ServiceTag@bxeffect;

Greeting = ServiceTag::of( "app/Greeting" );
GreetingLive = Layer::succeed( Greeting, { prefix: "Hello" } );
greet = Effect::service( Greeting ).map( service => service.prefix & ", Ada!" );
println( Effect::runSync( greet.provide( GreetingLive ) ) ); // Hello, Ada!
```

Context bindings are immutable and nested provisioning restores the previous
Context on every exit. Missing services are wiring defects. `Layer::effect`
builds from an Effect. `Layer::scoped` is its resource-producing alias: pass an
Effect that registers release with `acquireRelease`; it adds no release itself.
`Layer::merge` builds in declaration order, allowing later recipes to consume
earlier services. Reusing a Layer instance within one Scope shares its build;
separate runtime runs build independently.

For services shared across requests or jobs, use an explicitly owned runtime.
Using `GreetingLive` and `greet` above:

```boxlang
import models.effect.ManagedRuntime@bxeffect;

runtime = ManagedRuntime::make( GreetingLive );
try {
	println( runtime.runSync( greet ) );
	println( runtime.runSync( greet ) );
} finally {
	closeOutcome = runtime.close();
	if ( closeOutcome.isFailure() ) {
		println( closeOutcome.cause().pretty() );
	}
}
```

Construction is lazy; concurrent first runs share one Layer build. Closing
rejects new runs with expected `ManagedRuntimeClosed`, interrupts and awaits
active run cleanup, then releases managed services once. At application scope,
create the runtime at startup and close it at application end. Each request
builds a fresh program with its own input. Shared services must be thread-safe;
use a datasource name or pool instead of sharing one JDBC connection.

WireBox/ColdBox integrations map a runtime instance explicitly; static Effect
and Layer APIs stay imports. Close it before container services disappear,
including ColdBox reinitialization. See the
[framework recipes](https://github.com/tonyjunkes/bx-effect/blob/main/docs/native-integrations.md#wirebox-and-coldbox)
for binder and interceptor ownership. The kernel installs no lifecycle hooks.

## Resources and shorter lifetimes

Wrap resource-producing work before transforming or using the acquired handle.
For an existing file path, `path`:

```boxlang
contents = Effect::scoped(
	Effect::acquireRelease(
		Effect::try(
			try: () => fileOpen( path, "read" ),
			catch: error => { _tag: "FileOpenError", message: error.message }
		),
		handle => Effect::sync( () => fileClose( handle ) )
	).flatMap( handle => Effect::sync( () => fileRead( handle ) ) )
);
println( Effect::runSync( contents ) );
```

`acquireRelease` ties release to the current Scope. `scoped` creates a shorter
lifetime: it finishes children and cleanup before following work or outer
recovery. Return computed values rather than handles already released by that
Scope. `acquireUseRelease(acquire, use, release)` offers a single-resource
lifetime; its release callback receives `(resource, useExit)`.
`ensuring(cleanup)` always runs an Effect; `onExit` supplies the full outcome.
Cleanup runs once in LIFO order on every exit and retains cleanup failures.

## Concurrency and time

```boxlang
program = Effect::forEach(
	[ 1, 2, 3 ],
	( value, index ) => Effect::sync( () => value * 2 ),
	{ concurrency: 2, mode: "accumulate" }
);
println( arrayToList( Effect::runFuture( program ).get() ) ); // 2,4,6
```

`forEach` defaults to sequential work; `all` defaults to unbounded child-Fiber
execution. Both default to fail-fast. Explicit `accumulate` waits for all
branches and combines Causes in input order. Set a concurrency limit for I/O.
Use `fromBoxFuture(() => nativeAsyncCall())` to keep future creation lazy.
Fibers are owned by their Scope; interruption is best effort, and cleanup is
awaited before their owning lifetime ends.

```boxlang
import models.effect.Schedule@bxeffect;

policy = Schedule::exponential( 100 ).maxDelay( 1000 ).and( Schedule::recurs( 3 ) );
retried = Effect::scoped( program ).retry( policy ).timeout( 5, "seconds" );
```

`retry` handles expected failures; `recurs(3)` allows three retries after the
initial attempt. `maxDelay` caps each wait, not total elapsed time; put it after
modifiers that can increase waits. `spaced` waits after completion; `fixed`
targets start times and skips missed intervals. Use native Scheduler for calendar
recurrence. Timeouts request interruption and await cleanup: arbitrary blocking
code may outlast the deadline. Configure native I/O deadlines separately.
For deterministic time tests, inject `models.effect.testing.TestClock@bxeffect`
through `new EffectRuntime( { clock: testClock } )`; it requires no TestBox.

## Streams and coordination

```boxlang
import models.effect.Stream@bxeffect;

firstTwo = Stream::fromArray( [ 1, 2, 3 ] )
	.mapEffect( value => Effect::sync( () => value * 2 ) )
	.take( 2 )
	.runCollect();
println( arrayToList( Effect::runSync( firstTwo ) ) ); // 2,4
```

Streams are reusable descriptions; consumers return Effects. Each consumption
pulls on demand and closes its cursor on every exit. `mapEffect`, `flatMap`, and
consumers run sequentially, without implicit read-ahead or parallelism.
Use Deferred for one-shot signaling, Semaphore `withPermit` for scoped permits,
Queue for FIFO buffering, and PubSub for broadcast. Queues and hubs are explicitly
application-owned; shut them down at their lifetime boundary. `fromQueue` owns
no Queue; `fromPubSub` owns only its per-consumer subscription. Their shutdown
becomes normal Stream completion.

## API details

Check the installed version before using newer operators. The
[public API inventory](https://github.com/tonyjunkes/bx-effect/blob/main/docs/public-api.md)
is the supported surface; `models.effect.internal` and cross-class interpreter
methods are private implementation details. For version-specific behavior, use
the corresponding release tag instead of `main` in these documentation URLs.

- [Error model](https://github.com/tonyjunkes/bx-effect/blob/main/docs/error-model.md): recovery and failure channels.
- [Resources](https://github.com/tonyjunkes/bx-effect/blob/main/docs/resources.md) and [Layers](https://github.com/tonyjunkes/bx-effect/blob/main/docs/services-and-layers.md): provisioning placement and ownership.
- [Concurrency](https://github.com/tonyjunkes/bx-effect/blob/main/docs/concurrency.md), [schedules](https://github.com/tonyjunkes/bx-effect/blob/main/docs/schedules.md), and [Streams](https://github.com/tonyjunkes/bx-effect/blob/main/docs/streams.md): advanced operators and coordination.
- [Native integrations](https://github.com/tonyjunkes/bx-effect/blob/main/docs/native-integrations.md): HTTP, JDBC transactions, caching, logging, and framework recipes.
