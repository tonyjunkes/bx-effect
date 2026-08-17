# Services and Layers

Use a `ServiceTag` as the stable identity for a service and provide concrete
values with a `Context` or a `Layer`.

```boxlang
Database = ServiceTag::of( "app/Database" );

DatabaseLive = Layer::effect(
    Database,
    Effect::sync( () => datasource.getConnection() )
);

query = Effect::service( Database )
    .map( db => db.query( "select 1" ) )
    .provide( DatabaseLive );
```

Contexts are immutable by contract: provisioning copies the service map and
restores the surrounding context across success and failure. `Layer.merge`
builds in declaration order, so a later Layer can consume an earlier service.

Within one root runtime execution, providing the same `Layer` instance more
than once reuses its built Context. Concurrent child Fibers share one in-flight
build as well: the first builder publishes its completed Context to the other
waiters. A successful build remains memoized through root Scope closure; a
failed build is delivered to current waiters and removed so a later provision
can retry. Shared scoped acquisition and release therefore happen once at the
owning root Scope. Separate Layer instances and independent runtime executions
remain independent; this is not a process-wide service cache.

A missing service is a defect (`BXEffect.MissingService`), because it indicates
an unprovided application dependency. Its error detail includes the requested
tag and a sorted list of tags available in that Context, which makes wiring
mistakes diagnosable without inventing a Layer dependency graph.

`Layer.merge` is intentionally an ordered recipe, not a declared dependency
graph: later Layers can consume services from earlier ones. BX Effect does not
attempt to infer dependency cycles from arbitrary builder closures. Graph
diagnostics require an explicit future Layer-dependency API.
