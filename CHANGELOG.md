# Changelog

All notable changes to BX Effect are documented here.

## 0.1.0 — Unreleased

- Initial BoxLang 1.16+ effect runtime.
- Lazy synchronous and BoxFuture-backed Effects with `Cause` and `Exit`.
- Context, Layers, resource Scopes, Fibers, concurrency, and Schedules.
- TestBox coverage and CI for the minimum supported and current BoxLang runtime.
- Atomic Fiber cancellation and synchronized downstream `TestClock` support.
- Direct iterative `map` interpretation, lazy executor resolution, and reusable
  concurrent completion futures.
- Stack-safe Cause inspection, transformation, and rendering.
- Repeatable warmup/median benchmark reporting and an expanded 181-spec suite.
- A JDK `ArrayDeque` continuation stack that preserves the BoxLang interpreter
  and public API while materially improving deep Map and FlatMap execution.
- Explicit `ManagedRuntime` ownership for one lazily shared application Layer.
- Focused `forEach` accumulation, `tapError`, `tapCause`, `exit`, `zip`, and
  `zipWith` operators.
- Pull-based, resource-safe `Stream` values with Queue and PubSub bridges.
- Native logger observer adapter, installed-consumer verification, public API
  inventory, compatibility policy, and BoxLang integration recipes.
