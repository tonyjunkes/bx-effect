# Module review

This document records the scope and decisions from the module review interview.
The interview and execution sequence were confirmed before implementation.
The agreed contracts below are the review specification; outcomes and verification
belong in [the module audit](module-audit.md).

## Confirmed decisions

- **Feature selection:** Compare current stable Effect with concrete BoxLang
  workflows and native capabilities. Each addition needs a practical benefit and
  a maintenance justification. See [ADR 0001](adr/0001-native-first-feature-selection.md).
- **Compatibility:** The audit may recommend public breaking changes for a 2.0
  release. Each proposal must identify affected usage, the benefit, and a migration
  path. No specific breaking change or next module version has been selected.
- **BoxLang baseline:** Use BoxLang 1.19.0 as the default development and
  verification baseline for the next release. Favor beneficial current native
  capabilities rather than preserving an older minimum at their expense. A wider
  support range is welcome when the APIs used and compatibility verification
  justify it; the next release's minimum is not yet decided.
- **TestBox:** Update the declared development dependency to the latest stable
  release and verify the suite against it during implementation.
- **Cleanup:** Review code by its observable purpose, callers, contracts, and
  measured justification. Include over-engineering, unnecessary work, duplicated
  paths, and abstractions that can be simplified while preserving the required
  result. Generated provenance alone is not a reason to remove code.
- **Performance and efficiency:** These take priority over reducing code.
  Simplification needs case-by-case evidence of near-identical or better
  performance and efficiency while meeting the required behavior. A meaningful
  regression is not an acceptable cleanup trade-off. Use both representative
  workloads and affected focused benchmarks; a noisy measurement or fewer lines
  alone establishes nothing. If existing behavior is wrong, assess the required
  behavior explicitly rather than preserving it merely for equivalence.
- **Tests:** Retain tests for meaningful regressions, including synthetic cases
  that protect real guarantees. Consolidate redundant coverage and improve weak
  assertions or unreliable concurrency timing. No line-count, deletion-count, or
  test-count target applies.
- **Acceptance workflows:** Prioritize bounded HTTP/API batches with retries,
  deadlines, partial failures, and cancellation; then large file/data pipelines
  with bounded memory, backpressure, and cleanup; then application-lived services
  shared across requests/jobs with dependency isolation and orderly shutdown.
- **Larger additions:** Prioritize the existing composition, errors, resources,
  concurrency, streams, and native integration areas for this pass. Also perform
  initial research identifying larger additions and their native alternatives,
  use cases, and unresolved decisions so follow-up specifications can be prepared.
  Larger subsystems require separate scope decisions before implementation.
  See the [initial larger-additions survey](larger-additions-survey.md) for cited
  alternatives, provisional recommendations, and unresolved questions.
- **Shortlisted features:** Include a lazy expected-async-error constructor and
  explicit bounded concurrent stream mapping. Their behavioral contracts are
  agreed below; API shape and implementation must follow the existing conventions
  and verification evidence. Preserve ordinary `fromBoxFuture` rejection behavior
  and default sequential stream semantics; reproducing and correcting a violation
  of the documented cancellation invariant is part of the audit.
- **Platform verification:** Test Linux and Windows where their differences
  matter. Linux retains broad runtime-matrix coverage. Windows checks should
  target native launcher, path/import/installation, and process shutdown behavior;
  expand to broader suites when an affected path or finding justifies it. A
  duplicate full operating-system/runtime matrix is not a goal by itself.

## Agreed feature contracts

### Expected async errors

- Construction is lazy. Each execution invokes the supplied native future factory.
- Ordinary exceptions from the factory and ordinary future rejections pass through
  the application error mapper and become expected failures.
- Mapper exceptions and invalid factory returns are defects, not expected errors.
- Cancellation, including native cancellation wrappers, remains interruption and
  cannot become a retryable expected failure. Fatal platform conditions bypass
  application error mapping under the runtime's fatal-throwable policy.
- Follow `Effect.try` and native BoxFuture conventions when choosing names,
  arguments, mapper input, and validation. Verify wrapper behavior on each claimed
  runtime; avoid arbitrary traversal that strips meaningful application failures.
- Cover successful and rejected futures, laziness and reruns, factory/mapper
  throws, invalid returns, requested/external/already-cancelled futures, native
  fatal wrappers, Context, and cleanup as applicable.

