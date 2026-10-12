# BX Effect: Post-1.1 Review and Development Roadmap

Working specification extracted from the [shared conversation](https://chatgpt.com/share/6accf255-4d70-83e9-8b19-d2c3f4184a09)
and its [linked full review](https://chatgpt.com/s/t_6acc6750da6c819191ae5dcf7aace431).
The review inspected 1.1.0 source but did not run TestBox or benchmarks. Treat
performance concerns as hypotheses until measured locally. Claims about other
projects' release versions are background, not implementation requirements.

## Immediate implementation scope

1. **Stream demand.** `fromArray(...).mapEffect(...).take(1)` must execute the
   mapper once. Cover map, tap, filter, takeWhile, early interruption, resource
   sources, Context, recovery, and wrapper composition. Preserve fresh cursors,
   snapshots, native Attempt/array batches, all Cause channels, and early cleanup.
   Do not add concurrent operators or change Queue/PubSub ownership. Document
   changed side-effect timing for applications relying on eager batch mapping.
2. **Sequential collections.** Measure 10,000 sequential operations against a
   native loop. Try advancing Effects in the iterative interpreter without a
   child Fiber per item. Keep only a reproducible improvement preserving output
   order, lazy mapper invocation, fail-fast/accumulated failures, Context
   restoration, interruption, resource registration, and finalization.
3. **Concurrent collections.** Profile limits 1, 8, 32, 128, and unbounded.
   Investigate operation-local completion notification through native BoxFuture
   callbacks instead of repeatedly rebuilding asyncAny inputs and running arrays.
   Implement only with measured benefit and unchanged cancellation/loser cleanup.
4. **Cooperative timeouts.** Document that a timed-out operation must terminate
   and clean up before its timeout returns. Test non-cooperative user code with
   deterministic gates and TestClock; recommend native client deadlines for I/O.
5. **Quality gates.** Add pinned BoxLang 1.16.0 compatibility alongside latest
   and snapshot. Strengthen repeated concurrency coverage for cancellation during
   acquisition, simultaneous shutdown, Layer build contention, failed finalizers,
   and bounded Queue/PubSub contention without timing-dependent sleeps.
6. **Release workflow.** Verify PRs and every main update. Publish only from an
   explicit version tag matching package and module metadata on main. Preserve
   immutable tags, installed-consumer verification, and TestBox JSON checks;
   remove forced publication.

## Subsequent phases

- Prototype local lifetimes: `Effect::scoped(program)`, scoped child Fiber
  ownership, scope-aware registration, interruption and cleanup before following
  work. Establish ownership semantics before publishing these APIs.
- Add bounded retry ergonomics, proposed as `Schedule::exponential(250)
  .maxDelay(10000).and(Schedule::recurs(5))`. Investigate total elapsed budgets
  separately; account for slow work and cleanup.
- Publish application-owned ManagedRuntime lifecycle recipes. Investigate native
  JDBC transaction propagation, rollback, nested Effects, interruption and async
  boundaries before exposing a transaction adapter. Prefer a single synchronous
  native transaction if that is the safe boundary.
- Demonstrate BoxCache getOrSet/TTL, native isValid or CBValidation expected
  errors, optional WireBox/ColdBox mapping, and observer/logger integration with
  representative examples and integration tests before adding library wrappers.
- Investigate inherited diagnostic metadata only if normal Context provisioning
  is insufficient. Defer richer Stream operators, service composition and request
  batching until demonstrated application needs justify them.

## Architecture and measurement constraints

Keep the iterative ArrayDeque interpreter, native BoxFuture/virtual-thread
execution, distinct Cause/Exit/Result/Attempt responsibilities, Context restoration,
runtime-local Layer memoization, native synchronization, independent TestClock,
and diagnostic-only observers. Avoid a scheduler, schema engine, synthetic
generator DSL, cache, HTTP/JDBC framework or heuristic Layer dependency scanning.

Use warmed measurements and correctness assertions. Compare direct operations,
native loops, native bounded async work, selective Stream consumption, deep
flatMap, native try/finally and repeated ManagedRuntime runs. Use monotonic
System.nanoTime and existing JFR support. Profile finalizer and Context allocation
before pooling or structural sharing; preserve cleanup isolation.

The proposed sequence is investigation/fixes, Stream and measured collection
refinement, local scopes/bounded retries, optional native integrations, then
future features only when justified. This first PR implements the immediate
scope above; subsequent phases remain separate design and implementation work.
