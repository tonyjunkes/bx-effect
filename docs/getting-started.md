# Getting Started

Install and enable BX Effect as a BoxLang module, then import public classes
from the module mapping:

```boxlang
import models.effect.Effect@bxEffect;
```

Application code should prefer the explicit `@bxEffect` suffix; it avoids
ambiguity when several modules expose similarly named classes. Library code
within BX Effect uses the module's internal mapping instead:

```boxlang
import bxModules.bxEffect.models.effect.Effect;
```

This keeps internal imports distinct from the consumer-facing module-qualified
API.

The module mapping does not create a global `Effect` alias. Import the class in
each source file that uses it; after import, ordinary static calls work as
expected:

```boxlang
program = Effect::succeed( "ready" );
value = Effect::runSync( program );
```

`Effect`, `Cause`, `Exit`, `Result`, `Schedule`, `Context`, and `Layer` are
static/value APIs, not services for WireBox to instantiate. A future WireBox
adapter may explicitly provide `EffectRuntime` or application service Layers,
but the BX Effect kernel does not depend on WireBox.

The repository test suite supplies `tests/boxlang.json`, which points the
runtime at the workspace's parent module directory. Run tests with the command
shown in the README so `@bxEffect` resolution exercises the installed-module
topology rather than a test-only source mapping.

Effects are lazy descriptions. Nothing runs until a runtime boundary:

```boxlang
program = Effect::try(
    try: () => httpClient.get( "/users/42" ),
    catch: error => { _tag: "RequestFailed", message: error.message }
);

exit = Effect::runSyncExit( program );
```

Use `runSync` when a failed program should throw `BXEffect.EffectFailure`. Use
`runSyncExit` when both success and failure should remain values. For an async
boundary, use `runFuture` or `runFutureExit`, both of which return a native
BoxFuture.
