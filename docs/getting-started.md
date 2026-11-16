# Getting Started

Install and enable BX Effect as a BoxLang module, then import public classes
from the module mapping:

```boxlang
import models.effect.Effect@bxeffect;
```

The explicit `@bxeffect` suffix avoids ambiguity when several modules expose
similarly named classes. Install with `box install bx-effect` or
`install-bx-module bx-effect`; the selected runtime must register and activate
the module.

The module mapping does not create a global `Effect` alias. Import the class in
each source file that uses it; after import, ordinary static calls work as
expected:

```boxlang
program = Effect::succeed( "ready" );
value = Effect::runSync( program );
```

`Effect`, `Cause`, `Exit`, `Result`, `Schedule`, `Context`, and `Layer` are
static/value APIs, not services for WireBox to instantiate. Applications may
explicitly map a runtime instance and provide container-owned services through
Layers. See the [WireBox and ColdBox recipes](native-integrations.md#wirebox-and-coldbox).

Effects are lazy descriptions. Nothing runs until a runtime boundary:

```boxlang
program = Effect::try(
    try: () => JSONDeserialize( '{"name":"Ada"}' ),
    catch: error => { _tag: "InvalidUserData", message: error.message }
);

outcome = Effect::runSyncExit( program );
if ( outcome.isSuccess() ) {
	println( outcome.value().name ); // Ada
} else {
	println( outcome.cause().pretty() );
}
```

Use `runSync` when a failed program should throw `bxeffect.EffectFailureException`. Use
`runSyncExit` when both success and failure should remain values. For an async
boundary, use `runFuture` or `runFutureExit`, both of which return a native
BoxFuture.

For expected errors from native async work, use `tryBoxFuture`; for bounded
collections, use `forEach(values, mapper, { concurrency: N })`. Streams also
offer explicit concurrent `mapEffect`. Continue with the [error model](error-model.md),
[concurrency](concurrency.md), or [stream guide](streams.md) for complete examples
and ownership details.
