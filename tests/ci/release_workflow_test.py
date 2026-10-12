"""Exercise release decisions against real Git history without publishing packages."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = yaml.load((ROOT / ".github/workflows/release.yml").read_text(), Loader=yaml.BaseLoader)
BASH = os.environ.get("TEST_BASH", "bash")


class ReleaseWorkflowTest(unittest.TestCase):
    def test_main_merge_runs_release_after_verification(self):
        self.assertIn("main", WORKFLOW["on"].get("push", {}).get("branches", []),
                      "Merging main must trigger the Release workflow without a manual tag")
        self.assertEqual(WORKFLOW["jobs"]["publish"]["needs"], "tests")
        steps = WORKFLOW["jobs"]["tests"]["steps"]
        self.assertTrue(any(step["name"] == "Verify installed consumer" for step in steps))
        self.assertEqual(WORKFLOW["concurrency"]["cancel-in-progress"], "false")

    def test_publishing_and_tagging_are_guarded_by_version_decision(self):
        job = WORKFLOW["jobs"]["publish"]
        self.assertEqual(job["permissions"]["contents"], "write")
        names = [step["name"] for step in job["steps"]]
        self.assertLess(names.index("Tag release commit"), names.index("Publish to ForgeBox"))
        self.assertLess(names.index("Publish to ForgeBox"), names.index("Create GitHub release"))
        for step in job["steps"]:
            if step["name"] in ("Require release credentials", "Set up CommandBox",
                                "Tag release commit", "Publish to ForgeBox", "Create GitHub release"):
                self.assertEqual(step.get("if"), "steps.release.outputs.publish == 'true'")
        checkout = job["steps"][0]
        self.assertNotEqual(checkout["with"].get("persist-credentials"), "false")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bx-effect-release-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.run_command("git", "init", "--quiet", "--initial-branch=main", str(self.directory))
        self.run_command("git", "config", "user.name", "Release test")
        self.run_command("git", "config", "user.email", "release-test@example.invalid")
        (self.directory / "box.json").write_text('{"version":"1.2.0"}\n')
        (self.directory / "ModuleConfig.bx").write_text('this.version = "1.2.0";\n')
        self.run_command("git", "add", ".")
        self.run_command("git", "commit", "--quiet", "-m", "Release fixture")
        self.sha = self.run_command("git", "rev-parse", "HEAD").stdout.strip()
        self.run_command("git", "update-ref", "refs/remotes/origin/main", self.sha)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        # Mock only GitHub's network response; all Git version/tag checks are real.
        stub = self.bin / "gh"
        stub.write_text('#!/usr/bin/env bash\nset -euo pipefail\n'
                        '[[ "$*" == "release list --limit 1000 --json tagName,isDraft" ]]\n'
                        '[[ "${GH_FAIL:-0}" == 0 ]] || exit 1\n'
                        'printf "%s\\n" "$TEST_RELEASES"\n', newline="\n")
        stub.chmod(0o755)

    def run_command(self, *args):
        return subprocess.run(args, cwd=getattr(self, "directory", ROOT), text=True,
                              capture_output=True, check=True)

    def decision(self, releases=(), ref="refs/heads/main", github_failure=False):
        step = next(step for step in WORKFLOW["jobs"]["publish"]["steps"]
                    if step.get("id") == "release")
        output = self.directory / "outputs"
        output.write_text("")
        script = self.directory / "decision.sh"
        script.write_text(step["run"], newline="\n")
        env = dict(os.environ, GITHUB_REF=ref, GITHUB_SHA=self.sha,
                   GITHUB_REF_NAME=ref.split("/")[-1], GITHUB_OUTPUT=output.as_posix(),
                   TEST_RELEASES=json.dumps(list(releases)), GH_FAIL=str(int(github_failure)))
        # Git Bash converts this Windows PATH into POSIX paths at startup.
        env["PATH"] = str(self.bin) + os.pathsep + env["PATH"]
        result = subprocess.run([BASH, "-e", "-o", "pipefail", script.as_posix()],
                                cwd=self.directory, env=env, capture_output=True, text=True)
        values = dict(line.split("=", 1) for line in output.read_text().splitlines())
        return result, values

    def test_new_version_is_released_without_existing_tag(self):
        result, values = self.decision()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(values["publish"], "true")
        self.assertEqual(values["tag"], "1.2.0")

    def test_ordinary_main_commit_skips_previous_version(self):
        self.run_command("git", "tag", "1.2.0")
        self.run_command("git", "commit", "--allow-empty", "--quiet", "-m", "Workflow fix")
        self.sha = self.run_command("git", "rev-parse", "HEAD").stdout.strip()
        self.run_command("git", "update-ref", "refs/remotes/origin/main", self.sha)
        result, values = self.decision()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(values["publish"], "false")

    def test_completed_release_is_not_republished(self):
        self.run_command("git", "tag", "-a", "1.2.0", "-m", "Release 1.2.0")
        result, values = self.decision([{"tagName": "1.2.0", "isDraft": False}])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(values["publish"], "false")

    def test_incomplete_release_at_same_commit_can_retry(self):
        self.run_command("git", "tag", "-a", "1.2.0", "-m", "Release 1.2.0")
        result, values = self.decision()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(values["publish"], "true")

    def test_draft_release_at_same_commit_can_finish(self):
        self.run_command("git", "tag", "1.2.0")
        result, values = self.decision([{"tagName": "1.2.0", "isDraft": True}])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(values["publish"], "true")

    def test_tag_step_pushes_tested_commit_and_can_retry(self):
        remote = self.directory / "remote.git"
        self.run_command("git", "init", "--quiet", "--bare", str(remote))
        self.run_command("git", "remote", "add", "origin", str(remote))
        self.run_command("git", "push", "--quiet", "origin", "main")
        step = next(step for step in WORKFLOW["jobs"]["publish"]["steps"]
                    if step["name"] == "Tag release commit")
        script = self.directory / "tag.sh"
        script.write_text(step["run"], newline="\n")
        env = dict(os.environ, TAG="1.2.0", GITHUB_SHA=self.sha)
        for _ in range(2):
            result = subprocess.run([BASH, "-e", "-o", "pipefail", script.as_posix()],
                                    cwd=self.directory, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        actual = self.run_command("git", "--git-dir", str(remote), "rev-parse", "1.2.0^{commit}")
        self.assertEqual(actual.stdout.strip(), self.sha)
        self.assertEqual(self.run_command("git", "cat-file", "-t", "1.2.0").stdout.strip(), "tag")

    def test_tag_step_never_moves_existing_tag(self):
        self.run_command("git", "tag", "1.2.0")
        original = self.sha
        self.run_command("git", "commit", "--allow-empty", "--quiet", "-m", "Later commit")
        step = next(step for step in WORKFLOW["jobs"]["publish"]["steps"]
                    if step["name"] == "Tag release commit")
        script = self.directory / "tag.sh"
        script.write_text(step["run"], newline="\n")
        env = dict(os.environ, TAG="1.2.0",
                   GITHUB_SHA=self.run_command("git", "rev-parse", "HEAD").stdout.strip())
        result = subprocess.run([BASH, "-e", "-o", "pipefail", script.as_posix()],
                                cwd=self.directory, env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.run_command("git", "rev-parse", "1.2.0^{commit}").stdout.strip(), original)

    def test_unrelated_version_tag_is_rejected(self):
        self.run_command("git", "commit", "--allow-empty", "--quiet", "-m", "Other commit")
        self.run_command("git", "tag", "1.2.0")
        self.run_command("git", "checkout", "--quiet", self.sha)
        result, _ = self.decision()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not an ancestor", result.stderr)

    def test_metadata_mismatch_is_rejected(self):
        (self.directory / "ModuleConfig.bx").write_text('this.version = "1.3.0";\n')
        result, _ = self.decision()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match", result.stderr)

    def test_non_main_dispatch_is_rejected(self):
        result, _ = self.decision(ref="refs/heads/feature")
        self.assertNotEqual(result.returncode, 0)

    def test_github_failure_does_not_allow_republication(self):
        self.run_command("git", "tag", "1.2.0")
        result, values = self.decision(github_failure=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("publish", values)


if __name__ == "__main__":
    unittest.main(verbosity=2)
