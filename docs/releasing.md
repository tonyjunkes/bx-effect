# Releasing BX Effect

1. Update the version in `box.json`, `ModuleConfig.bx`, and `CHANGELOG.md`.
2. Run `box install` to resolve development dependencies.
3. Run the full TestBox command in the README on BoxLang 1.16.0 and the current
   stable BoxLang release. Also run the module-setting override check:

   ```bash
   box boxlang cli --bx-config tests/boxlang.executor-override.json \
     testbox/system/runners/BoxLangRunner.bx --directory=tests.specs.module \
     --stream --write-report=false --properties-summary=false --stacktrace=short
   ```

4. Confirm `box package show` parses the ForgeBox descriptor.
5. Create and push a `v<version>` tag. The `Release` workflow reruns the suite,
   verifies the module-setting override and tag/package version match, and
   publishes with `box publish`.
   Configure its `FORGEBOX_API_TOKEN` repository secret before creating the tag.

`box.json` deliberately uses `location: "forgeboxStorage"`; ForgeBox stores the
published archive, so no artifact URL needs to be edited for a release.

## Compatibility matrix

| Runtime | Local evidence | Required hosted evidence |
| --- | --- | --- |
| BoxLang 1.16.0+ | TestBox suite and package smoke run locally on 1.16.0+57 | `Tests` workflow matrix entry |
| Current BoxLang | Source is compatible by design; no local current-runtime executable is assumed | `Tests` workflow `latest` entry |

BX Effect owns no executor, cache, logger, or application scheduler, so module
unload has no BX Effect-owned infrastructure to shut down.