### Bounded concurrent stream mapping

- Preserve input order by default, with explicit completion-order output available
  for independent work. Ordered emission can wait behind a slow earlier item.
- Bound total started-but-not-delivered mappings, including completed waiting
  results. Start with a total window of `N` for concurrency `N` and benchmark it;
  a larger configurable window requires demonstrated benefit.
- Start mapping on consumer demand. An explicit concurrent mapping followed by
  `take(1)` may start several mappings within its window. Existing sequential
  operators retain their current demand behavior.
- On failure or early termination, stop admission and interrupt and await admitted
  work before the consumer returns or following work/recovery starts. Close the
  source and retain cleanup failures under existing Cause and Scope contracts.
- Fail fast by default. Applications can return `Result` values to continue past
  recoverable per-item errors. Do not add an implicit accumulation policy or imply
  rollback of external side effects.
- Verify ordered/completion-order delivery, the total admission bound behind a
  stalled item, demand and early termination, source and mapper failures,
  Context isolation, interruption, and exactly-once awaited cleanup. Measure
  representative I/O throughput and retained memory as well as interpreter cost.

See [ADR 0002](adr/0002-bounded-concurrent-stream-admission.md) for the explicit
trade-off between delivery order, admission, and memory.

## Feature evidence and deferred candidates

The first two candidates have agreed behavioral contracts above. Named composition
and further investigations are not selected. The first three are confirmed public
API gaps, although existing BoxLang/BX Effect constructs can express the workflows
today.

