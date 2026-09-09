# Managed Runtime

Use `ManagedRuntime` when an application Layer owns services that should be
built once and shared across many requests or jobs, such as an application
client or connection-like resource. Ordinary `EffectRuntime` remains the right
boundary when each run should acquire and release everything independently.

```boxlang
import models.effect.Effect@bxeffect;
import models.effect.ManagedRuntime@bxeffect;
import models.effect.context.Layer@bxeffect;
import models.effect.context.ServiceTag@bxeffect;

Database = ServiceTag::of( "app/Database" );
ApplicationLive = Layer::scoped(
	Database,
	Effect::acquireRelease(
		Effect::sync( () => datasource.getConnection() ),
		connection -> Effect::sync( () => connection.close() )
	)
);

runtime = ManagedRuntime::make( ApplicationLive );
try {
	value = runtime.runSync(
		Effect::service( Database ).flatMap(
			connection -> Effect::sync( () => connection.query( "select 1" ) )
		)
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

## Closing

`close()` returns an `Exit`; `closeFuture()` returns a native BoxFuture of that
Exit. Once closing begins, new runs do not execute user work and fail with the
tagged expected error `ManagedRuntimeClosed`. Close requests interruption of
active runs, waits for their Scope cleanup, then releases managed Layer
resources once in LIFO order. Concurrent close calls share one completion.
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
	application.effectRuntime = ManagedRuntime::make( buildApplicationLayer() );
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
