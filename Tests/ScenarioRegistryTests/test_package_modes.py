import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Optional


ROOT = Path(__file__).resolve().parents[2]
CONFIGURE = ROOT / "Scripts" / "configure-package-plists.py"
IDENTITIES = ROOT / "App" / "PackageIdentities.plist"
SOURCE_INFO = ROOT / "App" / "Info.plist"
SOURCE_AGENT = ROOT / "App" / "LaunchAgents" / "com.ziadnasreldin.ZoidCoach.agent.plist"


class PackageModeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.info = self.root / "Info.plist"
        self.agent = self.root / "agent.plist"
        self.info.write_bytes(SOURCE_INFO.read_bytes())
        self.agent.write_bytes(SOURCE_AGENT.read_bytes())

    def configure(self, mode: str, qa_run_root: Optional[Path] = None):
        command = [
            str(CONFIGURE),
            "--mode",
            mode,
            "--identities",
            str(IDENTITIES),
            "--info-plist",
            str(self.info),
            "--launch-agent-plist",
            str(self.agent),
        ]
        if qa_run_root is not None:
            command.extend(("--qa-run-root", str(qa_run_root)))
        return subprocess.run(command, capture_output=True, text=True)

    def test_production_transformation_preserves_exact_source_defaults(self):
        expected_info = plistlib.loads(SOURCE_INFO.read_bytes())
        expected_agent = plistlib.loads(SOURCE_AGENT.read_bytes())

        result = self.configure("production")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(plistlib.loads(self.info.read_bytes()), expected_info)
        self.assertEqual(plistlib.loads(self.agent.read_bytes()), expected_agent)

    def test_qa_transformation_has_dedicated_identifiers_and_runtime_root(self):
        qa_run_root = self.root / "qa-runtime"

        result = self.configure("qa", qa_run_root)

        self.assertEqual(result.returncode, 0, result.stderr)
        expected_run_root = str(qa_run_root.resolve(strict=False))
        info = plistlib.loads(self.info.read_bytes())
        agent = plistlib.loads(self.agent.read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], "qa.ziadnasreldin.ZoidCoach")
        self.assertEqual(info["CFBundleExecutable"], "ZoidCoachQA")
        self.assertEqual(info["CFBundleDisplayName"], "Zoid Coach QA")
        self.assertEqual(info["ZoidCoachPackageMode"], "qa")
        self.assertEqual(info["ZoidCoachQARunRoot"], expected_run_root)
        self.assertEqual(
            info["LSEnvironment"]["ZOID_COACH_QA_RUN_ROOT"],
            expected_run_root,
        )
        self.assertEqual(agent["Label"], "qa.ziadnasreldin.ZoidCoach.agent")
        self.assertEqual(agent["BundleProgram"], "Contents/MacOS/ZoidCoachAgentQA")
        self.assertEqual(agent["MachServices"], {"qa.ziadnasreldin.ZoidCoach.agent": True})
        self.assertEqual(
            agent["EnvironmentVariables"]["ZOID_COACH_QA_RUN_ROOT"],
            expected_run_root,
        )
        outputs = self.info.read_text() + self.agent.read_text()
        self.assertNotIn("com.ziadnasreldin.ZoidCoach", outputs)

    def test_qa_transformation_rejects_a_missing_runtime_root(self):
        result = self.configure("qa")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("absolute --qa-run-root", result.stderr)


if __name__ == "__main__":
    unittest.main()
