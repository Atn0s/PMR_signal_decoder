#!/usr/bin/env python3
"""CLI bridge used by MATLAB to call the current Python decoder."""
from __future__ import annotations

import argparse
import os
import sys


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run Python scanner.py and write JSON.")
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--json", required=True)
    parser.add_argument("--protocol", action="append", default=None)
    parser.add_argument("--fo", type=float, action="append", default=None)
    parser.add_argument("--sample-rate", type=float, default=None)
    parser.add_argument("--blind-search", action="store_true")
    parser.add_argument("--iq-dtype", default="int16")
    parser.add_argument("--no-dedup", dest="deduplicate", action="store_false")
    parser.set_defaults(deduplicate=True)
    args = parser.parse_args(argv)

    root = os.path.abspath(args.project_root)
    if not os.path.isdir(root):
        raise SystemExit(f"Python project root not found: {root}")
    sys.path.insert(0, root)
    os.chdir(root)

    import scanner  # pylint: disable=import-error,import-outside-toplevel

    scanner.scan_file(
        args.target,
        freq_list=args.fo,
        output_json=args.json,
        protocol_names=args.protocol,
        sample_rate=args.sample_rate,
        blind_search=args.blind_search,
        iq_dtype=args.iq_dtype,
        deduplicate=args.deduplicate,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
