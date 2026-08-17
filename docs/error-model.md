# Expected Errors, Defects, and Exit

`Effect::fail( error )` creates an expected, recoverable domain failure.
`Effect::try()` maps an ordinary exception into that same channel. Exceptions
from `sync`, mappers, handlers, or async futures become defects instead.

```boxlang
program = Effect::fail( { _tag: "UserNotFound", id: userId } )
    .catchTag( "UserNotFound", error => Effect::succeed( anonymousUser ) );
```

`catchAll` handles only expected failures. Use `catchCause` when deliberately
handling a full failure tree. `Cause` preserves `Fail`, `Die`, `Interrupt`, and
sequential/parallel composition. `Cause::mapFailures( mapper )` transforms
only expected errors and preserves the original defect/interruption tree.
`Exit` is either a success value or a Cause.

Native `Attempt` remains the right type for presence/absence. Convert it with
`Effect::fromAttempt( value, onEmpty )`; do not use it to model defect detail.

`runFuture` applies the same boundary rule as `runSync`: it completes its native
BoxFuture successfully for an Effect success and exceptionally for an Effect
failure. As with every BoxFuture, `get()` exposes BoxLang's native execution
wrapper; its underlying failure is `BXEffect.EffectFailure` and retains the
rendered Cause. Use `runFutureExit` when a future should always resolve to an
`Exit` instead.

## Missing services

Resolving an unprovided `ServiceTag` is a defect, not an expected error. The
`BXEffect.MissingService` detail contains `requestedTag` and sorted
`availableTags` values so callers can diagnose incorrect Context/Layer wiring.
