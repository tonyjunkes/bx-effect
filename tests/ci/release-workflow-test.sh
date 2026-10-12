#!/usr/bin/env bash
# Exercise the workflow's Bash with real Git history and mocked network commands.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="${1:-$root/.github/workflows/release.yml}"
test_parent="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
test_root="$(mktemp -d "$test_parent/bx-effect-release.XXXXXXXX")"
cleanup() {
  case "$test_root" in "$test_parent"/bx-effect-release.*) rm -rf -- "$test_root" ;; esac
}
trap cleanup EXIT

# These extract this repository's two-space workflow layout, not arbitrary YAML.
# Missing steps or run blocks fail instead of silently testing empty scripts.
step() {
  awk -v name="$1" '
    /^      - name:/ { if (found) exit; found = ($0 == "      - name: " name) }
    found { print }
  ' "$workflow"
}
script() {
  step "$1" | awk '
    /^        run: \|$/ { found = 1; next }
    found && /^          / { print substr($0, 11); count++; next }
    found && NF { exit }
    END { if (!count) exit 1 }
  '
}
script 'Read and validate release version' > "$test_root/decision.sh"
script 'Tag release commit' > "$test_root/tag.sh"
script 'Publish to ForgeBox' > "$test_root/publish.sh"

mkdir "$test_root/bin"
cat > "$test_root/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'release list --limit 1000 --json tagName,isDraft' ]]
[[ "$GH_FAIL" == 0 ]]
printf '%s\n' "$TEST_RELEASES"
MOCK
cat > "$test_root/bin/box" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == 'forgebox show slug=bx-effect --json' ]]; then
  [[ "$FORGEBOX_FAIL" == 0 ]]
  printf '%s\n' "$TEST_FORGEBOX_ENTRY"
else
  [[ "$*" == 'forgebox publish' ]]
  printf '%s\n' "$*" >> "$TEST_PUBLISH_LOG"
fi
MOCK
chmod +x "$test_root/bin/gh" "$test_root/bin/box"
export PATH="$test_root/bin:$PATH"

fixture() {
  mkdir "$test_root/repo-$count"
  cd "$test_root/repo-$count"
  git init --quiet --initial-branch=main
  git config user.name 'Release test'
  git config user.email 'release-test@example.invalid'
  printf '%s\n' '{"version":"1.2.0","slug":"bx-effect"}' > box.json
  printf '%s\n' 'this.version = "1.2.0";' > ModuleConfig.bx
  git add .
  git -c commit.gpgsign=false commit --quiet -m 'Release fixture'
  export GITHUB_SHA="$(git rev-parse HEAD)" GITHUB_REF=refs/heads/main
  git update-ref refs/remotes/origin/main "$GITHUB_SHA"
  export GITHUB_OUTPUT="$PWD/outputs" TAG=1.2.0 VERSION=1.2.0 RUNNER_TEMP="$PWD"
  export TEST_RELEASES='[]' GH_FAIL=0 FORGEBOX_FAIL=0
  export TEST_FORGEBOX_ENTRY='{"versions":[]}' TEST_PUBLISH_LOG="$PWD/publish.log"
  : > "$GITHUB_OUTPUT"
  : > "$TEST_PUBLISH_LOG"
}
decision() { bash -e -o pipefail "$test_root/decision.sh"; }
publish() { bash -e -o pipefail "$test_root/publish.sh"; }
tag_commit() { bash -e -o pipefail "$test_root/tag.sh"; }
tag_fixture() { git -c tag.gpgsign=false tag --annotate 1.2.0 --message 'Release 1.2.0'; }
expect_output() { grep -Fxq "$1" "$GITHUB_OUTPUT"; }
expect_failure() { if "$@"; then echo 'Expected failure, but command succeeded.' >&2; return 1; fi; }

