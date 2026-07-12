from pathlib import Path
import re


ROOT = Path(__file__).resolve().parent.parent
TRACKER = ROOT / "docs" / "zoid-coach-product-scenario-tracker.md"

REPORTS = [
    (1, 17, ROOT / ".audit" / "scenarios-01-17.md"),
    (18, 34, ROOT / ".audit" / "scenarios-18-34.md"),
    (35, 50, ROOT / ".audit" / "scenarios-35-50.md"),
    (51, 65, ROOT / ".audit" / "scenarios-51-65.md"),
]

STATUSES = [
    "Fully implemented",
    "Touches remaining",
    "Frontend only left",
    "Partially implemented",
    "Barely started",
    "Not implemented",
    "Blocked from verification",
]


def checkbox_lines(path: Path) -> list[str]:
    return [line for line in path.read_text().splitlines() if re.match(r"^- \[[ x]\] ", line)]


tracker_lines = TRACKER.read_text().splitlines()
current_section = 0
section_by_line: dict[int, int] = {}

for index, line in enumerate(tracker_lines):
    heading = re.match(r"^## (\d+)\.", line)
    if heading:
        current_section = int(heading.group(1))
    section_by_line[index] = current_section

replacement_by_line: dict[int, str] = {}
aggregate = {status: 0 for status in STATUSES}

for start, end, report_path in REPORTS:
    tracker_indexes = [
        index
        for index, line in enumerate(tracker_lines)
        if start <= section_by_line[index] <= end and re.match(r"^- \[ \] ", line)
    ]
    report_items = checkbox_lines(report_path)
    if len(tracker_indexes) != len(report_items):
        raise RuntimeError(
            f"Scenario count mismatch for sections {start}-{end}: "
            f"tracker={len(tracker_indexes)} report={len(report_items)}"
        )

    for tracker_index, report_line in zip(tracker_indexes, report_items):
        scenario = tracker_lines[tracker_index][6:]
        expected_prefixes = (f"- [ ] {scenario}", f"- [x] {scenario}")
        if not report_line.startswith(expected_prefixes):
            raise RuntimeError(
                f"Scenario mismatch in sections {start}-{end}:\n"
                f"tracker: {scenario}\nreport: {report_line}"
            )

        suffix = report_line[len(expected_prefixes[0]) :] if report_line.startswith(expected_prefixes[0]) else report_line[len(expected_prefixes[1]) :]
        status = next((candidate for candidate in STATUSES if candidate in suffix), None)
        if status is None:
            raise RuntimeError(f"Missing approved status: {report_line}")

        evidence = suffix.strip()
        patterns = [
            rf"^-\s*\*\*Status:\s*{re.escape(status)}\.\*\*\s*",
            rf"^-\s*\*\*{re.escape(status)}\.\*\*\s*",
            rf"^-\s*\*\*{re.escape(status)}\*\*:\s*",
            rf"^\*\*Status:\s*{re.escape(status)}\.\*\*\s*",
            rf"^\*\*{re.escape(status)}\.\*\*\s*",
            rf"^\*\*{re.escape(status)}\*\*:\s*",
        ]
        for pattern in patterns:
            updated = re.sub(pattern, "", evidence, count=1)
            if updated != evidence:
                evidence = updated
                break

        evidence = evidence.lstrip(" :-")
        if not evidence:
            raise RuntimeError(f"Missing evidence: {report_line}")

        check = "x" if status == "Fully implemented" else " "
        replacement_by_line[tracker_index] = (
            f"- [{check}] {scenario} **Status: {status}.** {evidence}"
        )
        aggregate[status] += 1

if len(replacement_by_line) != 666:
    raise RuntimeError(f"Expected 666 annotated scenarios, got {len(replacement_by_line)}")

merged_lines = [replacement_by_line.get(index, line) for index, line in enumerate(tracker_lines)]
TRACKER.write_text("\n".join(merged_lines) + "\n")

print("Annotated scenarios:", len(replacement_by_line))
for status in STATUSES:
    print(f"{status}: {aggregate[status]}")
