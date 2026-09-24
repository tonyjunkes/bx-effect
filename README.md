# BX Effect

Build workflows with consistent error handling, retries, concurrency, and resource cleanup.

BX Effect is a BoxLang module for combining operations such as HTTP requests,
database queries, and file processing into reusable programs. Define the work,
choose how failures should be handled, and run it synchronously or asynchronously.

Use it when a workflow needs more than a single function call: retry a failed
request, process a batch with a concurrency limit, supply services for testing,
or release resources when work finishes or is interrupted. You can introduce it
around one operation and build from there.

Inspired by [Effect](https://effect.website/), BX Effect provides its own API for
BoxLang applications.

## Requirements

- BoxLang 1.16.0+
- Java 21+

## Supported Features

| Capability | What you can do |
| --- | --- |
| Workflow composition | Transform results with `map`, chain operations with `flatMap`, and observe values with `tap`. |
| Error handling | Recover from expected errors while keeping unexpected defects and interruption distinguishable. Inspect complete outcomes with `Exit` and `Cause`. |
| Retries and timing | Retry failed operations, repeat successful ones, add delays, and set timeouts with reusable `Schedule` policies. |
| Concurrency | Run batches with a concurrency limit, race operations, and manage running work through Fibers. Integrate existing `BoxFuture` APIs. |
| Resource cleanup | Pair acquisition with release and run finalizers on success, failure, or interruption. |
| Dependency management | Supply services through `Context` and `Layer`, and reuse services across runs with `ManagedRuntime`. |
| Coordination | Signal completion with `Deferred`, limit access with `Semaphore`, buffer work with `Queue`, and broadcast through `PubSub`. |
| Streams | Transform and consume sequences on demand, including Queue and PubSub sources, with cleanup when consumption ends. |
| Testing and diagnostics | Control time with `TestClock` and observe runtime events with an optional observer or logging adapter. |

## Installation

> You can refer to the [official BoxLang modules docs](https://boxlang.ortusbooks.com/getting-started/installation/modules) for which runtime option may best suit your needs.

### BoxLang CLI

```bash
install-bx-module bx-effect
```

### CommandBox CLI

```bash
box install bx-effect
```

## Usage

### Example workflow

```boxlang
import models.effect.Effect@bxeffect;

program = Effect::sync( () => jsonDeserialize( '{"name":"Sam"}' ) )
	.map( user => "Hello, " & user.name & "!" );

println( Effect::runSync( program ) ); // Hello, Sam!
```

An **Effect** describes an operation and how to handle its result. `sync` wraps
a function, `map` transforms its success value, and `runSync` executes the
program. The supplied functions run when you execute the program; building the
chain does not call them.

Use `flatMap` when the next step returns another Effect, and `tap` when you want
to run an Effect without replacing the current success value.

### Handle expected errors

Use `Effect::try()` to turn exceptions from an operation into errors your
application can handle. This complete example falls back to a guest user when
JSON parsing fails:

```boxlang
import models.effect.Effect@bxeffect;

program = Effect::try(
		try: () => jsonDeserialize( "invalid JSON" ),
		catch: error => { _tag: "InvalidUserData", message: error.message }
	)
	.catchTag( "InvalidUserData", error => Effect::succeed( { name: "Guest" } ) )
	.map( user => user.name );

println( Effect::runSync( program ) ); // Guest
```

The `_tag` field identifies an error for `catchTag`. Use `Effect::fail()` to
report an expected error directly, or `catchAll` to recover from any expected
error. Exceptions thrown by `sync`, transformations, or handlers are **defects**;
`catchAll` and `catchTag` do not recover them. `catchCause` explicitly handles the
complete failure, including defects and interruption.

Add `.retry( Schedule::recurs( 3 ) )` before recovery to allow up to three retries
after the initial attempt, importing `models.effect.Schedule@bxeffect` first.
Retry applies to expected errors only. The [schedules guide](docs/schedules.md)
covers delays, backoff, repeat, and timeout policies.

### Process a batch concurrently

`forEach` creates an Effect for each input and limits how many run at once.
This example normalizes names and returns the results in input order:

```boxlang
import models.effect.Effect@bxeffect;

program = Effect::forEach(
	[ "sam", "alex", "jordan" ],
	( name, index ) => Effect::sync( () => uCase( name ) ),
	{ concurrency: 2 }
);

future = Effect::runFuture( program );
println( arrayToList( future.get() ) ); // SAM,ALEX,JORDAN
```

`runFuture` returns a `BoxFuture` without waiting for the program to finish;
`get()` waits for its result. Replace the per-item operation with your own
Effect to process files, make requests, or save records.

`all` and `forEach` fail fast by default. Set `mode: "accumulate"` in the options
to wait for all branches and retain their failures in input order. See the
[concurrency guide](docs/concurrency.md) for cancellation and coordination.

### Choose how to run a program

| Method | Result |
| --- | --- |
| `Effect::runSync( program )` | The success value, or a thrown `bxeffect.EffectFailureException`. |
| `Effect::runSyncExit( program )` | An `Exit` containing the success value or complete failure `Cause`. |
| `Effect::runFuture( program )` | A `BoxFuture` that completes with the success value or exceptionally on failure. |
| `Effect::runFutureExit( program )` | A `BoxFuture` that completes with an `Exit`. |
| `Effect::runFork( program )` | A `Fiber` you can poll, join, or request to interrupt. |

Choose an `Exit` method when you want to inspect failure as a value instead of
catching an exception. Fiber interruption is best effort; scoped cleanup still
runs. For services shared across repeated runs, use
[`ManagedRuntime`](docs/managed-runtime.md) and close it when their lifetime ends.

## Guides

Start with [Getting started](docs/getting-started.md), then choose a guide for
the next concern in your application:

| Guide | Learn how to… |
| --- | --- |
| [Error handling and outcomes](docs/error-model.md) | Distinguish expected errors, defects, and interruption; work with `Exit`, `Cause`, and `Attempt`. |
| [Resources and cleanup](docs/resources.md) | Acquire resources, register release actions, and handle cleanup failures. |
| [Services and Layers](docs/services-and-layers.md) | Declare dependencies, provide implementations, and compose service setup. |
| [ManagedRuntime](docs/managed-runtime.md) | Reuse application services across runs and shut them down safely. |
| [Concurrency and coordination](docs/concurrency.md) | Use BoxFutures, Fibers, Deferred, Semaphore, Queue, and PubSub. |
| [Streams](docs/streams.md) | Build and consume sequences with demand-driven processing and resource cleanup. |
| [Schedules and timeouts](docs/schedules.md) | Configure retries, repeats, and timeouts, and test timing with `TestClock`. |
| [Runtime observability](docs/observability.md) | Observe runtime events and connect an existing logger. |
| [BoxLang integration recipes](docs/native-integrations.md) | Wrap HTTP, database, file, and asynchronous operations. |
| [Incremental adoption](docs/migration-from-imperative-code.md) | Introduce Effects into existing application code. |
| [Public API and compatibility](docs/public-api.md) | Find the supported classes and methods for the 1.x API. |

## Contributing & Testing

Bug reports, documentation improvements, and pull requests are welcome through
[GitHub](https://github.com/tonyjunkes/bx-effect). Include a small reproduction and
your BoxLang and Java versions when reporting a bug. Add focused tests for
behavior changes and update the relevant guide when public behavior changes.

After cloning the repository, install the development dependencies and run the
TestBox suite from the repository root:

```bash
# Using CommandBox
box install
box run-script test
```

The suite runs through the BoxLang CLI (via CommandBox or an OS install of BoxLang if preferred).
CI runs the TestBox suite and module-setting checks on BoxLang `latest` and
`snapshot`. For performance work, see the [benchmarks](benchmarks/README.md).
