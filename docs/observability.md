# Runtime Observability

BX Effect has a small, opt-in observer boundary for runtime diagnostics. It is
disabled by default and does not require a module setting, interceptor, logger,
or telemetry dependency.

Pass an observer function when constructing an `EffectRuntime`:

```boxlang
import models.effect.EffectRuntime@bxeffect;

runtime = new EffectRuntime( {
    observer: ( eventName, details ) => writeLog(
        text: "BX Effect event: #eventName#",
        type: "information"
    )
} );
```

The current event names are:

| Event | Details |
| --- | --- |
| `runtime:started` | Empty details struct |
| `effect:suspended` / `effect:resumed` | `instruction` (`AsyncFuture` or `Sleep`) |
| `fiber:started` | `fiberId` |
| `fiber:completed` / `fiber:interrupted` | `fiberId`, terminal `Exit` |
| `retry:scheduled` | `recurrence`, `delay`, and `unit` |
| `scope:closing` / `scope:closed` | Completed `Exit` |
| `defect:unhandled` | Terminal `Cause` and its defect values |
| `runtime:completed` | Final `Exit` |

For one runtime execution, `runtime:started` occurs first; closing/closed scope
events occur before `runtime:completed`. The observer receives diagnostic
snapshots only. It cannot control scheduling or mutate runtime state.

Fiber terminal events apply to forked execution. `defect:unhandled` is emitted
when a runtime reaches a terminal failure Cause containing a defect; recovery
inside the program prevents the event because no defect reached the boundary.

Observer exceptions are ignored after the normal fatal-throwable policy is
applied. They therefore cannot change an Effect result or prevent finalizers.
This keeps observability diagnostic-only.

## Native logger adapter

`models.effect.observability.LoggingObserver@bxeffect` maps events to either an
existing logger object (`trace`, `debug`, `info`, `warn`, and `error` methods)
or a named BoxLang `writeLog` target. `LoggingObserver::make(target, levels)`
accepts per-event levels plus `"*"` for the default. It configures no appenders
or interceptors and contains formatting/logger failures.

Metrics, interceptor bridges, and OpenTelemetry remain separate opt-in adapter
work rather than module settings or kernel dependencies.
