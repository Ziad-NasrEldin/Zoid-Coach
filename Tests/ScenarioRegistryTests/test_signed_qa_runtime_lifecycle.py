import subprocess
import shlex
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LIBRARY = ROOT / "Scripts/lib/signed-qa-runtime-lifecycle.sh"
INSTALLER = ROOT / "Scripts/install-signed-qa-runtime.sh"
REGISTRATION_PROBE = ROOT / "Sources/ZoidCoachApp/PolicyMutationXPCProbe.swift"


class SignedQARuntimeLifecycleTests(unittest.TestCase):
    def run_zsh(self, script: str, cwd: Path) -> None:
        subprocess.run(
            [
                "zsh",
                "-c",
                f"set -euo pipefail; source {shlex.quote(str(LIBRARY))}; {script}",
            ],
            cwd=cwd,
            check=True,
            text=True,
            capture_output=True,
        )

    def test_installer_recovers_only_delayed_exact_helper_readiness(self) -> None:
        result = subprocess.run(
            [str(INSTALLER), "--self-test"],
            cwd=ROOT,
            check=True,
            text=True,
            capture_output=True,
        )

        self.assertIn("PASS: signed QA installer readiness self-tests", result.stdout)
        self.assertIn("command_status=5", result.stderr)

    def test_app_replacement_changes_the_bundled_helper_path_atomically(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            installed = root / "Zoid 666 QA E2E.app"
            staged = root / ".installing.app"
            backup = root / ".previous.app"
            old_helper = installed / "Contents/MacOS/ZoidCoachAgentQA"
            new_helper = staged / "Contents/MacOS/ZoidCoachAgentQA-v2"
            old_helper.parent.mkdir(parents=True)
            new_helper.parent.mkdir(parents=True)
            old_helper.write_text("old")
            new_helper.write_text("new")

            self.run_zsh(
                f"qa_commit_app_replacement {str(installed)!r} {str(staged)!r} {str(backup)!r}",
                root,
            )

            self.assertFalse(old_helper.exists())
            self.assertEqual(
                (installed / "Contents/MacOS/ZoidCoachAgentQA-v2").read_text(),
                "new",
            )
            self.assertEqual(
                (backup / "Contents/MacOS/ZoidCoachAgentQA").read_text(),
                "old",
            )

    def test_interrupted_replacement_restores_the_previous_app(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            installed = root / "installed.app"
            staged = root / "staged.app"
            backup = root / "backup.app"
            staged.mkdir()
            backup.mkdir()
            (backup / "marker").write_text("previous")

            self.run_zsh(
                f"qa_recover_interrupted_replacement {str(installed)!r} {str(staged)!r} {str(backup)!r}",
                root,
            )

            self.assertEqual((installed / "marker").read_text(), "previous")
            self.assertFalse(staged.exists())
            self.assertFalse(backup.exists())

    def test_uninstall_invokes_only_the_installed_qa_app_lifecycle_command(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            installed = root / "qa.app"
            executable = installed / "Contents/MacOS/ZoidCoachQA"
            log = root / "calls.log"
            executable.parent.mkdir(parents=True)
            executable.write_text(
                f"#!/bin/zsh\n# --qa-unregister-agent\nprint -r -- \"$1\" >> {str(log)!r}\n"
            )
            executable.chmod(0o755)

            self.run_zsh(
                f"qa_unregister_installed_agent {str(installed)!r} ZoidCoachQA",
                root,
            )

            self.assertEqual(log.read_text().strip(), "--qa-unregister-agent")

    def test_uninstall_skips_an_older_app_without_the_lifecycle_command(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            installed = root / "qa.app"
            executable = installed / "Contents/MacOS/ZoidCoachQA"
            log = root / "calls.log"
            executable.parent.mkdir(parents=True)
            executable.write_text(f"#!/bin/zsh\nprint invoked >> {str(log)!r}\n")
            executable.chmod(0o755)

            self.run_zsh(
                f"qa_unregister_installed_agent {str(installed)!r} ZoidCoachQA",
                root,
            )

            self.assertFalse(log.exists())

    def test_install_acceptance_requires_writable_xpc_prompt_timeline_and_heartbeat(self) -> None:
        installer = INSTALLER.read_text()
        probe = REGISTRATION_PROBE.read_text()

        self.assertIn(
            "PASS: QA XPC runtime is writable and prompt timeline is available",
            installer,
        )
        self.assertIn("processing_checkpoints", installer)
        self.assertIn("source_id = 'agent-runtime'", installer)
        self.assertLess(
            installer.index("--qa-register-agent"),
            installer.index('open "$INSTALLED_APP"'),
        )
        self.assertIn("fetchRuntimeSafety", probe)
        self.assertIn("fetchPromptInboxTimeline", probe)
        self.assertIn("readAgentHeartbeat", probe)


if __name__ == "__main__":
    unittest.main()