- **Expected async errors:** The HTTP recipe currently composes a native future
  handler, Result, and `fromResult` around `fromBoxFuture`. Investigate a small
  lazy constructor for async expected errors that preserves cancellation as
  interruption, maps ordinary factory failures, keeps mapper failures as defects,
  and keeps ordinary
  `fromBoxFuture` semantics unchanged. Upstream comparison:
  [Effect.tryPromise](https://github.com/Effect-TS/effect/blob/effect%404.1.4/packages/effect/src/Effect.ts).
- **Bounded concurrent stream mapping:** `mapEffect` is currently sequential.
  Grouping followed by bounded `Effect.forEach` is possible but introduces batch
  barriers. Investigate an explicit concurrent operator with bounded in-flight
  work and defined ordering, demand, failure, and cleanup behavior. Existing
  sequential operators promise no implicit read-ahead. Upstream comparison:
  [Stream.mapEffect](https://github.com/Effect-TS/effect/blob/effect%404.1.4/packages/effect/src/Stream.ts).
- **Named composition:** Accumulating named intermediate results currently needs
  nested `flatMap` calls or application helpers. Consider a thin record-based
  sequencing convenience only if repeated examples demonstrate a material
  readability benefit without meaningful performance cost. Upstream comparison:
  [Effect.bind](https://github.com/Effect-TS/effect/blob/effect%404.1.4/packages/effect/src/Effect.ts).
- **Further investigation:** Effect-aware caching, dynamically keyed scoped
  resource sharing, and named operation diagnostics have possible use cases, but
  native async cache capabilities, resource ownership, and diagnostic context
  propagation need more comparison before recommending new public abstractions.

## Initial audit leads

These are review hypotheses, not confirmed defects or approved changes. The
exploration did not rerun suites or benchmarks.

- **Concurrent collection strategies:** `EffectRuntime.awaitAll` and
  `awaitSmallAll` repeat admission and completion orchestration, switching at
  concurrency eight. Comments describe a measured benefit, but no checked-in
  comparison supporting this split or threshold was located. Compare candidate
  simplifications using the [collection benchmark](../benchmarks/CollectionRuntimeBench.bxm),
  including threshold-adjacent widths and delayed work. Preserve ordered
  outcomes, bounded admission, cancellation, fatal throwable handling, and
  awaited cleanup. The measured deque change in
  [runtime-optimization.md](runtime-optimization.md) is a separate decision.
- **Lifecycle protocol duplication:** Runtime, Scope, and ManagedRuntime repeat
  parts of interrupt/await/cleanup collection. Their ownership responsibilities
  differ. Consider a small shared helper only if it makes those responsibilities
  clearer; do not replace them with a generic lifecycle framework merely to
  remove similar loops.
- **Internal API boundary:** Instruction constructors and Fiber termination and
  cleanup hooks have live cross-class callers despite not belonging to the
  supported public inventory. Verify native visibility options before proposing
  encapsulation changes; these methods have not been established as dead code.
- **Test synchronization:** `tests/resources/AsyncTestSupport.bx` uses
  `getTickCount()` deadlines despite documented anomalous CLI readings elsewhere.
  Some race specifications assume ordering from different sleep durations, and
  some cleanup assertions poll after a completion boundary. Review monotonic
  deadlines, explicit rendezvous, and direct assertions where the boundary
  already promises completed cleanup. Preserve distinct semantic scenarios.
- **External future cancellation:** Source inspection shows async exception
  normalization recognizes interruption from the Fiber control flag, with no
  separate native cancellation classification. An already-cancelled or externally
  cancelled future without that flag appears to become a defect. Reproduce this
  path and compare it with the cancellation invariant before designing the new
  expected-error constructor; cancellation must not accidentally become retryable
  application failure. Existing rejected-future and requested-cancellation behavior
  have coverage, but no focused external-cancellation case was located.
- **Native acceptance coverage:** Dedicated native specs cover cache,
  validation, JDBC, and application lifecycle behavior. No dedicated native
  HTTP-client, Scheduler-callback, or file-recipe spec was found in
  `tests/specs/native`. The ColdBox HTTP suite exercises server integration,
  which does not establish client-recipe coverage. Evaluate these missing
  acceptance scenarios against the selected workflow priorities.

## Decision tree

- Feature admission and cleanup standards: settled above.
  - Representative application workflows and their priority: settled above.
  - Larger subsystems: initial research requested; implementation requires
    separate scope decisions.
  - Expected async errors and bounded concurrent stream mapping: selected with
    behavioral contracts and acceptance scenarios above.
  - Other candidates: recorded for investigation; additions require separate
    practical justification and scope decisions.
- Breaking-change proposals: permitted for consideration.
  - Actual breaks, migration work, and release version: determined from findings
    using the existing compatibility policy; do not choose a major in advance.
- Latest-native-runtime preference: settled above.
  - Exact supported range: determined by selected APIs and compatibility
    verification; current baseline preference does not predetermine the minimum.
- Evidence-based code and test review: settled above.
  - Performance trade-offs: settled above; individual changes require evidence.
  - Operating-system coverage: risk-based Linux and Windows checks agreed above.
  - Execution sequence and completion gates: confirmed below.

## Confirmed execution sequence

1. Establish reproducible correctness and affected performance baselines for the
   unchanged implementation on BoxLang 1.19.0 and latest stable TestBox. Update
   the declared development dependency and distinguish runtime-version gains
   from gains caused by implementation changes.
2. Audit all production classes and their callers, guides, examples, and relevant
   tests. Start with async/error/resource handoffs and collection orchestration;
   include packaging and native/framework consumer paths. Record concrete
   triggering sequences, redundant guarantees, and real simplification candidates.
   The initial leads above do not limit this review or establish defects.
3. Apply justified correctness, efficiency, code, and test improvements in
   separable changes. Strengthen deterministic synchronization and native
   acceptance coverage where it demonstrates a real contract. Compare affected
   benchmarks before and after on the same runtime and machine; retain specialized
   paths when removing them imposes meaningful performance or efficiency costs.
4. Implement the two selected features against the agreed contracts, using native
   BoxLang primitives and the existing iterative interpreter/Scope model. Keep
   sequential fast paths intact. Update the public inventory, relevant guides,
   examples, and focused behavioral coverage together.
5. Run the full suite with positive passes and zero failures/errors, executor
   overrides, applicable real native/framework acceptance checks, package
   inspection, and an isolated installed consumer. Verify platform-specific
   Windows paths as justified; Linux runtime-matrix verification remains required.
   Run affected benchmarks with repeated comparable samples and record results.
6. Select the supported BoxLang range and module version from the actual API and
   compatibility results. Align package/config/changelog/release metadata, record
   migration notes for any actual public breaks, and hand off the changes with
   findings, verification results, and any material limits. The larger-additions
   survey remains a separate input to future specifications.

The audit may conclude that a component or test is already justified and should
remain. Findings that require a new product decision return to the interview;
routine implementation choices follow the agreed contracts and repository rules.

Implementation follows the confirmed interview. Research findings remain hypotheses until their triggering paths,
observable effects, and supporting evidence have been checked.
