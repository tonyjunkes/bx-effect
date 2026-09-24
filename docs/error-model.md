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

`Effect::fromExit(outcome)` lifts either Exit branch losslessly.
`Effect::failCause(failureCause)` re-emits a complete Cause from `catchCause`
without rebuilding it. `Effect::die(defect)` explicitly describes a defect.
`catchTags({ NotFound: handler, Unavailable: handler })` copies its handler
table at construction and invokes only the matching expected-error handler
at execution. Keys use BoxLang's native case-insensitive struct lookup.
Unmatched errors, defects, and interruption keep their channels.

Native `Attempt` remains the right type for presence/absence. Convert it with
`Effect::fromAttempt( value, onEmpty )`; do not use it to model defect detail.

`runFuture` applies the same boundary rule as `runSync`: it completes its native
BoxFuture successfully for an Effect success and exceptionally for an Effect
failure. As with every BoxFuture, `get()` exposes BoxLang's native execution
wrapper; its underlying failure is `bxeffect.EffectFailureException` and retains the
rendered Cause. Use `runFutureExit` when a future should always resolve to an
`Exit` instead.

## Missing services

Resolving an unprovided `ServiceTag` is a defect, not an expected error. The
`bxeffect.context.MissingServiceException` detail contains `requestedTag` and sorted
`availableTags` values so callers can diagnose incorrect Context/Layer wiring.

ServiceTag equality and hashing use native BoxLang keys, matching Context
lookup (including case-insensitive names and integer-key normalization).
`key()` preserves the supplied spelling for diagnostics.

## Exception naming

Library-thrown custom exception types use
`bxeffect[.<namespace>].<DescriptiveName>Exception`: lowercase library and
namespace segments, followed by a PascalCase name ending in `Exception`.
Namespaces describe stable public areas rather than mirroring every directory.

| Area | Examples |
| --- | --- |
| Core and shared exceptions | `bxeffect.InvalidDeferredOutcomeException`, `bxeffect.EffectFailureException`, `bxeffect.ScopeClosedException` |
| Invalid messages | `bxeffect.InvalidQueueValueException`, `bxeffect.InvalidPubSubValueException` for null writes, raised lazily as defects |
| Context and service tags | `bxeffect.context.MissingServiceException`, `bxeffect.context.InvalidServiceTagException` |
| Observability | `bxeffect.observability.InvalidLoggingObserverLevelException`, `bxeffect.observability.InvalidLoggingObserverTargetException` |

Implementation directories such as `models`, `effect`, and `internal` do not
appear in exception types. Shared validation types remain at the root:
`bxeffect.InvalidDurationException` and `bxeffect.InvalidTimeUnitException`
also apply when thrown by the published `TestClock`.

These are BoxLang custom exception type strings. Expected error values and
their tags, including `QueueShutdown`, `PubSubShutdown`, and
`SubscriptionShutdown`, retain their names and failure-channel semantics.
Application-provided exception types are preserved as supplied.

Code migrating from the previous naming convention must update typed catches
and exception-type comparisons: append `Exception`, lowercase the library
prefix to `bxeffect`, and add `context` for `MissingService`/`InvalidServiceTag`
or `observability` for `InvalidLoggingObserverLevel`/`InvalidLoggingObserverTarget`.
The old names are not aliases. Messages, details, and Cause channels are unchanged.
