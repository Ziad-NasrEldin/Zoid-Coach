#!/usr/bin/env python3

import argparse
import html
import json
import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "docs" / "scenario-registry.json"
DEFAULT_OUTPUT = ROOT / ".lavish" / "zoid-coach-scenario-audit.html"
STATUS_ORDER = [
    "Fully implemented",
    "Touches remaining",
    "Frontend only left",
    "Partially implemented",
    "Barely started",
    "Not implemented",
    "Blocked from verification",
]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--commit", required=True)
    arguments = parser.parse_args()
    output = arguments.output
    if not output.exists():
        raise SystemExit(f"Existing scenario audit template is missing: {output}")
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    scenarios = registry["scenarios"]
    counts = Counter(item["audit_status"] for item in scenarios)
    data = [
        {
            "checked": item["checkbox_state"] == "checked",
            "section": f"{item['section_number']}. {item['section_title']}",
            "scenario": item["wording"],
            "status": item["audit_status"],
            "evidence": item["audit_note"],
        }
        for item in scenarios
    ]
    document = output.read_text(encoding="utf-8")
    document = re.sub(
        r"<h1>.*?</h1>",
        f"<h1>{counts['Fully implemented']} of {len(scenarios)} scenarios are fully usable end to end.</h1>",
        document,
        count=1,
        flags=re.DOTALL,
    )
    lede = (
        f"This tracker is current through authoritative integration tip <code>{html.escape(arguments.commit)}</code>. "
        "Notification delivery now has a privacy-safe local outcome ledger, truthful fallback and scheduling states, "
        "stable replacement evidence, and a direct Settings repair surface. "
        "The signed verifier found an onboarding policy-store blocker and corrected a QA isolation bug, so no notification scenario was overstated as fully implemented."
    )
    document = re.sub(r'<p class="lede">.*?</p>', f'<p class="lede">{lede}</p>', document, count=1, flags=re.DOTALL)
    critical = (
        '<div class="critical"><strong>Notification delivery moved forward without weakening the end-to-end bar.</strong> '
        "Automated evidence proves fallback, delivery, failure, replacement, restart, retention, and redaction. "
        "The signed card rendered, but populated visible acceptance remains a finishing touch after the verifier correctly stopped at an unrelated onboarding persistence failure.</div>"
    )
    document = re.sub(r'<div class="critical">.*?</div>', critical, document, count=1, flags=re.DOTALL)
    metrics = '<div class="metrics">' + "".join(
        f'<button class="metric" data-filter="{html.escape(status)}"><strong>{counts[status]}</strong><span>{html.escape(status)}</span></button>'
        for status in STATUS_ORDER
    ) + "</div>"
    document = re.sub(r'<div class="metrics">.*?</div>', metrics, document, count=1, flags=re.DOTALL)
    serialized = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    document = re.sub(r"const data = .*?;\n", f"const data = {serialized};\n", document, count=1, flags=re.DOTALL)
    document = re.sub(
        r"    const capacityEvidence = .*?    const body = document.getElementById\('rows'\);",
        "    const body = document.getElementById('rows');",
        document,
        count=1,
        flags=re.DOTALL,
    )
    output.write_text(document, encoding="utf-8")


if __name__ == "__main__":
    main()
