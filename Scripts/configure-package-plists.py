#!/usr/bin/env python3

import argparse
import plistlib
from pathlib import Path


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("production", "qa"), required=True)
    parser.add_argument("--identities", type=Path, required=True)
    parser.add_argument("--info-plist", type=Path, required=True)
    parser.add_argument("--launch-agent-plist", type=Path, required=True)
    parser.add_argument("--qa-run-root", type=Path)
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    identities = plistlib.loads(arguments.identities.read_bytes())
    identity = identities[arguments.mode]
    info = plistlib.loads(arguments.info_plist.read_bytes())
    launch_agent = plistlib.loads(arguments.launch_agent_plist.read_bytes())

    info["CFBundleIdentifier"] = identity["appBundleIdentifier"]
    info["CFBundleExecutable"] = identity["appExecutableName"]
    info["CFBundleDisplayName"] = identity["appDisplayName"]
    info["CFBundleName"] = identity["appDisplayName"]

    launch_agent["Label"] = identity["launchAgentLabel"]
    launch_agent["BundleProgram"] = f"Contents/MacOS/{identity['agentExecutableName']}"
    launch_agent["MachServices"] = {identity["machServiceName"]: True}

    if arguments.mode == "qa":
        if arguments.qa_run_root is None or not arguments.qa_run_root.is_absolute():
            raise SystemExit("QA packaging requires an absolute --qa-run-root")
        qa_run_root = arguments.qa_run_root.resolve(strict=False)
        info["ZoidCoachPackageMode"] = "qa"
        info["ZoidCoachQARunRoot"] = str(qa_run_root)
        info["LSEnvironment"] = {"ZOID_COACH_QA_RUN_ROOT": str(qa_run_root)}
        launch_agent["EnvironmentVariables"] = {
            "ZOID_COACH_QA_RUN_ROOT": str(qa_run_root)
        }
    else:
        info.pop("ZoidCoachPackageMode", None)
        info.pop("ZoidCoachQARunRoot", None)
        info.pop("LSEnvironment", None)
        launch_agent.pop("EnvironmentVariables", None)

    arguments.info_plist.write_bytes(plistlib.dumps(info, sort_keys=False))
    arguments.launch_agent_plist.write_bytes(
        plistlib.dumps(launch_agent, sort_keys=False)
    )


if __name__ == "__main__":
    main()
