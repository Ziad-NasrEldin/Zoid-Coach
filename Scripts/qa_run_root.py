#!/usr/bin/env python3

import sys
from pathlib import Path


def canonical_qa_run_root(value: Path) -> Path:
    if not value.is_absolute():
        raise ValueError("QA run root must be absolute")
    canonical = value.resolve(strict=False)
    home = Path.home().resolve(strict=False)
    protected = (
        (home / "Library").resolve(strict=False),
        (home / "Library" / "Application Support").resolve(strict=False),
        (home / "screenwatch").resolve(strict=False),
    )
    for production_root in protected:
        if _contains(canonical, production_root) or _contains(production_root, canonical):
            raise ValueError(
                f"QA run root {canonical} overlaps production path {production_root}"
            )
    return canonical


def _contains(candidate: Path, root: Path) -> bool:
    return candidate == root or root in candidate.parents


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: qa_run_root.py <absolute-qa-run-root>")
    try:
        print(canonical_qa_run_root(Path(sys.argv[1])))
    except ValueError as error:
        raise SystemExit(str(error)) from error


if __name__ == "__main__":
    main()
