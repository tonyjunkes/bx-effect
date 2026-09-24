# BoxFutures and Fibers

BX Effect reuses BoxLang BoxFutures and named executors. `fromBoxFuture` takes
a factory so construction stays lazy:

```boxlang
request = Effect::fromBoxFuture(
    () => futureNew( () => httpClient.get( url ) )
);
```

`runFuture` yields a native BoxFuture of the success value; `runFutureExit`
yields a BoxFuture of `Exit`. `runFork` or `program.fork()` creates a logical
`Fiber` with `await`, `join`, `poll`, `interrupt`, `isDone`, and `id`.

The default executor is read lazily from the activated module's
`defaultExecutor` setting (which defaults to BoxLang's `io-tasks`). Applications
can override that module setting in their BoxLang configuration or construct a
runtime explicitly with a different existing BoxLang executor:

```boxlang
runtime = new EffectRuntime( { executor: "cpu-tasks" } );
future = runtime.runFuture( cpuBoundProgram );
```

## Async execution model

`io-tasks` is BoxLang's built-in virtual-thread executor for unlimited
I/O-bound work. BX Effect deliberately runs its iterative interpreter there and
awaits nested BoxFutures with `get()`. This keeps scheduling, executor
ownership, and future behavior entirely in BoxLang rather than introducing a
second scheduler or a custom continuation framework.

Consequently, `runFuture` and `runFutureExit` return immediately, while their
interpreter task may wait in a virtual thread. `runSync` is the explicit
caller-blocking boundary. The async and concurrency benchmarks exercise 64 and
256 concurrently delayed branches; retain those checks when changing executor
or async-boundary behavior.

Use `io-tasks` for programs that wait for child work. A bounded executor can
starve if all its workers wait for children submitted to the same pool.
An explicitly selected CPU executor suits work that does not wait on that pool;
it is not a substitute for the default executor for structured I/O workflows.

`runFuture` mirrors `runSync`: an Effect failure completes the native BoxFuture
exceptionally. `get()` exposes BoxLang's normal execution wrapper around the
underlying `bxeffect.EffectFailureException`; choose `runFutureExit` when the future
should resolve to an `Exit` for both outcomes.

Use `Effect::all`, `race`, or `firstSuccessOf` for concurrent programs. Branches
inherit the caller's Context and are owned by its Scope. Cancellation is
best-effort because BoxFuture executors cannot forcibly stop arbitrary user
code. An interrupted Fiber requests cancellation of both its outer runtime
future and the native BoxFuture currently awaited by the interpreter. Scope
finalizers still follow their normal lifecycle path.

The interpreter also observes a cancellation request between instructions, so
work after the canceled instruction does not resume merely because no native
wait was active at that instant. Parent Scope shutdown stops child admission,
requests interruption for every admitted child, and waits for each child's
internal termination before releasing shared scoped resources. Arbitrary user
code that cannot be interrupted may therefore delay the parent boundary until
it returns; this is the resource-safe consequence of best-effort cancellation.

If cancellation causes an async, sleep, semaphore, Queue, or concurrent
collection wait to throw, the runtime normalizes that boundary to the Fiber's
interruption Cause. It never exposes a native canceled-wait wrapper as a
defect.

`Effect::all` accepts an optional policy struct:

```boxlang
Effect::all( programs, { concurrency: 4, mode: "failFast" } );
```

`concurrency` is a positive integer or `"unbounded"` (the default). `all`
preserves success-value order. Its default `"failFast"` mode requests
interruption for unfinished started branches after the first failure, waits for
their interpreters to terminate, and skips branches not yet started.

Use `mode: "accumulate"` when every branch must be attempted. It continues
starting bounded work after failures, waits for all started branches, and
returns every failure in a deterministic parallel `Cause` in input order.
Accumulation does not request sibling interruption merely because one branch
fails.

Both fail-fast `all` and a successful `firstSuccessOf` request interruption of
running losers and wait for their interpreters to terminate before returning.
A losing branch's Scope still runs its finalizers exactly once; interruption
remains best effort for arbitrary user code.

`race` returns the first completed success or failure, requests interruption
for unfinished losers, and waits for their interpreters to terminate.
`firstSuccessOf` keeps waiting after failures and
returns the first success; if every branch fails, it returns a parallel Cause
containing all branch failures in input order.

Use `forEach` to map a BoxLang array to Effects. The mapper is lazy, output
order follows input order, and it runs sequentially by default. Supply the same
`concurrency` policy to opt into parallel work:

```boxlang
Effect::forEach( users, ( user, index ) => saveUser( user ), {
	concurrency : 4
} );
```

Pass `{ discard: true }` when the work matters but collected values do not.
The interpreter drops successful branch outputs instead of building a result
array. Input descriptions are still finite and eager; use Stream for pull-based
input. Prefer a bounded concurrency limit for large collections: unbounded
completion selection still traverses the active set.

Failed loser cleanup is retained by `race`, `firstSuccessOf`, and fail-fast
`all`, in sequence after the primary outcome. A successful winner can therefore
produce a failure when a loser cannot release its resources. Ordinary loser
errors and interruption alone do not replace a successful winner. Root shutdown
also retains cleanup failures from unjoined children; see [resources](resources.md).

## Deferred

`Deferred` is a single-assignment signal for coordinating Fibers. It wraps a
native BoxFuture; it is not another promise implementation. Completion methods
return lazy Effects and only the first completion wins.

```boxlang
import models.effect.Deferred@bxeffect;
import models.effect.Effect@bxeffect;

signal = Deferred::make();
waiter = Effect::runFork( signal.await() );

Effect::runSync( signal.succeed( "ready" ) );
value = waiter.join();
```

`succeed`, `fail`, `die`, and `interrupt` complete the signal with the
corresponding `Exit` channel. Use `complete( exit )` when a complete Cause must
be retained. `poll()` returns native `Attempt` containing an `Exit` when the
signal is complete.

Each `await()` creates a dependent native future for that waiter. Interrupting
one waiting Fiber therefore does not cancel the shared Deferred or other
waiters; the original signal can still be completed.

## Semaphore

`Semaphore` coordinates a bounded number of concurrent critical sections. It
uses a fair `java.util.concurrent.Semaphore` internally, while `acquire()` and
`release()` remain lazy Effects.

```boxlang
import models.effect.Effect@bxeffect;
import models.effect.Semaphore@bxeffect;

databaseSlots = Semaphore::make( 8 );

result = Effect::runSync(
	databaseSlots.withPermit( queryEffect )
);
```

Prefer `withPermit()` for application work. It releases exactly one permit only
after a successful acquisition, including when protected work fails, defects,
or the owning Fiber is interrupted. A Fiber interrupted while waiting does not
acquire or release a permit. As with all runtime waits, Fiber interruption is
best effort and relies on the configured BoxLang executor to interrupt the
waiting runtime thread.

## Queue

`Queue` provides an Effect-aware FIFO buffer with explicit shutdown. Use
`Queue::bounded( capacity )` for backpressure or `Queue::unbounded()` when no
producer limit is required. It uses a JDK `ReentrantLock` and conditions to
coordinate mutable queue state; its blocking operations are interpreter
instructions, not nested worker futures.

```boxlang
import models.effect.Effect@bxeffect;
import models.effect.Queue@bxeffect;

requests = Queue::bounded( 64 );
Effect::runSync( requests.offer( request ) );
nextRequest = Effect::runSync( requests.take() );
```

`offer()` and `take()` are lazy. A bounded `offer()` waits until a consumer
makes room, and an empty `take()` waits for a producer. `poll()` is the
non-blocking inspection operation: it returns native `Attempt` and, if it
removes an item, wakes one blocked producer.

Messages must be non-null so a present poll result always identifies a message.
`offer(null)` constructs lazily but fails with an `InvalidQueueValueException`
defect when run, without inserting a message or waiting for capacity. Argument
validation precedes shutdown handling; even a closed queue rejects null this way.

`shutdown()` is lazy and idempotent: the first execution returns `true`; later
executions return `false`. It wakes blocked producers and consumers. Existing
buffered items can still be taken after shutdown; once drained, `take()` and
all post-shutdown `offer()` operations fail in the expected-error channel with:

```boxlang
{
	_tag : "QueueShutdown",
	operation : "offer" // or "take"
}
```

Fiber interruption of a blocked `offer()` or `take()` produces an interruption
Cause. The runtime observes its cancellation state before mutating the queue,
so a canceled producer does not insert a value and a canceled consumer does not
remove a subsequently available value. As with every Fiber operation,
interruption remains best effort if arbitrary user code itself is running.

Queue state is deliberately not Scope-owned and is never closed automatically.
The application that creates a Queue owns its lifetime and should execute
`shutdown()` when its producers and consumers must stop. Queue does not imply a
subscription, broadcast, or Stream/Sink API.

## PubSub

`PubSub` broadcasts each accepted value to every subscription that is active at
publication. Unlike Queue consumers, subscribers do not compete for a shared
item. Use `PubSub::bounded( capacity )` to make a publisher wait for the
slowest active subscriber, or `PubSub::unbounded()` when that limit is not
needed.

```boxlang
import models.effect.Effect@bxeffect;
import models.effect.PubSub@bxeffect;

events = PubSub::bounded( 64 );
subscription = Effect::runSync( events.subscribe() );

Effect::runSync( events.publish( { type: "Created" } ) );
event = Effect::runSync( subscription.take() );
Effect::runSync( subscription.unsubscribe() );
```

`subscribe()`, `publish()`, and `take()` are lazy Effects. Messages are
delivered only to subscriptions active when `publish()` runs; no replay buffer
is retained for a later subscriber. In a bounded hub, a publish waits when any
active subscription has reached capacity. Taking from, or unsubscribing, that
slow subscriber makes room for blocked publishers.

Messages must be non-null. `publish(null)` fails lazily with an
`InvalidPubSubValueException` defect without delivery or capacity consumption,
including with no subscribers or after shutdown. This keeps subscription
`poll(): Attempt<value>` unambiguous.

Subscriptions are explicit application-owned resources. Prefer
`withSubscription( use )` when the consumer has one Effect lifetime:

```boxlang
value = Effect::runSync(
	events.withSubscription( subscription =>
		events.publish( "ready" ).flatMap( () => subscription.take() )
	)
);
```

It releases the subscription with `ensuring` after `use` succeeds, fails,
defects, or is interrupted. Explicit subscriptions must eventually run
`unsubscribe()`; subscribing does not implicitly attach to a runtime Scope.

`shutdown()` is lazy and idempotent. It drops pending subscription values,
wakes all blocked operations, and makes later `publish`, `subscribe`, and
`take` calls fail through the expected-error channel:

```boxlang
{ _tag : "PubSubShutdown", operation : "publish" }
{ _tag : "SubscriptionShutdown", operation : "take" }
```

The first form represents the closed hub; the second represents an explicitly
unsubscribed subscription. Interruption of a blocked publish or take remains a
Fiber interruption Cause and does not deliver or consume a later value.

This intentionally omits Effect v4's replay, dropping, sliding, batch, and
implicit Scope-owned subscription strategies. Those need separate semantics and
tests before BX Effect broadens the API, and PubSub is not a Stream/Sink API.
