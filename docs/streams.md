# Pull-based Streams

A BX Effect `Stream` describes zero or more effectful values. It is lazy and
reusable: every consumer opens a fresh cursor, requests one batch at a time,
and closes the source after success, failure, defect, or interruption.

```boxlang
import models.effect.Effect@bxeffect;
import models.effect.Stream@bxeffect;

program = Stream::fromArray( users )
	.filter( user -> user.active )
	.mapEffect( user -> saveUser( user ) )
	.take( 100 )
	.runCollect();

saved = Effect::runSync( program );
```

Streams use native arrays as pull batches and native `Attempt` for
end-of-stream. An empty Attempt means normal completion; expected errors,
defects, and interruption remain in the Effect Cause.

Demand propagates through operators and resource/Context/recovery wrappers.
`fromArray(users).mapEffect(fetchProfile).take(1)` maps only the first value;
`filter` examines only enough inputs to find the next match. `takeWhile` must
inspect its first rejected value, then stops. `grouped(10).take(1)` requests
only the first ten inputs, and `flatMap` opens one inner Stream at a time.
An effectful consumer failure stops further upstream transformations.

**Compatibility note:** earlier 1.1.0 array Streams transformed an entire
source batch before applying downstream limits. Unrequested callbacks, failures,
and defects now remain unevaluated. Side effects around `flatMap` interleave
with inner consumption rather than all outer mappings running first. Array
structure is still snapshotted when `fromArray` is constructed, and each run
has its own position. Full collection/folding may still process arrays in batches;
batch size is private and should not be used as an application contract.

## Stateful and resource-backed sources

`unfoldEffect` produces one value at a time. Its step returns an Effect of empty
Attempt to finish or present `{ value, state }` to continue:

```boxlang
pages = Stream::unfoldEffect( 1, page ->
	page > 5
		? Effect::succeed( attempt() )
		: fetchPage( page ).map( response -> attempt( {
			value : response,
			state : page + 1
		} ) )
);
```

Use `Stream::acquireRelease(acquire, release, use)` when the source owns a file
handle, cursor, or other resource. Acquisition starts only when a consumer runs.
Early `take`, consumer failure, and Fiber interruption release exactly once.

## Transforming and consuming

`map`, `filter`, `take`, `drop`, and `runFold` use synchronous callbacks;
exceptions are defects. `mapEffect`, `tap`, and `runForEach` take callbacks that
return Effects and run sequentially by default. `concat` and `flatMap` are also
sequential. Explicit concurrent mapping is described below.

## Bounded concurrent mapping

Use `mapEffect(mapper, { concurrency: N })` for independent asynchronous work.
The default remains sequential; `N` must be a positive whole number. For example,
given an application `loadProfile(id)` that returns an Effect:

```boxlang
profiles = Stream::fromArray( userIds )
	.mapEffect( id => loadProfile( id ), { concurrency: 8 } )
	.runForEach( profile => saveProfile( profile ) );

Effect::runSync( profiles );
```

Use concurrency for independent work that spends time waiting. Sequential
mapping can be faster for immediate transformations or small cached file reads;
measure with your native client, payload sizes and latency before choosing a limit.

Results preserve input order. Set `unordered: true` to deliver in completion
order when rows are independent. Ordered output can wait behind a slow earlier
item. Both modes bound started-but-not-delivered mappings to `N`, including
completed results waiting for delivery; the bound counts values, not their byte
sizes or memory already owned by the source. Use `runForEach`, `runFold`, or
`runDrain` for incremental consumption; `runCollect` retains the output array.

Work starts on demand. The next pull refills the window, so `take(1)` can start
up to `N` mappings but starts no replacement after receiving its final value.
Concurrent mapper work has a local Scope per item: resources acquired inside a
mapper are released before that mapped value is delivered. Return computed
values; share longer-lived services through an outer Context or ManagedRuntime.

Mapping fails fast. A failure interrupts and awaits the admitted work, then
closes the source before following work or outer recovery. Cleanup failures
remain in the Cause. External side effects already completed are not rolled
back. To continue past expected per-row failures, return `Result` values:

```boxlang
import models.effect.Result@bxeffect;

outcomes = Stream::fromArray( userIds ).mapEffect(
	id => loadProfile( id )
		.map( profile => Result::success( profile ) )
		.catchAll( error => Effect::succeed( Result::failure( error ) ) ),
	{ concurrency: 8, unordered: true }
);
```

Defects and interruption still terminate this pipeline. Early termination and
cancellation await mapper cleanup before source release. Resources acquired during
upstream pulls also remain available until admitted mappers and their cleanup
finish. As with other Effect
concurrency, non-cooperative work can delay that boundary. Use the native
operation's own deadlines where appropriate. Concurrency one uses the existing
sequential path and its resource lifetime.

## Sequential operators

`takeWhile(predicate)` excludes the first rejected value and stops further
pulls; its cursor still closes on early completion. `scan(initial, reducer)`
emits the initial accumulator before pulling, then every updated accumulator.
Treat the seed and results as immutable; use `Stream::suspend(() => ...)` to
allocate a fresh mutable seed if needed. Synchronous callback exceptions are
defects, just as with `map`.

`grouped(size)` emits native arrays with up to a positive whole `size` values.
It fills one group on demand across source batches, emitting a final partial
group only at normal completion. Source failure keeps its Cause and discards
an unfinished group. It retains at most the current source batch and one group;
it never reads ahead for a later group.

```boxlang
batches = Stream::fromArray( [ 1, 2, 3, 4, 5 ] ).grouped( 2 );
// runCollect yields [ [1, 2], [3, 4], [5] ]
progress = Stream::fromArray( [ 1, 2, 3 ] ).scan( 0, ( total, value ) => total + value );
// runCollect yields [0, 1, 3, 6]
```

Repeated `concat` builds an immutable description graph in constant work per
append. Each consumer flattens it iteratively once, and still opens sources
one at a time, closing the previous cursor before opening the next.

`catchAll` recovers a pure expected failure only. Use `catchCause` when recovery
deliberately includes defects, interruption, or composite Causes. `provide`
keeps services visible during source acquisition, every pull, and release.

## Queue and PubSub bridges

Every consumer closes its cursor before returning to following Effect work or
outer error recovery, including early `take` completion. Resource acquisition
also registers an idempotent fallback for interruption or failure during cursor
opening. Releases run once; a release failure remains in the consumer's Cause.

`Stream::fromQueue(queue)` requests one value at a time and does not own the
Queue. After shutdown, buffered values drain and `QueueShutdown` becomes normal
stream completion.

`Stream::fromPubSub(pubSub)` acquires one subscription per consumption and
unsubscribes it on every exit. Hub or subscription shutdown is normal stream
completion. The Stream never shuts down the PubSub itself. Because pulls are
demand-driven, a bounded PubSub naturally backpressures publishers at the
slowest active Stream consumer.

The module provides no Channel, Sink, Chunk, replay, merge, concurrent flatMap,
dropping/sliding buffer, or Java Stream wrapper.
