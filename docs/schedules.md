# Retry, Repeat, and Timeout

`Schedule` is an in-process recurrence policy, not a replacement for BoxLang
Scheduler or Scheduled Tasks.

```boxlang
request.retry( Schedule::recurs( 3 ) );
polling.repeat( Schedule::spaced( 1, "seconds" ) );
request.timeout( 5, "seconds" );
```

Available constructors are `recurs`, `spaced`, `fixed`, and `exponential`.
Schedules can be composed with `and`, `or`, `whileInput`, `untilInput`,
`maxDelay`, and `jittered`:

```boxlang
policy = Schedule::exponential( 100 )
	.jittered( 0.8, 1.2 )
	.whileInput( error => error.retryable );
```

Cap backoff and limit retries by composing a maximum wait with a recurrence
count:

```boxlang
policy = Schedule::exponential( 250 )
	.maxDelay( 10000 )
	.and( Schedule::recurs( 5 ) );

retried = Effect::scoped( oneAttempt ).retry( policy );
```

This allows at most five retries after the initial attempt. `maxDelay` caps
each computed wait, not the execution time or total elapsed retry budget. It
accepts the same units as the constructors and returns a new policy without
changing its source. A zero cap removes waits while retaining the underlying
continuation decision. Wrapping each attempt in `scoped` releases that attempt's
resources before its retry wait; wrapping the entire retry instead retains them
until the complete retry program finishes.

Modifiers apply in composition order. Put `maxDelay` after `jittered`, `and`,
or `or` when the cap must include their computed delays. A later modifier can
increase a previously capped wait. When a fixed schedule's wait is shortened,
its next timing anchor becomes the actual capped start target; an uncapped wait
or immediate overrun restart retains the normal fixed-schedule anchor.

`retry` only retries expected failures; defects remain defects. `repeat`
continues after success and returns the final successful value. `timeout` fails
with `{ _tag: "TimeoutError", duration, unit }` and requests interruption for
the losing fiber. Delays use the runtime Clock; the default live Clock delegates
to BoxFuture's native delayed executor.

Timeouts are **cooperative**. The runtime interrupts and awaits the losing
Fiber, including its finalizers, before returning. Synchronous user code that
ignores cancellation and slow cleanup can therefore extend execution beyond
the configured duration. A timeout does not abandon resources or forcibly stop
arbitrary code. Configure native HTTP/client/database deadlines as well when
the underlying operation needs its own limit.

Live `Clock.now()` measures monotonic milliseconds using `System.nanoTime()`,
anchored to wall time when that Clock instance is created. Wall-clock adjustments
do not change recurrence delays. It is an elapsed-time clock, not an authoritative
timestamp source; use native BoxLang date/time APIs for calendar timestamps.

`spaced( duration )` waits the full duration **after an execution completes**.
`fixed( duration )` targets recurrence start times at a fixed interval. When an
execution overruns its next target, the next iteration begins without an
additional delay; it does not attempt to run missed iterations. Both behaviors
use the runtime Clock, so `TestClock` can prove their timing without wall-clock
waiting. The immediate restart becomes the new interval anchor: with a 10 ms
interval and first execution finishing at 35 ms, starts are 0, 35, then 45 ms
when subsequent work is instantaneous, rather than several starts at 35 ms.

For deterministic TestBox coverage, supply a `TestClock` when constructing a
runtime and advance it explicitly:

```boxlang
import models.effect.EffectRuntime@bxeffect;
import models.effect.testing.TestClock@bxeffect;

clock = new TestClock();
runtime = new EffectRuntime( { clock: clock } );
fiber = runtime.runFork( Effect::sleep( 5, "seconds" ) );

clock.advance( 5, "seconds" );
fiber.join();
```

`TestClock` is published deterministic test support for downstream module
consumers. It does not depend on TestBox, replace BoxLang Scheduled Tasks, or
create an application scheduler.

A zero-duration TestClock sleep returns an already completed native BoxFuture.
Count-only recurrence therefore needs no explicit clock advancement.
