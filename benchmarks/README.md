# Benchmarks

The benchmark scripts are correctness-checked local comparison tools, not CI
timing gates. Each scenario performs one warmup followed by five measured
samples and reports minimum and median elapsed milliseconds using
`java.lang.System.nanoTime()`.

Async and concurrency scenarios also require elapsed time to reach the requested
delay (with 1 ms rounding tolerance). Results from before the live Clock fix are
not valid delay baselines. Use an isolated `BOXLANG_HOME` when an installed copy
of bx-effect would otherwise shadow the checkout's module imports.

Run them from the repository root with the commands listed in `AGENTS.md`, for
example:

```bash
box boxlang cli --bx-config tests/boxlang.json benchmarks/EffectRuntimeBench.bxm
```

For a performance change, run the affected benchmark three times before and
after the change on the same machine and runtime. Retain a change when the
median improves consistently by roughly ten percent, or when it removes a
demonstrable allocation or complexity problem without materially regressing
other scenarios. Record the BoxLang version, Java version, executor override,
and machine context with any published result.

Capture a prebuilt kernel graph with Java Flight Recorder after its warmup:

```bash
box boxlang cli --bx-config tests/boxlang.json benchmarks/EffectRuntimeProfile.bxm --mode=map
box boxlang cli --bx-config tests/boxlang.json benchmarks/EffectRuntimeProfile.bxm --mode=flatMap
```

The recordings are written under the ignored `benchmarks/build/` directory by
default. Use `jfr view hot-methods` and `jfr view allocation-by-class` to inspect
them.

The scripts cover:

- 100,000-node `map` and `flatMap` interpretation;
- Java Flight Recorder profiles for prebuilt `map` and `flatMap` graphs through
  `EffectRuntimeProfile.bxm`;
- delayed async execution and concurrency scaling;
- runtime-local Layer sharing;
- repeated `ManagedRuntime` boundaries with one application Layer build and release;
- 100,000-value Stream mapping, 10,000 repeated pulls, Queue consumption,
  early interruption, and an indicative retained-memory reading;
- Context lookup/provision and Scope finalization.
