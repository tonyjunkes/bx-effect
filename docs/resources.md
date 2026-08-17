# Resource Safety

`acquireRelease` registers an acquired resource in the running Scope. Releases
run exactly once in LIFO order after success, expected failure, defects, or a
timeout/fiber interruption request.

```boxlang
connection = Effect::acquireRelease(
    Effect::sync( () => datasource.getConnection() ),
    db => Effect::sync( () => db.close() )
);
```

Use `ensuring` for an unconditional cleanup Effect and `onExit` when cleanup
needs the complete `Exit`. If cleanup fails, BX Effect retains that failure: it
replaces a prior success or is appended sequentially to the program Cause.

`Layer::scoped` uses the same Scope mechanism for resource-producing services.
Once Scope closure begins, it rejects newly registered finalizers and child
Fibers. This prevents late work from escaping the lifetime that owns its
cleanup.
