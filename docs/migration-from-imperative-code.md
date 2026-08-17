# Incremental Migration

Start at a boundary; an application does not need to be rewritten.

```boxlang
// Before
try {
    return service.fetch( id );
} catch ( any error ) {
    return fallback;
}

// After
return Effect::try(
    try: () => service.fetch( id ),
    catch: error => { _tag: "FetchFailed", cause: error }
).orElse( Effect::succeed( fallback ) );
```

Wrap nullable APIs with native `Attempt` and `Effect::fromAttempt`, manual
try/finally resources with `acquireRelease`, and existing BoxFuture pipelines
with `fromBoxFuture`. Existing BoxLang caches, logging, schedulers, and
executors remain the platform facilities to use.

