#!/usr/bin/env python3

import argparse
import plistlib
from pathlib import Path

from qa_run_root import canonical_qa_run_root


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
    info["ZoidCoachPackageMode"] = arguments.mode
    info["LSEnvironment"] = {"ZOID_COACH_PACKAGE_MODE": arguments.mode}
    launch_agent["EnvironmentVariables"] = {
        "ZOID_COACH_PACKAGE_MODE": arguments.mode
    }

    if arguments.mode == "qa":
        if arguments.qa_run_root is None:
            raise SystemExit("QA packaging requires an absolute --qa-run-root")
        try:
            qa_run_root = canonical_qa_run_root(arguments.qa_run_root)
        except ValueError as error:
            raise SystemExit(str(error)) from error
        info["ZoidCoachQARunRoot"] = str(qa_run_root)
        info["LSEnvironment"]["ZOID_COACH_QA_RUN_ROOT"] = str(qa_run_root)
        launch_agent["EnvironmentVariables"]["ZOID_COACH_QA_RUN_ROOT"] = str(qa_run_root)
    else:
        info.pop("ZoidCoachQARunRoot", None)

    arguments.info_plist.write_bytes(plistlib.dumps(info, sort_keys=False))
    arguments.launch_agent_plist.write_bytes(
        plistlib.dumps(launch_agent, sort_keys=False)
    )


if __name__ == "__main__":
    main()
