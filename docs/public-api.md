# Public API Inventory

This page is the compatibility boundary for BX Effect `0.1.x`. Import every
public class through the activated module mapping:

```boxlang
import models.effect.Effect@bxeffect;
```

Methods whose names begin with `_`, and every class under
`models.effect.internal`, are runtime implementation details. They can be
reached by BoxLang but may change without compatibility guarantees.

## Effect values and outcomes

| Class and import | Supported surface | Evaluation and failure behavior |
| --- | --- | --- |
| `models.effect.Effect@bxeffect` | Constructors: `succeed`, `fail`, `sync`, `try`, `suspend`, `fromAttempt`, `fromResult`, `service`, `acquireRelease`, `fromBoxFuture`, `all`, `forEach`, `race`, `firstSuccessOf`, `sleep`. Operators: `map`, `flatMap`, `tap`, `tapError`, `tapCause`, `exit`, `zip`, `zipWith`, `as`, `asVoid`, `foldCause`, `catchCause`, `catchAll`, `mapError`, `catchIf`, `catchTag`, `orElse`, `filterOrFail`, `ensuring`, `onExit`, `fork`, `retry`, `repeat`, `timeout`, `provide`, `provideService`. Boundaries: `runSync`, `runSyncExit`, `runFuture`, `runFutureExit`, `runFork`. | Constructors and operators are lazy except validation of invalid options. `fail` is expected failure; thrown user code is a defect; Fiber cancellation is interruption. `catchAll`/`tapError` handle only a pure expected failure. `catchCause`/`tapCause` see the complete Cause. |
| `models.effect.Cause@bxeffect` | `fail`, `die`, `interrupt`, `sequential`, `parallel`; `kind`, `error`, `defect`, `fiberId`, `left`, `right`, `isFailure`, `isDefect`, `isInterrupted`, `failures`, `defects`, `mapFailures`, `pretty`. | Immutable complete failure tree. Cause construction is eager value construction and runs no Effects. |
| `models.effect.Exit@bxeffect` | `success`, `failure`; `isSuccess`, `isFailure`, `value`, `cause`, `match`. | Immutable complete Effect outcome. |
| `models.effect.Result@bxeffect` | `success`, `failure`, `fromAttempt`; `isSuccess`, `isFailure`, `value`, `error`, `map`, `flatMap`, `mapError`, `match`, `toAttempt`. | Immutable pure value with success or expected failure only. It does not represent defects or interruption. |

`Effect::all` and `Effect::forEach` accept `concurrency` and `mode` (`failFast`
or `accumulate`); `forEach` additionally accepts `discard`. Accumulation waits
for all selected branches and retains Causes in input order.

## Runtime, resources, and concurrency

| Class and import | Supported surface | Ownership contract |
| --- | --- | --- |
| `models.effect.EffectRuntime@bxeffect` | Constructor options `executor`, `clock`, `observer`; `runSync`, `runSyncExit`, `runFuture`, `runFutureExit`, `runFork`, `executor`, `clock`. | One root Scope and Layer memo per run. Runtime owns no executor or Clock lifecycle. |
| `models.effect.ManagedRuntime@bxeffect` | `make(layer, options)`; `runSync`, `runSyncExit`, `runFuture`, `runFutureExit`, `runFork`, `close`, `closeFuture`, `isClosed`. | Lazily builds and privately reuses one Layer. `close` interrupts active runs, waits for run finalization, then releases managed services once. Runs after closing starts fail with tagged `ManagedRuntimeClosed`. |
| `models.effect.Scope@bxeffect` | `addFinalizer`, `addRelease`, `addChild`, `interruptChildren`, `close`, `isClosed`. | Advanced explicit Scope primitive. Finalizers are idempotent LIFO entries. Most applications should use `acquireRelease` instead. |
| `models.effect.Fiber@bxeffect` | `await`, `join`, `poll`, `interrupt`, `isDone`, `id`. | Returned by `runFork`/`fork`. Interruption is best effort; `await` preserves an `Exit`, while `join` throws on failure. |
| `models.effect.Deferred@bxeffect` | `make`; `await`, `complete`, `succeed`, `fail`, `die`, `interrupt`, `poll`, `isDone`. | Mutable one-shot coordination value backed by one BoxFuture. Operations are lazy Effects except inspection. |
| `models.effect.Semaphore@bxeffect` | `make`; `acquire`, `release`, `withPermit`, `availablePermits`. | Mutable JDK permit source. Prefer `withPermit` for scoped release. |
| `models.effect.Queue@bxeffect` | `bounded`, `unbounded`; `offer`, `take`, `poll`, `shutdown`, `isShutdown`, `size`. | Mutable application-owned FIFO. Shutdown drains buffered values, then `take`/`offer` fail with tagged `QueueShutdown`. |
| `models.effect.PubSub@bxeffect` | `bounded`, `unbounded`; `publish`, `subscribe`, `withSubscription`, `shutdown`, `isShutdown`, `capacity`, `subscriberCount`. | Mutable application-owned broadcast hub. Bounded publish waits for the slowest active subscriber. |
| `models.effect.PubSubSubscription@bxeffect` | `take`, `poll`, `unsubscribe`, `isShutdown`. | Returned by PubSub. Ownership is explicit; prefer `withSubscription` unless handing ownership to Stream. |

