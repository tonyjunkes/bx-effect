# AGENTS.md

BX Effect is an Effect-inspired BoxLang module (BoxLang 1.18.0+, Java 21+).
Explicit user instructions take precedence; nested AGENTS.md files govern their subtree.

## Sources and boundaries

- For public behavior, use [docs/public-api.md](docs/public-api.md) and the focused guides below. Implementation and focused specs are the executable contract.
- [README.md](README.md), [box.json](box.json), and [.github/workflows](.github/workflows) define setup, package scripts, runtime support, and CI. Verify commands against them.
- [SKILL.md](SKILL.md) is portable guidance for applications using BX Effect; this file governs development of the module itself.
- The module must be installed, registered, and activated. Public code imports `models.effect.Effect@bxeffect`; library peers resolve through `bxModules.bxEffect...`.
- Keep the kernel independent of application lifecycle, WireBox, interceptors, and annotation scanning. Framework integration is explicit application code under `examples/`.
- Reuse native BoxFuture, AsyncService, named executors, Attempt, caching, logging, JDBC, validation, and scheduling. Before adding a low-level facility, check official BoxLang documentation/source for an existing primitive.

## Read for the subsystem being changed

Paths in the implementation column are relative to `models/effect/`.

| Change | Implementation | Contract and focused specs |
| --- | --- | --- |
| Constructors, operators, outcomes | `Effect.bx`, `EffectRuntime.bx`, `Cause.bx`, `Exit.bx`, `Result.bx` | [error-model](docs/error-model.md); `tests/specs/core/` |
| Acquisition, finalizers, local lifetimes | `Scope.bx`, runtime | [resources](docs/resources.md); `tests/specs/resources/`, especially `AcquisitionSpec.bx` |
| Service provisioning, Layer sharing | `context/`, `internal/LayerMemo.bx` | [services-and-layers](docs/services-and-layers.md); `tests/specs/context/` |
| Application-lived services | `ManagedRuntime.bx` | [managed-runtime](docs/managed-runtime.md); `tests/specs/runtime/` |
| Futures, Fibers, coordination | `Fiber.bx`, `Deferred.bx`, `Semaphore.bx`, `Queue.bx`, `PubSub.bx`, `internal/FiberControl.bx` | [concurrency](docs/concurrency.md); `tests/specs/async/`, `tests/specs/stress/` |
| Retry, repeat, timeout, deterministic time | `Schedule.bx`, `Clock.bx`, `testing/TestClock.bx` | [schedules](docs/schedules.md); `tests/specs/schedule/` |
| Stream sources, operators, consumers | `Stream.bx`, `internal/StreamCursor.bx` | [streams](docs/streams.md); `tests/specs/stream/` |
| Runtime diagnostics | runtime, `observability/` | [observability](docs/observability.md); `tests/specs/observability/` |
| Native and framework integration | `examples/` at repository root | [native-integrations](docs/native-integrations.md); `tests/specs/native/`, `tests/specs/frameworks/` |

## Invariants to preserve

- Effects and transformations are lazy; execution starts at a runtime boundary. Keep the instruction graph and interpreter iterative and stack-safe.
- Preserve `Fail`, `Die`, and `Interrupt`, including composite Causes. `catchAll` handles pure expected failures; `catchCause` explicitly handles complete Causes. Use Attempt for absence, Result for expected outcomes, and Exit for complete runtime outcomes.
- Effects, Causes, Exits, Results, Contexts, Layers, and Schedules are immutable values. Restore Context after nested provisioning on every exit. Missing services remain wiring defects with deterministic tag diagnostics.
- Scope stops child admission, interrupts and awaits admitted children, then runs idempotent LIFO cleanup. Acquisition waits stay interruptible; successful acquisition registers release before observing pending interruption. Rejected registration releases immediately. Retain cleanup failures and continue remaining finalizers.
- Layer recipes build in declaration order. Memoization stays private to the owning lifetime and shares in-flight builds across child Fibers; failed builds can retry. Builder closures are not a declared dependency graph.
- ManagedRuntime lazily shares one application Layer and gives each run an isolated Scope. Closing rejects new runs, interrupts and awaits active finalization, then releases managed services once. Keep its Context and memo private.
- Async execution uses native BoxFuture on BoxLang's `io-tasks` virtual-thread executor; `runFuture` stays non-blocking to its caller. Replacing internal waits requires a documented native API and benchmark evidence. Cancellation requests reach both the outer task and active nested future, and native cancellation wrappers remain interruption.
- Worker-thread interruption is registered only around known interruptible Semaphore, Queue, and PubSub instructions and cleared in `finally`. Deferred awaiters use dependent futures so one cancellation cannot cancel the shared result.
- Collections default to fail-fast; explicit accumulation awaits all work and retains Causes in input order. Queue/PubSub ownership and shutdown stay explicit; bounded waits remain interruptible. PubSub subscription lifetime is separate from hub lifetime.
- Each Stream consumer gets a fresh demand-driven cursor, closes it before following work or recovery, and retains an idempotent release fallback during opening. Empty Attempt is completion. Queue sources own no Queue; PubSub sources own only their subscription. Keep operators sequential without implicit read-ahead.
- Timeouts and interruption are cooperative. `spaced` waits after completion; `fixed` targets start times and skips missed intervals. Published `testing/TestClock.bx` stays independent of TestBox; repository fixtures belong under `tests/`.
- Observers are diagnostic-only: failures cannot change outcomes or prevent cleanup. Terminal events report completed/interrupted Fibers; unhandled-defect events describe only defects reaching a runtime boundary.

