# Larger additions: initial survey

Research checked 2026-11-15 against [released Effect 4.1.4](https://github.com/Effect-TS/effect/releases/tag/effect%404.1.4), native BoxLang documentation, and tagged source. This is preparation for later scope/specification decisions; recommendations and effort estimates below are provisional. Current-library improvements retain priority. Selection decisions are recorded separately in the [module review](module-review.md).

Use BoxLang 1.19.0 as the default next-release investigation baseline; older support depends on selected APIs and verification. No sources here establish a performance gain, and no suites or benchmarks were rerun. Package release status does not establish individual module stability: the annotations cited below belong to the exact tagged modules.

## HTTP / Stream bridge

**Workflow and facts:** Stream supplier NDJSON into bounded JDBC batches. Native [HTTP](https://boxlang.ortusbooks.com/boxlang-framework/http-calls) already provides fluent requests, output files, text `onChunk`, and `onBinaryChunk(bytes, info)` documented as new in 1.19.0. BX already supplies [future/Queue coordination](concurrency.md), [pull Streams](streams.md), and [ManagedRuntime](managed-runtime.md). Effect's [HttpClient](https://github.com/Effect-TS/effect/blob/effect%404.1.4/packages/effect/src/http/HttpClient.ts) and [HttpClientResponse](https://github.com/Effect-TS/effect/blob/effect%404.1.4/packages/effect/src/http/HttpClientResponse.ts) are individually **unstable**.

**Recommendation:** Investigate a thin optional native adapter first, retaining native request/header/client models. Potential benefit is one cancellation/resource boundary around transport, decoding, and persistence. Estimated medium effort, high lifecycle risk.

**Unknowns:** Does blocking a callback bound upstream buffering? How does cancellation abort transport? Who owns request/response resources? Define queue capacity, byte/line limits, retry replayability, and failure mapping. Documentation alone proves neither bounded native buffering nor abort behavior; exact 1.19.0 implementation/test checks are prerequisites to a specification.

## Validation / codecs

**Workflow and facts:** Decode, validate, and normalize supplier payloads before persistence. Native [jsonDeserialize](https://boxlang.ortusbooks.com/boxlang-language/reference/built-in-functions/conversion/jsondeserialize) and [isValid](https://boxlang.ortusbooks.com/boxlang-language/reference/built-in-functions/decision/isvalid) supply parsing/value checks; ecosystem [CBValidation](https://forgebox.io/view/cbvalidation) supplies structured constraints. BX has an existing [validation recipe](native-integrations.md#input-validation). Effect's main [Schema](https://github.com/Effect-TS/effect/blob/effect%404.1.4/packages/effect/src/Schema.ts) module is **stable**; advanced symbols need individual stability checks.

**Recommendation:** Explore mapping existing validators into Result/Effect before a general bidirectional codec system. The latter needs demonstrated encode/decode reuse and carries a high general-system maintenance burden; an adapter is smaller.

**Unknowns:** Missing versus null, unknown keys, coercion, numeric precision, dates, recursive shapes, error paths/order, schema versions, and JSON Schema interoperability. Native validation availability does not settle these codec contracts.

## Metrics / tracing

**Workflow and facts:** Diagnose import latency, retries, and cancellation across request/job lifetimes. BX already exposes runtime, Fiber, retry, and Scope [observer events and LoggingObserver](observability.md); native [logging configuration](https://boxlang.ortusbooks.com/getting-started/configuration/logging) owns loggers. The [Java OpenTelemetry SDK](https://opentelemetry.io/docs/languages/java/sdk/) supplies exporters. Effect's [OtlpTracer](https://github.com/Effect-TS/effect/blob/effect%404.1.4/packages/effect/src/observability/OtlpTracer.ts) is **unstable**.

**Recommendation:** Investigate optional observer-to-metrics adapters using existing SDKs/exporters. Estimated low–medium effort for metrics, medium–high for tracing. Existing diagnostic events do not define application spans or `traceparent` propagation; tracing beyond them needs an explicit API proposal.

**Unknowns:** Child-Fiber context propagation, label cardinality, redaction, sampling, bounded export queues/drop policy, flush/shutdown ownership, observer failure containment, and negligible disabled cost. This survey does **not** establish that a native/Ortus telemetry module is absent; check that ecosystem before selecting dependencies.

## Declarative HTTP APIs / client generation

**Workflow and facts:** Share endpoint validation, errors, and documentation between ColdBox servers and clients. [ColdBox routing](https://coldbox.ortusbooks.com/the-basics/routing) owns dispatch; [CBSwagger](https://github.com/coldbox-modules/cbSwagger) generates OpenAPI from configured routes. BX already has [explicit framework integration](native-integrations.md#wirebox-and-coldbox). Effect's [HttpApi](https://github.com/Effect-TS/effect/blob/effect%404.1.4/packages/effect/src/http-api/HttpApi.ts) shares endpoint descriptions across builders/clients/OpenAPI and is **unstable**.

**Recommendation:** Defer until a consumer demonstrates duplicated endpoint definitions and codec demand. First compare consuming existing OpenAPI with introducing another DSL. Estimated high effort, including generator maintenance. An additive optional package need not imply a major release.

**Unknowns:** ColdBox/CBSwagger integration and BoxLang compatibility, codec dependency, authentication, streaming/multipart support, status/error mapping, and ownership of generated clients and regeneration.

## Durable jobs / workflows

**Workflow and facts:** A multi-hour import survives restart or waits for approval. Native [Scheduler plus JDBC](native-integrations.md) is the baseline for calendar execution and an application job table. BX's current scoped execution does not define a persisted replay protocol. Effect's [Workflow](https://github.com/Effect-TS/effect/blob/effect%404.1.4/packages/effect/src/workflow/Workflow.ts), [Activity](https://github.com/Effect-TS/effect/blob/effect%404.1.4/packages/effect/src/workflow/Activity.ts), [WorkflowEngine](https://github.com/Effect-TS/effect/blob/effect%404.1.4/packages/effect/src/workflow/WorkflowEngine.ts), and [ClusterWorkflowEngine](https://github.com/Effect-TS/effect/blob/effect%404.1.4/packages/effect/src/cluster/ClusterWorkflowEngine.ts) are each **unstable**; Activity explicitly supports stored/replayed results.

**Recommendation:** Defer a new engine; separately investigate an external-engine adapter if a real workflow requires it. Estimated very high operational burden.

**Unknowns:** Persisted activity results, stable execution/activity IDs, side-effect delivery and idempotency, crashes between side effects and recording, compensation versus Scope cleanup, version migration, leases, retention, and operator recovery. A JDBC job table is an alternative to compare, not evidence that durable replay is already solved.

## Distributed keyed execution

**Workflow and facts:** Multiple workers own tenant-keyed work. BoxLang 1.19.0's [ScheduledTask.onOneServer](https://github.com/ortus-boxlang/BoxLang/blob/v1.19.0/src/main/java/ortus/boxlang/runtime/async/tasks/ScheduledTask.java#L1031) documents shared-cache mutual exclusion and explicitly says new-node schedule alignment is not implemented. Effect's individually **unstable** [Entity](https://github.com/Effect-TS/effect/blob/effect%404.1.4/packages/effect/src/cluster/Entity.ts) and [SqlMessageStorage](https://github.com/Effect-TS/effect/blob/effect%404.1.4/packages/effect/src/cluster/SqlMessageStorage.ts) add keyed RPC/shard routing and persisted mailboxes; these exceed BX's current in-process [coordination](concurrency.md).

**Recommendation:** Highest maintenance burden; defer without primary consumer demand showing why native locks/job tables are insufficient. Prefer investigating broker/engine adapters.

**Unknowns:** Partitions, fencing, deduplication, ordering, storage/retention, mailbox bounds, authorization, and rolling upgrades. Scheduler locking is a narrower baseline than durable keyed execution.

## Evidence required next

HTTP bridging and adapter metrics are the strongest next **research recommendations**, not approved additions. Every candidate needs a real BoxLang workload, native 1.19 + current-BX comparison, and maintenance justification. Measure throughput, latency, retained memory, allocations, live Fibers, cancellation, and completed cleanup. Performance/efficiency take priority; cleanup must cause no meaningful regression. Avoid new general cache, JDBC, or filesystem platforms for parity. Public breaks may be proposed for 2.0 with affected usage and migration; none are selected here.
