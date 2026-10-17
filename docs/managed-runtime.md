# Managed Runtime

Use `ManagedRuntime` when an application Layer owns services that should be
built once and shared across many requests or jobs, such as a thread-safe
application client or datasource name. Ordinary `EffectRuntime` remains the right
boundary when each run should acquire and release everything independently.

```boxlang
import models.effect.Effect@bxeffect;
import models.effect.ManagedRuntime@bxeffect;
import models.effect.context.Layer@bxeffect;
import models.effect.context.ServiceTag@bxeffect;

DatabaseName = ServiceTag::of( "app/DatabaseName" );
// Configure this datasource through native BoxLang application settings.
ApplicationLive = Layer::succeed( DatabaseName, "applicationDB" );

runtime = ManagedRuntime::make( ApplicationLive );
try {
	value = runtime.runSync(
        Effect::service( DatabaseName ).flatMap( name => Effect::try(
            try: () => queryExecute(
                "SELECT id FROM records WHERE id = :id",
                { id: { value: 1, sqltype: "integer" } },
                { datasource: name }
            ),
            catch: error => { _tag: "DatabaseError", message: error.message }
        ) )
	);
} finally {
	closeExit = runtime.close();
}
```

Construction is lazy: the Layer starts on the first run. Concurrent first runs
share one build, and later runs reuse its private Context. A failed build closes
partial acquisitions and a later run retries. Each run still owns a separate
Scope, so request-local `acquireRelease`, finalizers, and child Fibers finish
without closing application services.

ManagedRuntime does not make a supplied service thread-safe. Share a native
datasource name or application-owned thread-safe pool/client, and acquire a
connection for the operation that uses it. One JDBC connection retained across
concurrent requests would share mutable transaction state. Native datasource
configuration and pool ownership remain with BoxLang; see the
[transaction recipe](native-integrations.md#jdbc-and-transactions).

## Closing

`close()` returns an `Exit`; `closeFuture()` returns a native BoxFuture of that
Exit. Once closing begins, new runs do not execute user work and fail with the
tagged expected error `ManagedRuntimeClosed`. Close requests interruption of
active runs, waits for their Scope cleanup, then releases managed Layer
resources once in LIFO order. Concurrent close calls share one completion.
Failed cleanup from runs interrupted by close is retained before managed-service
cleanup in the closing Exit. Completed runs already removed before close keep
their own outcomes; close does not replay their business errors.
The observer sees `scope:closing`, `scope:closed`, then `runtime:completed` for
the managed close outcome; observer failures remain diagnostic-only.

Interruption is still best effort for arbitrary code. If user code ignores
interruption, close waits rather than releasing a service that code may still
use.

## Application lifecycle recipe

Keep ownership explicit in `Application.bx`; BX Effect does not install a
global runtime or lifecycle interceptor:

```boxlang
function onApplicationStart() {
    var cacheTag = ServiceTag::of( "app/Cache" );
    application.effectRuntime = ManagedRuntime::make(
        Layer::effect( cacheTag, Effect::sync( () => cache( "default" ) ) )
    );
	return true;
}

function onApplicationEnd( applicationScope ) {
	var closeExit = arguments.applicationScope.effectRuntime.close();
	if ( closeExit.isFailure() ) {
		writeLog(
			text: closeExit.cause().pretty(),
			type: "Error",
			log: "application"
		);
	}
}
```

Do not place the managed Context or Layer memo in application scope. Store only
the runtime instance so its state and services remain encapsulated.

Build request programs in the request that will run them. The complete
[Application.bx](https://github.com/tonyjunkes/bx-effect/blob/main/examples/application/Application.bx)
and [request example](https://github.com/tonyjunkes/bx-effect/blob/main/examples/application/Index.bxm)
show native startup, repeated requests, logging observation, and application-end
cleanup. The native cache provider is supplied as an externally owned service;
closing the ManagedRuntime finalizes its work without shutting that provider down.

For WireBox-owned services, the [framework recipes](native-integrations.md#wirebox-and-coldbox)
map one runtime explicitly and close it before injector or ColdBox service teardown,
including reinitialization. The framework owns the supplied service instances.
