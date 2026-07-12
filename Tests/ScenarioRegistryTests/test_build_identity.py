import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts" / "stamp-build-identity.sh"
SOURCE_PLIST = ROOT / "App" / "Info.plist"


class BuildIdentityTests(unittest.TestCase):
    def run_stamp(self, commit: str, state: str):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        plist = Path(directory.name) / "Info.plist"
        plist.write_bytes(SOURCE_PLIST.read_bytes())
        result = subprocess.run(
            [str(SCRIPT), str(plist)],
            cwd=ROOT,
            env={
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "ZOID_COACH_BUILD_COMMIT": commit,
                "ZOID_COACH_BUILD_STATE": state,
            },
            capture_output=True,
            text=True,
        )
        return result, plist

    def test_stamp_writes_coherent_commit_state_and_identity(self):
        commit = "a" * 40
        result, plist = self.run_stamp(commit, "clean")

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = plistlib.loads(plist.read_bytes())
        self.assertEqual(payload["ZoidCoachGitCommit"], commit)
        self.assertEqual(payload["ZoidCoachGitState"], "clean")
        self.assertEqual(
            payload["ZoidCoachBuildIdentity"],
            f"zoid-coach-{commit}-clean",
        )

    def test_stamp_rejects_malformed_commit_and_state(self):
        bad_commit, _ = self.run_stamp("abc123", "clean")
        bad_state, _ = self.run_stamp("b" * 40, "maybe")

        self.assertNotEqual(bad_commit.returncode, 0)
        self.assertIn("Invalid build commit", bad_commit.stderr)
        self.assertNotEqual(bad_state.returncode, 0)
        self.assertIn("Invalid build state", bad_state.stderr)


if __name__ == "__main__":
    unittest.main()
