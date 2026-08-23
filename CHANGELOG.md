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
- Repeatable warmup/median benchmark reporting and an expanded 132-spec suite.