main_trigger() {
  awk '/^on:$/ { found=1; next } found && /^[^ ]/ { exit } found { print }' "$workflow" |
    grep -A2 '^  push:$' | grep -Fxq '      - main'
  grep -Fxq '    needs: tests' "$workflow"
  grep -Fxq '  cancel-in-progress: false' "$workflow"
  [[ -n "$(step 'Verify installed consumer')" ]]
}
publication_guards() {
  local name
  for name in 'Require release credentials' 'Set up CommandBox' 'Tag release commit' 'Publish to ForgeBox' 'Create GitHub release'; do
    step "$name" | grep -Fxq "        if: steps.release.outputs.publish == 'true'"
  done
  awk '/^  publish:$/ { found=1 } found { print }' "$workflow" | grep -Fxq '      contents: write'
  # Tag pushes need checkout credentials; the verification job keeps them disabled.
  ! awk '/^  publish:$/ { found=1 } found { print }' "$workflow" | grep -q 'persist-credentials: false'
  [[ "$(grep -n 'name: Tag release commit' "$workflow" | cut -d: -f1)" -lt "$(grep -n 'name: Publish to ForgeBox' "$workflow" | cut -d: -f1)" ]]
  [[ "$(grep -n 'name: Publish to ForgeBox' "$workflow" | cut -d: -f1)" -lt "$(grep -n 'name: Create GitHub release' "$workflow" | cut -d: -f1)" ]]
}
new_version() { decision; expect_output publish=true; expect_output tag=1.2.0; }
unchanged_version() {
  tag_fixture
  git -c commit.gpgsign=false commit --allow-empty --quiet -m 'Workflow fix'
  export GITHUB_SHA="$(git rev-parse HEAD)"
  git update-ref refs/remotes/origin/main "$GITHUB_SHA"
  decision; expect_output publish=false
}
completed_release() { tag_fixture; export TEST_RELEASES='[{"tagName":"1.2.0","isDraft":false}]'; decision; expect_output publish=false; }
incomplete_release() { tag_fixture; decision; expect_output publish=true; }
draft_release() { tag_fixture; export TEST_RELEASES='[{"tagName":"1.2.0","isDraft":true}]'; decision; expect_output publish=true; }
tag_push_and_retry() {
  git init --quiet --bare "$test_root/remote.git"
  git remote add origin "$test_root/remote.git"
  git push --quiet origin main
  tag_commit; tag_commit
  [[ "$(git --git-dir "$test_root/remote.git" rev-parse '1.2.0^{commit}')" == "$GITHUB_SHA" ]]
  [[ "$(git cat-file -t 1.2.0)" == tag ]]
}
immutable_tag() {
  tag_fixture
  local original="$GITHUB_SHA"
  git -c commit.gpgsign=false commit --allow-empty --quiet -m 'Later commit'
  export GITHUB_SHA="$(git rev-parse HEAD)"
  expect_failure tag_commit
  [[ "$(git rev-parse '1.2.0^{commit}')" == "$original" ]]
}
unrelated_tag() {
  git -c commit.gpgsign=false commit --allow-empty --quiet -m 'Other commit'
  tag_fixture
  git checkout --quiet "$GITHUB_SHA"
  expect_failure decision
}
metadata_mismatch() { printf '%s\n' 'this.version = "1.3.0";' > ModuleConfig.bx; expect_failure decision; }
non_main() { export GITHUB_REF=refs/heads/feature; expect_failure decision; }
github_failure() { tag_fixture; export GH_FAIL=1; expect_failure decision; ! grep -q '^publish=' "$GITHUB_OUTPUT"; }
new_package() { publish; [[ "$(cat "$TEST_PUBLISH_LOG")" == 'forgebox publish' ]]; }
published_package_retry() { export TEST_FORGEBOX_ENTRY='{"versions":[{"version":"1.2.0"}]}'; publish; [[ ! -s "$TEST_PUBLISH_LOG" ]]; }
forgebox_failure() { export FORGEBOX_FAIL=1; expect_failure publish; [[ ! -s "$TEST_PUBLISH_LOG" ]]; }
malformed_forgebox() { export TEST_FORGEBOX_ENTRY='{"error":"unavailable"}'; expect_failure publish; [[ ! -s "$TEST_PUBLISH_LOG" ]]; }

count=0
failures=0
for test in main_trigger publication_guards new_version unchanged_version completed_release incomplete_release draft_release tag_push_and_retry immutable_tag unrelated_tag metadata_mismatch non_main github_failure new_package published_package_retry forgebox_failure malformed_forgebox; do
  ((count+=1))
  # Run outside an `if` so errexit remains active inside every test assertion.
  set +e
  (set -e; fixture; "$test") > "$test_root/result.log" 2>&1
  status=$?
  set -e
  if [[ "$status" == 0 ]]; then
    echo "PASS $test"
  else
    echo "FAIL $test"
    cat "$test_root/result.log"
    ((failures+=1))
  fi
done
echo "$count release checks, $failures failures"
[[ "$failures" == 0 ]]