All async boundaries return native BoxLang `BoxFuture` values. BX Effect never
creates or owns an executor pool.

## Context, Layer, time, and recurrence

| Class and import | Supported surface | Contract |
| --- | --- | --- |
| `models.effect.context.ServiceTag@bxeffect` | `of`, `key`, `equals`, `hashCode`, `toString`. | Stable service identity. |
| `models.effect.context.Context@bxeffect` | `empty`, `add`, `get`, `has`, `merge`. | Immutable service map. Missing tags are `bxeffect.context.MissingServiceException` defects with deterministic diagnostics. |
| `models.effect.context.Layer@bxeffect` | `succeed`, `effect`, `scoped`, `merge`; `build`, `provide`. | Ordered service recipe. Builders are lazy; scoped acquisition belongs to the active runtime Scope. |
| `models.effect.Clock@bxeffect` | `now`, `sleep`. | Live runtime Clock. `sleep` returns a native BoxFuture. |
| `models.effect.testing.TestClock@bxeffect` | `sleep`, `advance`, `now`, `pendingCount`. | Published deterministic test support with no TestBox dependency. |
| `models.effect.Schedule@bxeffect` | `recurs`, `spaced`, `fixed`, `exponential`, `and`, `or`, `whileInput`, `untilInput`, `jittered`, `coerce`, `next`. | Immutable retry/repeat decision policy; not cron or BoxLang Scheduler. |

## Streams and observability

| Class and import | Supported surface | Contract |
| --- | --- | --- |
| `models.effect.Stream@bxeffect` | Constructors: `empty`, `succeed`, `fail`, `fromArray`, `fromEffect`, `suspend`, `unfoldEffect`, `acquireRelease`, `fromQueue`, `fromPubSub`. Operators: `map`, `mapEffect`, `filter`, `tap`, `take`, `drop`, `concat`, `flatMap`, `catchAll`, `catchCause`, `ensuring`, `provide`. Consumers: `runCollect`, `runForEach`, `runFold`, `runDrain`. | Immutable reusable description. Every consumer opens a fresh demand-driven cursor and closes it on every exit. End-of-stream is empty native `Attempt`, never failure. |
| `models.effect.observability.LoggingObserver@bxeffect` | `make(loggerOrName, levels)`; `onEvent`. | Optional diagnostic adapter for an existing logger object or named `writeLog` target. It configures and owns nothing; all adapter failures are contained. |

## Compatibility policy before 1.0

BX Effect follows semantic-versioning intent while the package is `0.x`:

- patch releases preserve this inventory and documented semantics;
- a minor `0.x` release may make a necessary breaking correction, which must
  be called out in the changelog and migration notes;
- additions require focused failure-channel, laziness, Context, and cleanup
  tests as applicable; and
- removal, renaming, changed defaults, changed error tags, new eager work, or a
  changed ownership boundary is a compatibility change even when BoxLang types
  still compile.

Before changing public API, update this inventory, the relevant guide and
examples, focused specs, the isolated installed-consumer fixture, package
inspection, and the minimum/latest runtime matrix in the same change.

