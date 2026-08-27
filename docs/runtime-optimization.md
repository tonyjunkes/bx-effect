# Runtime Optimization Decision

Recorded 2026-08-26 for package `0.1.0`. The accepted terminal architecture is
Phase 1 from the Java runtime optimization specification: the BoxLang
interpreter remains authoritative and uses one local JDK `ArrayDeque` for its
continuation stack.

## Environment and baseline

| Field | Value |
| --- | --- |
| Baseline commit | `43d2dfd6746cb1d8711ced5365480085d7341e1a` |
| Baseline worktree | Production sources clean; user-owned `.gitignore` and Java-kernel POC changes present |
| BoxLang | `1.16.0+57` |
| Java | Temurin `21.0.11+10` |
| OS | Windows 11 Pro |
| CPU | Intel Core i9-11900K |
| Module/executor | BX Effect `0.1.0`, `io-tasks` |
| Isolation | Baseline archived from the commit; both candidates ran from isolated BoxLang homes |

The comparison used 100,000 prebuilt instructions. Each fresh JVM performed
one warmup and five timed samples through `BenchmarkSupport`, which measures
with `System.nanoTime()`.

### Raw kernel outputs

Baseline:

```text
iterations=100000 samples=5 directMinMs=21 directMedianMs=26 mapMinMs=4613 mapMedianMs=4797 flatMapMinMs=8556 flatMapMedianMs=8706
iterations=100000 samples=5 directMinMs=20 directMedianMs=26 mapMinMs=4315 mapMedianMs=4427 flatMapMinMs=8477 flatMapMedianMs=8596
iterations=100000 samples=5 directMinMs=20 directMedianMs=30 mapMinMs=4384 mapMedianMs=4453 flatMapMinMs=8471 flatMapMedianMs=8826
```

Phase 1:

```text
iterations=100000 samples=5 directMinMs=21 directMedianMs=27 mapMinMs=1096 mapMedianMs=1149 flatMapMinMs=5140 flatMapMedianMs=5154
iterations=100000 samples=5 directMinMs=22 directMedianMs=26 mapMinMs=1113 mapMedianMs=1162 flatMapMinMs=5029 flatMapMedianMs=5104
iterations=100000 samples=5 directMinMs=21 directMedianMs=25 mapMinMs=1136 mapMedianMs=1152 flatMapMinMs=5059 flatMapMedianMs=5157
```

| Workload | Baseline median of JVM medians | Phase 1 median of JVM medians | Change |
| --- | ---: | ---: | ---: |
| Map | 4,453 ms | 1,152 ms | 74.1% lower, 3.87x faster |
| FlatMap | 8,706 ms | 5,154 ms | 40.8% lower, 1.69x faster |

Both target measurements exceed the specification's 20% material-improvement
threshold.

## Profiling

`benchmarks/EffectRuntimeProfile.bxm` constructs and warms a graph before
capturing three executions with Java Flight Recorder. Its raw recordings were
written to the ignored `benchmarks/java-kernel-poc/build/` directory during the
decision run.

| Workload | Baseline elapsed | Phase 1 elapsed | Baseline leading sample | Phase 1 result |
| --- | ---: | ---: | --- | --- |
| Map | 14,809 ms | 3,933 ms | `Array.remove(int)`, 90.17% | Hotspot absent |
| FlatMap | 27,757 ms | 15,646 ms | `Array.remove(int)`, 71.80% | Hotspot absent |

After the change, FlatMap samples are distributed across BoxLang closure
invocation, dynamic casting, struct access, and map lookup. Allocation samples
are likewise distributed; this change makes no allocation-reduction claim.
`ArrayDeque` represented less than 0.2% of sampled allocation pressure.

## Correctness and regression checks

- The isolated BoxLang 1.16.0 suite passes 181/181 specs across all 17 bundles.
- Focused core, Context, resource, and schedule packages exercise success and
  failure unwinding, Context restoration, finalizer order, retry/repeat, and
  interruption. New tests cover a 10,000-node Map chain and mixed continuation
  frames in exact LIFO order.
- The executor-override module package passes 6/6 specs.
- `box package show` succeeds, and a clean staged installed consumer prints
  `BX_EFFECT_CONSUMER_SMOKE_OK`.
- Async, concurrency, Layer, ManagedRuntime, Context/Scope, and Stream
  benchmarks completed their correctness checks. The affected Context
  provision and Scope medians changed from 3,928/2,822 ms to 3,990/3,023 ms
  (+1.6%/+7.1%). The standalone Context lookup, which does not enter the Effect
  interpreter, varied more than 10% between fresh isolated homes and is not an
  affected-path regression.
- The repository CI remains the authoritative minimum/latest BoxLang matrix;
  only the minimum runtime was available for this local decision run.

## Decision record

| Field | Decision |
| --- | --- |
| Accepted phase | Phase 1: BoxLang interpreter with a per-run JDK `ArrayDeque` continuation stack |
| Baselines | Commit and environment above; exact benchmark output retained in this document; local JFR files remain excluded build artifacts |
| Correctness | 181/181 full suite, focused semantic packages, 6/6 executor override, package inspection, and installed consumer pass on BoxLang 1.16.0 |
| Performance | Map 3.87x faster and FlatMap 1.69x faster by median of three fresh JVM medians |
| Allocation/profile | The 90.17%/71.80% `Array.remove(int)` CPU hotspot disappeared; no broader allocation claim |
| Regressions | No material regression on an affected representative path; Context/Scope stayed within 10% |
| Compatibility | Public API, imports, return types, module settings, and Java 21 baseline unchanged; no production JAR or build step added |
| Maintenance cost | One standard JDK collection import and direct deque operations; the BoxLang interpreter remains the only authoritative path |
| Stop rationale | Phase 1 already exceeds the material goal. Fresh profiles no longer show one dominant control-stack cost, while the Phase 2 POC depends on a prohibited private-scope bridge and lacks complete semantic/package parity |
| Rollback | Restore the continuation stack to a BoxLang Array and map `addLast`/`removeLast`/`isEmpty` back to `append`/`pop`/`len` |

Phase 2 is therefore not accepted or shipped. It remains a separate future
investigation only if representative consumer workloads establish a new
material bottleneck and every Java interoperability and packaging gate can be
met without duplicating interpreter semantics.