## BoxLang conventions

- Use tabs and LF in `.bx`/`.bxm` files. Expand `finally` blocks, including single-statement cleanup.
- Imported identifiers are reserved case-insensitively. Prefer `program`, `outcome`, and `failureCause` over locals matching imported classes.
- Custom exception types follow `bxeffect[.<namespace>].<DescriptiveName>Exception`; namespaces describe public areas, not implementation directories. Repository-only types use `testing` or `benchmarks`. Expected error tags retain their names; see [error-model](docs/error-model.md).
- Static semantic APIs such as Effect and Layer are imported values, not WireBox services. Optional adapters explicitly map a runtime or application Layer.
- Keep named `Effect::try( try: ..., catch: ... )` covered on the minimum runtime. If an `Exit` type annotation hits a parser issue, remove only that annotation.
- Function comments describe behavior and arguments; declared return types make `@return` unnecessary.

## Code Review Rules

- Trace changed behavior through callers and the relevant subsystem guide/spec.
  Check whether tests miss a failing path; passing tests alone do not establish correctness.
- For lifetime or concurrency changes, examine acquisition/cancellation handoffs,
  concurrent close or reinit, and finalization ordering against the invariants above.
  Findings should describe the triggering sequence and observable failure.
- For integration, packaging, or workflow changes, follow the consumer path:
  module activation/imports, minimum-runtime APIs, platform-specific launcher
  branches, and automatic release behavior. Check examples as executable code.

## Verification

Run from the repository root after `box install`:

```bash
box run-script test
```

For focused iteration, choose the relevant package from the table above:

```bash
box boxlang cli --bx-home .boxlang/test --bx-config tests/boxlang.json testbox/system/runners/BoxLangRunner.bx --directory=tests.specs.core --stream --write-report=false --properties-summary=false --stacktrace=short
```

- Keep `--bx-home .boxlang/test` for checkout specs/benchmarks so an installed module cannot shadow the checkout. Standalone CLI/CI uses `boxlang` in place of `box boxlang cli`.
- Inspect TestBox totals: require positive passes, zero failures, and zero errors; process exit status alone is insufficient. Both workflows enforce this with JSON reports.
- Before handoff, run the full suite when feasible. For module/runtime settings, also run the executor override:

```bash
box boxlang cli --bx-home .boxlang/test --bx-config tests/boxlang.executor-override.json testbox/system/runners/BoxLangRunner.bx --directory=tests.specs.module --stream --write-report=false --properties-summary=false --stacktrace=short
```

- For ColdBox HTTP changes, run `box run-script test:frameworks`; the normal CLI suite skips these HTTP-only cases. MiniServer setup and reports are documented in [README.md](README.md#contributing--testing).
- For metadata/packaging changes, run `box package show`. Keep version changes aligned in `box.json`, `ModuleConfig.bx`, `CHANGELOG.md`, and the release workflow; runtime support changes also touch README, test configs, and both CI matrices.
- For interpreter/composition changes, run the relevant [benchmarks](benchmarks/README.md). Recorded elapsed time uses imported `java.lang.System.nanoTime()` converted to milliseconds; `getTickCount()` has produced anomalous CLI readings.
- Behavior changes require focused coverage for applicable laziness, failure channels, Context isolation, cancellation, and cleanup contracts. Public API changes also update the inventory, guides, and examples.
- CI tests the minimum runtime, latest, and snapshot, including executor overrides. The release workflow also checks an isolated installed consumer before automatic publishing from `main`.
