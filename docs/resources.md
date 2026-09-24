# Resource Safety

`acquireRelease` registers an acquired resource in the running Scope. Releases
run exactly once in LIFO order after success, expected failure, defects, or a
timeout/fiber interruption request.

A successful acquisition installs its release before the runtime observes a
pending interruption. Acquisition waits remain interruptible. Wrap the actual
resource-producing Effect with `acquireRelease` before adding user `map` or
`flatMap` work, so cleanup already owns the resource if that work fails. If a
closing Scope rejects registration, the runtime releases the resource immediately
and retains any cleanup failure alongside the registration defect.

```boxlang
connection = Effect::acquireRelease(
    Effect::sync( () => datasource.getConnection() ),
    db => Effect::sync( () => db.close() )
);
```

Use `ensuring` for an unconditional cleanup Effect and `onExit` when cleanup
needs the complete `Exit`. If cleanup fails, BX Effect retains that failure: it
replaces a prior success or is appended sequentially to the program Cause.

Use `Effect::acquireUseRelease(acquire, use, release)` for a shorter lifetime,
such as one connection per batch item. Release runs before the following Effect
or outer recovery, rather than waiting for the root Scope to end. Its callback
receives `(resource, useExit)`; failed acquisition never calls use or release.
The acquisition handoff and cleanup failure rules above also apply here.

```boxlang
saved = Effect::acquireUseRelease(
    Effect::sync( () => datasource.getConnection() ),
    db => saveBatch( db ),
    ( db, useExit ) => Effect::sync( () => db.close() )
);
```

Races, fail-fast collections, and root shutdown retain terminal child cleanup
failures. Cleanup can turn a winning success into failure, or append to the
primary Cause. Ordinary losing business errors and interruption alone are not
added to the winner. Explicit recovery inside a child, or around the aggregate
Effect, handles that cleanup failure normally without adding it again at shutdown.

`Layer::scoped` uses the same Scope mechanism for resource-producing services.
At a root boundary, the runtime first stops child-Fiber admission, interrupts
and awaits every admitted child, and then begins Scope cleanup. Once cleanup
begins, the Scope rejects newly registered finalizers and child Fibers. This
prevents late work from escaping the lifetime that owns its cleanup or using a
resource after its release.
