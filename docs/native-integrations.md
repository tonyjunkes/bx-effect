# Native BoxLang Integration Recipes

BX Effect adds lazy execution, Cause, Context, Scope, and interruption
semantics around platform facilities. It does not replace BoxLang caches, HTTP,
JDBC, logging, files, or Scheduler.

The [native examples](https://github.com/tonyjunkes/bx-effect/tree/main/examples)
are application code using the public Effect API. They can be copied into an
application; they are not additional module classes or runtime dependencies.

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
import models.effect.Effect@bxeffect;
import models.effect.context.Layer@bxeffect;
import models.effect.context.ServiceTag@bxeffect;

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

loadedUser = Effect::service( CacheProvider ).flatMap( provider ->
	Effect::sync( () => provider.getOrSet(
		"user:#userId#",
		() => loadUser( userId ),
		60
	) )
);
```

For async lookup, use `Effect::fromBoxFuture(() -> provider.getAsync(key))` and
then `Effect::fromAttempt`. `getOrSet` returns the value directly, so it
belongs inside a lazy `sync` with a synchronous native value loader. Native
BoxCache coordinates concurrent loads for a key. Numeric TTLs are in seconds;
`60` is one minute, and `0` makes an entry eternal. Expiration, idle timeout,
eviction, and provider-specific loading behavior remain native policies.
See the [BoxCache provider API](https://boxlang.ortusbooks.com/boxlang-framework/caching/boxcache-provider)
and the [tested loading recipe](https://github.com/tonyjunkes/bx-effect/blob/main/examples/native/CachedLookup.bx).

## Input validation

Use native validators to make an application-specific expected error:

```boxlang
validatedEmail = Effect::suspend( () =>
	isValid( "email", submittedEmail )
		? Effect::succeed( submittedEmail )
		: Effect::fail( { _tag: "InvalidEmail", message: "A valid email is required" } )
);

accepted = validatedEmail.catchTag( "InvalidEmail", error => handleInvalidEmail( error ) );
```

Validation runs at the runtime boundary. A validation failure is an expected
`Fail`; exceptions thrown by subsequent mapping or application code remain
defects. The [user-input recipe](https://github.com/tonyjunkes/bx-effect/blob/main/examples/native/UserValidation.bx)
checks payload shape, required email, and whole-number age using native APIs,
returning `{ _tag: "InvalidUser", errors }` for invalid input. See
[isValid](https://boxlang.ortusbooks.com/boxlang-language/reference/built-in-functions/decision/isvalid).

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

Supply a configured datasource name through Tags and Layers. The native pool
then owns connection management for each operation:

```boxlang
DatabaseName = ServiceTag::of( "app/DatabaseName" );
DatabaseLive = Layer::succeed( DatabaseName, "applicationDB" );

records = Effect::service( DatabaseName ).flatMap( name ->
	Effect::try(
		try: () -> queryExecute(
			"SELECT id FROM records WHERE id = :id",
			{ id: { value: 1, sqltype: "integer" } },
			{ datasource: name }
		),
		catch: error -> { _tag: "DatabaseError", message: error.message }
	)
);
```

Keep a complete native transaction inside one synchronous Effect:

```boxlang
saved = Effect::suspend( () => {
	try {
		transaction datasource="applicationDB" {
			queryExecute( "INSERT INTO records (id) VALUES (:id)",
				{ id: { value: firstId, sqltype: "integer" } }, { datasource: "applicationDB" } );
			queryExecute( "INSERT INTO records (id) VALUES (:id)",
				{ id: { value: secondId, sqltype: "integer" } }, { datasource: "applicationDB" } );
		}
	} catch ( database error ) {
		return Effect::fail( { _tag: "DatabaseError", message: error.message } );
	}
	return Effect::succeed( 2 );
} );
```

The exception leaves the native block before it is mapped, so rollback finishes
before the expected error is returned. The typed catch maps database exceptions;
other thrown values remain defects. See the
[tested write recipe](https://github.com/tonyjunkes/bx-effect/blob/main/examples/native/SaveRecords.bx).

Nested synchronous Effect work can use the surrounding native transaction.
`runSync` throws on failure, which lets the native block roll back.
`runSyncExit` returns a value: when that value is failure, call native
`transactionRollback()` explicitly before leaving the block. Returning an `Exit`
or a failed Effect description by itself does not tell JDBC to roll back.

Async transaction propagation depends on the native BoxLang version. The minimum
runtime shares the caller's transaction context with joined async work; newer
runtimes can give async work a separate connection manager. An async query can
therefore commit independently of the caller's rollback. Do not rely on a Fiber
boundary to either propagate or isolate a transaction. Keep transaction work
sequential within its synchronous native block. For partial rollback,
use an explicit native savepoint; implicit nested-block behavior depends on
native runtime configuration and version.

Effect interruption and timeout are cooperative. Non-cooperative synchronous
transaction work can commit before the interpreter observes its pending
interruption. An interrupted Exit alone therefore does not prove rollback.
Use native query/client deadlines and an explicit transaction failure path when
the operation requires database abort semantics. BX Effect owns no connection
pool or transaction manager. See the
[native transaction guide](https://boxlang.ortusbooks.com/boxlang-framework/jdbc/transactions).

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

