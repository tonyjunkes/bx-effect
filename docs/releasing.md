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
5. Install the repository package into a clean `boxlang_modules` directory and
   run `tests/consumer/Smoke.bxm` with `tests/consumer/boxlang.json`. The normal
   test mapping is not acceptable evidence for this check.
6. Record the verified BoxLang and Java versions with the release candidate.

ForgeBox publishing is intentionally deferred. The `Release` workflow remains
disabled and `box.json` has no publication location. Before enabling it, review
the tag/version check, choose the ForgeBox storage location, configure
`FORGEBOX_API_TOKEN`, and repeat every check above. Pushing a tag today does not
publish the module.

## Compatibility matrix

| Runtime | Local evidence | Required hosted evidence |
| --- | --- | --- |
| BoxLang 1.16.0+ | TestBox suite and package smoke run locally on 1.16.0+57 | `Tests` workflow matrix entry |
| Current BoxLang | Source is compatible by design; no local current-runtime executable is assumed | `Tests` workflow `latest` entry |

BX Effect owns no executor, cache, logger, or application scheduler, so module
unload has no BX Effect-owned infrastructure to shut down.
