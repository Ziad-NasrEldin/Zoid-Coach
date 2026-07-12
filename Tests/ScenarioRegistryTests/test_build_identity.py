import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STAMP = ROOT / "Scripts" / "stamp-build-identity.sh"
VERIFY = ROOT / "Scripts" / "verify-build-identity.sh"
SOURCE_PLIST = ROOT / "App" / "Info.plist"


class BuildIdentityTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.repository = Path(self.directory.name) / "repository"
        self.repository.mkdir()
        self.plist = self.repository / "Info.plist"
        self.plist.write_bytes(SOURCE_PLIST.read_bytes())
        subprocess.run(["git", "init", "-q"], cwd=self.repository, check=True)
        subprocess.run(["git", "config", "user.email", "qa@zoid.invalid"], cwd=self.repository, check=True)
        subprocess.run(["git", "config", "user.name", "Zoid QA"], cwd=self.repository, check=True)
        subprocess.run(["git", "add", "Info.plist"], cwd=self.repository, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "fixture"], cwd=self.repository, check=True)
        self.commit = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=self.repository,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def stamp(self, destination: Path):
        return subprocess.run(
            [str(STAMP), str(destination), str(self.repository)],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )

    def identity(self):
        return subprocess.run(
            [str(STAMP), "--print", str(self.repository)],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def test_stamp_reads_clean_identity_from_real_repository(self):
        destination = Path(self.directory.name) / "Stamped.plist"
        destination.write_bytes(SOURCE_PLIST.read_bytes())
        result = self.stamp(destination)

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = plistlib.loads(destination.read_bytes())
        self.assertEqual(payload["ZoidCoachGitCommit"], self.commit)
        self.assertEqual(payload["ZoidCoachGitState"], "clean")
        self.assertEqual(payload["ZoidCoachBuildIdentity"], f"zoid-coach-{self.commit}-clean")

    def test_detector_marks_unstaged_staged_and_untracked_changes_dirty(self):
        self.plist.write_bytes(self.plist.read_bytes() + b"\n")
        self.assertEqual(self.identity(), f"zoid-coach-{self.commit}-dirty")

        subprocess.run(["git", "add", "Info.plist"], cwd=self.repository, check=True)
        self.assertEqual(self.identity(), f"zoid-coach-{self.commit}-dirty")

        subprocess.run(["git", "restore", "--staged", "Info.plist"], cwd=self.repository, check=True)
        subprocess.run(["git", "restore", "Info.plist"], cwd=self.repository, check=True)
        (self.repository / "untracked.txt").write_text("untracked\n")
        self.assertEqual(self.identity(), f"zoid-coach-{self.commit}-dirty")

        (self.repository / "untracked.txt").unlink()
        self.assertEqual(self.identity(), f"zoid-coach-{self.commit}-clean")

    def test_verifier_requires_expected_commit_and_clean_proof(self):
        destination = Path(self.directory.name) / "Stamped.plist"
        destination.write_bytes(SOURCE_PLIST.read_bytes())
        self.assertEqual(self.stamp(destination).returncode, 0)

        accepted = subprocess.run(
            [str(VERIFY), str(destination), "--expected-commit", self.commit, "--require-clean"],
            capture_output=True,
            text=True,
        )
        wrong_commit = subprocess.run(
            [str(VERIFY), str(destination), "--expected-commit", "b" * 40],
            capture_output=True,
            text=True,
        )
        self.assertEqual(accepted.returncode, 0, accepted.stderr)
        self.assertNotEqual(wrong_commit.returncode, 0)

        payload = plistlib.loads(destination.read_bytes())
        payload["ZoidCoachGitState"] = "dirty"
        payload["ZoidCoachBuildIdentity"] = f"zoid-coach-{self.commit}-dirty"
        destination.write_bytes(plistlib.dumps(payload))
        dirty = subprocess.run(
            [str(VERIFY), str(destination), "--expected-commit", self.commit, "--require-clean"],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(dirty.returncode, 0)
        self.assertIn("dirty packages cannot prove scenario completion", dirty.stderr)

    def test_verifier_rejects_incoherent_identity(self):
        destination = Path(self.directory.name) / "Stamped.plist"
        destination.write_bytes(SOURCE_PLIST.read_bytes())
        self.assertEqual(self.stamp(destination).returncode, 0)
        payload = plistlib.loads(destination.read_bytes())
        payload["ZoidCoachBuildIdentity"] = "zoid-coach-" + ("0" * 40) + "-clean"
        destination.write_bytes(plistlib.dumps(payload))

        result = subprocess.run([str(VERIFY), str(destination)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match", result.stderr)


if __name__ == "__main__":
    unittest.main()
