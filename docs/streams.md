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
return Effects and run sequentially. `concat` and `flatMap` are also sequential;
the MVP has no implicit parallelism or buffering.

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

The MVP deliberately has no Channel, Sink, Chunk, replay, merge, concurrent
flatMap, dropping/sliding buffer, or Java Stream wrapper.
