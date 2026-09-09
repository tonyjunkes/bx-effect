# Native BoxLang Integration Recipes

BX Effect adds lazy execution, Cause, Context, Scope, and interruption
semantics around platform facilities. It does not replace BoxLang caches, HTTP,
JDBC, logging, files, or Scheduler.

## Logging observer

Use the optional adapter with an existing logger object or named BoxLang logger:

```boxlang
import models.effect.EffectRuntime@bxeffect;
import models.effect.observability.LoggingObserver@bxeffect;

runtime = new EffectRuntime( {
	observer : LoggingObserver::make( "application", {
		"defect:unhandled" : "error",
		"retry:scheduled" : "debug"
	} )
} );
```

The adapter configures no logger, appender, encoder, or interceptor and never
throws into the runtime. See BoxLang's [logging configuration](https://boxlang.ortusbooks.com/getting-started/configuration/logging)
for logger ownership.

## BoxCache

Provide the existing `ICacheProvider` as a service and keep native `Attempt`,
TTLs, stores, eviction, async access, and statistics:

```boxlang
CacheProvider = ServiceTag::of( "app/CacheProvider" );
CacheLive = Layer::effect(
	CacheProvider,
	Effect::sync( () => cache( "default" ) )
);

cachedUser = Effect::service( CacheProvider ).flatMap( provider ->
	Effect::fromAttempt(
		provider.get( "user:#userId#" ),
		() -> { _tag: "CacheMiss", key: "user:#userId#" }
	)
);
```

For async lookup, use `Effect::fromBoxFuture(() -> provider.getAsync(key))` and
then `Effect::fromAttempt`. For atomic loading use native `getOrSet`. See the
[BoxCache provider API](https://boxlang.ortusbooks.com/boxlang-framework/caching/boxcache-provider).

## HTTP

Keep request creation lazy by putting `sendAsync()` inside the future factory.
An inherited future `handle` can turn transport completion into `Result`, while
runtime cancellation still remains an interruption request:

```boxlang
request = Effect::fromBoxFuture( () ->
	http( url ).get().sendAsync().handle( ( response, transportError ) ->
		isNull( transportError )
			? Result::success( response )
			: Result::failure( {
				_tag : "HttpTransportError",
				message : transportError.getMessage()
			} )
	)
).flatMap( result -> Effect::fromResult( result ) )
	.flatMap( response -> response.statusCode >= 200 && response.statusCode < 300
		? Effect::succeed( response )
		: Effect::fail( {
			_tag : "HttpStatusError",
			status : response.statusCode
		} )
	);
```

Cancellation is best effort through the active dependent future; the native
client decides whether an in-flight network request can be stopped. BX Effect
adds no request, response, header, or middleware hierarchy. See BoxLang's
[HTTP client guide](https://boxlang.ortusbooks.com/boxlang-framework/http-calls).

## JDBC and transactions

Provide datasource/query services with Tags and Layers, parameterize through
native JDBC functions, and map database exceptions at the edge:

```boxlang
QueryService = ServiceTag::of( "app/QueryService" );
QueryLive = Layer::succeed( QueryService, {
	run : ( sql, params = {} ) => queryExecute( sql, params )
} );

users = Effect::service( QueryService ).flatMap( queries ->
	Effect::try(
		try: () -> queries.run(
			"select * from users where active = :active",
			{ active: { value: true, sqltype: "boolean" } }
		),
		catch: error -> { _tag: "DatabaseError", message: error.message }
	)
);
```

Until an application verifies transaction context across its configured
executor, wrap a native transaction block in one synchronous `Effect::try` and
do not fork inside it. BX Effect does not own a pool or transaction manager.

## Scheduled tasks

Let BoxLang Scheduler own calendar recurrence. A task callback should execute
one explicit runtime boundary and record its Exit:

```boxlang
scheduler.task( "refresh-search-index" )
	.call( () => {
		var taskExit = application.effectRuntime.runSyncExit( refreshIndex() );
		if ( taskExit.isFailure() ) {
			logger.error( taskExit.cause().pretty() );
		}
		return taskExit;
	} )
	.every( 15, "minutes" );
```

Use BX Effect `Schedule` only for retry/repeat inside one run. See BoxLang's
[Scheduled Tasks guide](https://boxlang.ortusbooks.com/boxlang-framework/asynchronous-programming/scheduled-tasks).

## Files

Use `acquireRelease` for a handle and keep native file operations:

```boxlang
contents = Effect::acquireRelease(
	Effect::try(
		try: () -> fileOpen( path, "read" ),
		catch: error -> { _tag: "FileOpenError", message: error.message }
	),
	handle -> Effect::sync( () -> fileClose( handle ) )
).flatMap( handle -> Effect::sync( () -> fileRead( handle ) ) );
```

For many values, build a `Stream::acquireRelease` source around the handle so
early termination closes it. BX Effect adds no filesystem or path service.

