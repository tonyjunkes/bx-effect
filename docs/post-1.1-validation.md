# Post-1.1 validation record

Validated October 12, 2026 against baseline `198b0128e6f044da617966fa7e70b3e93a8300eb`
and implementation `d58b6f76d51b8239eb9cd8ffdfe99f3be47a6d5b`.
Scope: the immediate items in [the extracted roadmap](post-1.1-roadmap.md).

## Correctness and packaging

- Full local TestBox suite: **244 passed, 0 failed, 0 errors** on BoxLang
  **1.16.0** and **1.17.5**. The minimum run writes a JSON report and its totals
  are checked; 1.17.5 uses the canonical `box run-script test`.
- Final implementation CI: minimum **1.16.0**, **latest**, and **snapshot** all
  pass the full-suite JSON gates and executor-override checks.
- Local executor override: **4 passed, 0 failed, 0 errors**. `box package show`
  succeeds. An isolated installed consumer prints `BX_EFFECT_CONSUMER_SMOKE_OK`.
- The six initial demand regressions fail against 1.1.0 with five failed
  assertions and one error. The final suite covers selective map/mapEffect/tap,
  filtering/takeWhile, nested limits, drop/scan/grouping, flatMap, resources,
  Context, recovery, consumer failure, and interruption.
- Seeded stress repeats each scenario twelve times, covering cancellation during
  concurrent acquisition, failed releases, in-flight Layer contention, shuffled
  accumulated completions, and simultaneous bounded Queue/PubSub shutdown.
  Gates and observed native wait states establish ordering without arbitrary sleeps.
- Bounded fatal-rejection regressions exercise four and twelve branches in
  fail-fast and accumulate modes. Both completion strategies retain fatal
  throwable identity and terminate rather than losing an exceptional notification.
- Cooperative timeout tests use TestClock and gates to show that a timeout waits
  for non-cooperative synchronous work and finalizers.
- Workflow YAML parses successfully. Publishing is now tag-triggered and checks
  metadata agreement and main ancestry, without moving tags or forcing publication.
  No package release was performed during this work.

## Benchmark method

Windows 11 Pro, Intel Core i9-11900K, BoxLang 1.17.5, CommandBox-selected Temurin
21.0.12.1, default `io-tasks`, isolated checkout homes/configs. Baseline source
was archived from remote main into an ignored comparison directory. The same
benchmark script runs against both versions.

Each fresh JVM uses one scenario warmup and five samples measured with imported
`System.nanoTime()`. The tables retain three fresh-JVM medians and compare their
median. CollectionRuntimeBench also warms 10,000 native children before its
scenarios. This matters: the baseline sequential forEach warms Fiber machinery,
whereas the inline candidate does not; comparisons without a common child warmup
overstated small-limit regressions. Those preliminary numbers are not used here.

The native checksum loop is a reference for language overhead, not an equivalent
array-producing operator. Immediate concurrent Effects expose bookkeeping cost;
the existing delayed concurrency benchmark separately checks live waiting.
These are local comparisons, not CI timing gates or consumer latency promises.

## Collection measurements

Times are milliseconds. Sequential forEach processes 10,000 values; each all
scenario processes 1,000 immediate Effects with ordered-result assertions.

| Scenario | Baseline JVM medians | Final JVM medians | Median change |
| --- | --- | --- | --- |
| Native checksum loop | 7, 5, 6 | 5, 6, 6 | 6 → 6 |
| Sequential forEach | 3643, 3799, 3725 | 1794, 1769, 1783 | 3725 → 1783; 52.1% lower |
| all, concurrency 1 | 245, 251, 255 | 261, 265, 268 | 251 → 265; 5.6% higher |
| all, concurrency 8 | 152, 157, 156 | 164, 167, 163 | 156 → 164; 5.1% higher |
| all, concurrency 32 | 196, 202, 193 | 158, 155, 152 | 196 → 155; 20.9% lower |
| all, concurrency 128 | 359, 381, 357 | 175, 150, 150 | 359 → 150; 58.2% lower |
| all, unbounded | 1111, 1093, 958 | 159, 152, 142 | 1093 → 152; 86.1% lower |

Retain the inline sequential path and notifications for larger active sets.
Keep the original asyncAny waiting loop at limits up to eight: notifications
did not justify replacing it. Both strategies share ordered outcome assembly
and propagate native rejection, including fatal JVM errors. Small-set changes
stay within the repository's approximate 10% material-regression threshold.

## Stream measurements

The original Stream benchmark runs unchanged against the baseline; the final
script adds a selective-consumption scenario with an exact mapper-count assertion.

| Scenario | Baseline JVM medians | Final JVM medians | Median change |
| --- | --- | --- | --- |
| Map/fold 100,000 values | 282, 290, 273 | 259, 260, 277 | 282 → 260; 7.8% lower |
| 10,000 unfold pulls | 2751, 3152, 2760 | 2820, 2738, 2769 | 2760 → 2769; 0.3% higher |
| 1,000 Queue values | 781, 731, 724 | 724, 717, 735 | 731 → 724; 1.0% lower |
| Interruption | 2, 2, 2 | 2, 2, 2 | unchanged |
| mapEffect.take(1), 100,000 inputs | Not a selective baseline | 73, 73, 81 | One mapper call per run |

Private factories honor demand directly; the cursor does not add another
buffering layer. Full-array pulls reuse the immutable snapshot. Snapshotting
still costs O(input length) at construction; demand avoids unrequested
transformations rather than claiming zero allocation for a large source.
Existing indicative heap readings are not used to infer retained-memory or
allocation improvements. No pooling or Context structural-sharing change is made.

## Other benchmark checks

Correctness assertions pass for EffectRuntimeBench (100,000-node map/flatMap),
ConcurrencyBench (1/8/64/256 delayed branches), and ContextScopeBench.
Representative medians: map 1177 ms, flatMap 5497 ms; delayed concurrency
30/31/60/162 ms with its 20 ms minimum-delay assertions; Context lookup/provision
141/3145 ms and Scope finalization 2597 ms. These are validation samples, not
new comparative allocation or timing claims.

## Standards review

Initial findings: one rejected-child hang and one stale completion-strategy
description. Native success/rejection notification and bounded regressions fix
the hang; the guide now describes the hybrid strategy. Follow-up review of
rejection recovery and simplified private cursors reports **0 open findings**.

## Spec review

Initial finding: stress readiness did not prove actual blocked contention.
Capturing workers and awaiting their known native wait states fixes the gap;
larger branch counts exercise notifications. Follow-up reports **0 open findings**.

Later local scopes, bounded retries, and native integrations remain separate
roadmap work. Public side-effect timing and sequential interpreter-thread changes
are documented in the Stream and concurrency guides.
