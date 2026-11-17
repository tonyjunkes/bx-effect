# Contributing

Use BoxLang 1.18.0+ and Java 21+ for development. Development uses stable TestBox
and pinned Derby/ColdBox dependencies; see [box.json](box.json) for their versions.
These development dependencies are excluded from the production package.

## Prepare and test

Run from the repository root with the selected BoxLang runtime:

```bash
box install
box run-script test:prepare
box run-script test
```

For a standalone BoxLang installation, preparation and tests are:

```bash
boxlang --bx-home .boxlang/compiler --bx-config tests/boxlang.compiler.json tests/PrepareFrameworks.bx
boxlang --bx-home .boxlang/test --bx-config tests/boxlang.json testbox/system/runners/BoxLangRunner.bx --directory=tests.specs --stream --write-report=false --properties-summary=false --stacktrace=short
```

`test:prepare` rebuilds the pinned ColdBox/cbproxies sources using the selected
runtime's native compiler. Their published package contains snapshot-generated
bytecode incompatible with stable 1.19.0. Source checksums, compilation results,
and checkout-local targets are verified before the installed development copy
is replaced. Original dependencies and build output remain under
`.boxlang/framework-build`. Run preparation after installing dependencies or
switching runtime bytecode versions. The compiler home has no framework modules
or CFML compatibility enabled. Applications installing BX Effect need none of
this preparation.

Always retain the isolated `--bx-home .boxlang/test` for checkout specs and
benchmarks. It prevents a globally installed module from shadowing the checkout.
Focused iteration replaces `tests.specs` with a package such as
`tests.specs.async` or `tests.specs.stream`; `--bundles=tests.specs.stream.ConcurrentMapSpec`
selects one bundle. The directory option accepts one package, not a comma list.

Require positive passes, zero failures, and zero errors. The process exit code
alone is insufficient. CI writes JSON and validates those totals. For local JSON
reports, use `--write-report=true --write-json-report=true` and an **absolute**
`--reportpath`; relative paths can resolve under TestBox's own templates.

Run the executor override after runtime/module configuration changes:

```bash
boxlang --bx-home .boxlang/test --bx-config tests/boxlang.executor-override.json testbox/system/runners/BoxLangRunner.bx --directory=tests.specs.module --stream --write-report=false --properties-summary=false --stacktrace=short
```

## Framework and consumer checks

With a matching BoxLang MiniServer on PATH:

```bash
box run-script test:frameworks
```

The native equivalent is:

```bash
boxlang --bx-home .boxlang/framework-runner --bx-config tests/boxlang.json tests/RunFrameworks.bx
```

The runner starts a loopback server, checks HTTP responses, reinitialization and
application shutdown, then stops the process tree. Its reports and server log
are under `.boxlang/framework-integration`. Set `MINISERVER_JAR` to a matching
MiniServer JAR when the launcher is unavailable, or `BX_EFFECT_FRAMEWORK_PORT`
to override port 8951. The normal CLI suite skips HTTP-only cases.

Linux CI covers minimum/latest/snapshot runtimes. A Windows stable-runtime lane
checks module activation, real framework startup/shutdown, and an installed
consumer in a path containing spaces. Release verification also installs a
staged production package into an isolated consumer. See
[the workflows](.github/workflows) and [consumer fixture](tests/consumer/Smoke.bxm).

## Changes and evidence

Trace behavior through callers, the [public inventory](docs/public-api.md), and
the relevant guide/spec. Preserve distinct tests for different failure channels,
ownership boundaries, or cancellation handoffs. Replace assumed race ordering
with bounded rendezvous. A small synthetic test can protect a real guarantee;
extra assertions that repeat another test need no separate case.

For performance work, follow [benchmark instructions](benchmarks/README.md).
Compare repeated samples on the same runtime and machine. Cleanup must preserve
required behavior and near-identical or better performance/efficiency; fewer
lines alone are insufficient evidence. Record actual workload limits and
measurement variation.

Update the inventory, guides and executable examples with public API changes.
Use semantic versioning, with migration notes for actual breaking changes.
Keep `box.json`, `ModuleConfig.bx` and `CHANGELOG.md` aligned, and inspect package
metadata with `box package show`. Main merges run automatic release verification
and publishing; prepare release metadata intentionally.
