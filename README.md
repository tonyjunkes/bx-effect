# BX Effect

Lazy, composable effects for BoxLang applications.

BX Effect turns side-effecting work—database calls, HTTP requests, file access,
concurrent jobs, and resource lifecycles—into values that can be composed before
they run. It gives BoxLang applications a consistent way to model success,
recoverable errors, unexpected defects, interruption, retries, cleanup, and
dependencies without introducing a separate async or scheduling platform.

BX Effect is inspired by [Effect](https://effect.website/) and designed around
BoxLang's native runtime facilities, including `BoxFuture`, `Attempt`, named
executors, and virtual threads.

## Why BX Effect?

Ordinary `try`/`catch`, callbacks, and futures work well in isolation, but become
harder to reason about when an operation also needs retries, parallelism,
cancellation, dependency wiring, or guaranteed cleanup. BX Effect keeps those
concerns in one lazy, fluent program:

- **Lazy execution** — describe work now and run it only at an explicit boundary.
- **Clear failure channels** — distinguish expected errors, defects, and interruption.
- **Composable workflows** — transform and sequence work with `map`, `flatMap`, and `tap`.
- **Resource safety** — guarantee LIFO cleanup across every exit path.
- **Structured concurrency** — run, bound, race, and interrupt work with BoxLang-native futures.
- **Resilience policies** — retry, repeat, delay, and time out operations with reusable schedules.
- **Explicit dependencies** — provide services through isolated `Context` and `Layer` values.
- **Coordination primitives** — use `Deferred`, `Semaphore`, `Queue`, and `PubSub` in Effect programs.
- **Stack-safe interpretation** — compose deeply without growing the JVM call stack.

## Requirements

- BoxLang 1.16.0 or newer
- Java 21 or newer

## Installation

For a BoxLang CLI application, install the module globally:

```bash
install-bx-module bx-effect
```

To keep the module local to the current application:

```bash
install-bx-module bx-effect --local
```

For a CommandBox-managed application:

```bash
box install bx-effect
```

Import BX Effect classes through the module mapping in each file that uses them:

```boxlang
import models.effect.Effect@bxEffect;
```

## Quick start

An Effect is a description of work. Creating or transforming it does not execute
the supplied functions:

```boxlang
import models.effect.Effect@bxEffect;

program = Effect::sync( () -> {
	println( "Running the effect" );
	return 21;
} ).map( value -> value * 2 );

// Nothing above has run yet.
result = Effect::runSync( program );
println( result ); // 42
```

Execution begins at a runtime boundary such as `runSync`, `runSyncExit`,
`runFuture`, or `runFork`.

## Expected errors and defects

Use `Effect::fail()` for recoverable domain errors. Use `Effect::try()` when an
exception from existing code should be mapped into that expected-error channel:

```boxlang
import models.effect.Effect@bxEffect;

program = Effect::try(
	try: () -> userGateway.find( userId ),
	catch: error -> {
		_tag : "UserLookupFailed",
		message : error.message
	}
)
	.filterOrFail(
		user -> user.active,
		user -> { _tag: "InactiveUser", id: user.id }
	)
	.catchTag(
		"InactiveUser",
		error -> Effect::succeed( anonymousUser )
	);

exit = Effect::runSyncExit( program );
```

Exceptions thrown by `sync`, mappers, or handlers are retained as defects.
`catchAll` and `catchTag` recover expected errors only; `catchCause` is the
explicit boundary for handling the complete failure cause.

## Concurrency and async work

BX Effect runs asynchronous work through native BoxLang executors and returns
native `BoxFuture` values at async boundaries:

```boxlang
import models.effect.Effect@bxEffect;

program = Effect::forEach(
	users,
	( user, index ) -> saveUserEffect( user ),
	{ concurrency: 4 }
);

future = Effect::runFuture( program );
savedUsers = future.get();
```

`Effect::all()` preserves input order and fails fast by default. Use
`{ mode: "accumulate" }` to wait for every branch and retain all failures. Use
`race`, `firstSuccessOf`, `fork`, and Fiber interruption for other structured
concurrency patterns.

Existing asynchronous APIs remain lazy by supplying a future factory:

```boxlang
request = Effect::fromBoxFuture(
	() -> futureNew( () -> httpClient.get( url ) )
);
```

## Retry, repeat, and timeout

Schedules are reusable policies for in-process recurrence:

```boxlang
import models.effect.Schedule@bxEffect;

policy = Schedule::exponential( 100, "milliseconds" )
	.jittered( 0.8, 1.2 )
	.whileInput( error -> error.retryable );

response = request
	.retry( policy )
	.timeout( 5, "seconds" );
```

`retry` retries expected failures only. `repeat` recurs after successful work,
and `timeout` fails with a tagged `TimeoutError`.

## Safe resource lifecycles

`acquireRelease` ties a resource to the running Scope. Its release action runs
exactly once after success, expected failure, defect, or interruption:

```boxlang
connection = Effect::acquireRelease(
	Effect::sync( () -> datasource.getConnection() ),
	db -> Effect::sync( () -> db.close() )
);

program = connection.flatMap(
	db -> Effect::sync( () -> db.query( "select * from users" ) )
);
```

Use `ensuring` for unconditional cleanup and `onExit` when cleanup needs the
program's complete `Exit`.

## Services and layers

`ServiceTag` identifies an application dependency, while a `Layer` describes
how to build and provide it:

```boxlang
import models.effect.Effect@bxEffect;
import models.effect.context.Layer@bxEffect;
import models.effect.context.ServiceTag@bxEffect;

Database = ServiceTag::of( "app/Database" );

DatabaseLive = Layer::effect(
	Database,
	Effect::sync( () -> datasource.getConnection() )
);

program = Effect::service( Database )
	.flatMap( db -> Effect::sync( () -> db.query( "select 1" ) ) )
	.provide( DatabaseLive );
```

Provisioned contexts are isolated and restored after the nested program
finishes. Layers can be merged into ordered service recipes and scoped when a
service owns resources.

## Runtime boundaries

| Boundary | Result |
| --- | --- |
| `Effect::runSync( program )` | Returns the success value or throws `BXEffect.EffectFailure`. |
| `Effect::runSyncExit( program )` | Returns an `Exit` containing either the value or full `Cause`. |
| `Effect::runFuture( program )` | Returns a native `BoxFuture` of the success value. |
| `Effect::runFutureExit( program )` | Returns a native `BoxFuture` that resolves to an `Exit`. |
| `Effect::runFork( program )` | Returns a logical `Fiber` for polling, joining, or interruption. |

## Guides

- [Getting started](docs/getting-started.md)
- [Expected errors, defects, and Exit](docs/error-model.md)
- [Services and Layers](docs/services-and-layers.md)
- [Resource safety](docs/resources.md)
- [BoxFutures, Fibers, and coordination](docs/concurrency.md)
- [Schedules, retry, repeat, and timeout](docs/schedules.md)
- [Runtime observability](docs/observability.md)
- [Incremental migration](docs/migration-from-imperative-code.md)

## Contributing

Clone the repository and install its development dependency:

```bash
box install
```

Run the TestBox suite from the repository root:

```console
box run-script test
```

The package script runs TestBox through BoxLang's CLI runtime and does not
require a web server.
