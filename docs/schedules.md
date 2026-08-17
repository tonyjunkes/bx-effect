# Retry, Repeat, and Timeout

`Schedule` is an in-process recurrence policy, not a replacement for BoxLang
Scheduler or Scheduled Tasks.

```boxlang
request.retry( Schedule::recurs( 3 ) );
polling.repeat( Schedule::spaced( 1, "seconds" ) );
request.timeout( 5, "seconds" );
```

Available constructors are `recurs`, `spaced`, `fixed`, and `exponential`.
Schedules can be composed with `and`, `or`, `whileInput`, `untilInput`, and
`jittered`:

```boxlang
policy = Schedule::exponential( 100 )
	.jittered( 0.8, 1.2 )
	.whileInput( error => error.retryable );
```
`retry` only retries expected failures; defects remain defects. `repeat`
continues after success and returns the final successful value. `timeout` fails
with `{ _tag: "TimeoutError", duration, unit }` and requests interruption for
the losing fiber. Delays use the runtime Clock; the default live Clock delegates
to BoxFuture's native delayed executor.

`spaced( duration )` waits the full duration **after an execution completes**.
`fixed( duration )` targets recurrence start times at a fixed interval. When an
execution overruns its next target, the next iteration begins without an
additional delay; it does not attempt to run missed iterations. Both behaviors
use the runtime Clock, so `TestClock` can prove their timing without wall-clock
waiting.

For deterministic TestBox coverage, supply a `TestClock` when constructing a
runtime and advance it explicitly:

```boxlang
import models.effect.EffectRuntime@bxEffect;
import models.effect.testing.TestClock@bxEffect;

clock = new TestClock();
runtime = new EffectRuntime( { clock: clock } );
fiber = runtime.runFork( Effect::sleep( 5, "seconds" ) );

clock.advance( 5, "seconds" );
fiber.join();
```

`TestClock` is a test-only timing service. It does not replace BoxLang Scheduled
Tasks or create an application scheduler.
