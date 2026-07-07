#!/usr/bin/env python3
"""Generate Python baseline JSON files for MATLAB regression tests."""
from __future__ import annotations

import argparse
import os
import sys


SAMPLES = (
    ("dmr_1_78125", "data/dmr_1_78125.rawiq", ("dmr",), None, False),
    ("dmr_2_78125", "data/dmr_2_78125.rawiq", ("dmr",), None, False),
    ("p25_1_78125", "data/p25_1_78125.rawiq", ("p25",), None, False),
    ("dpmr_1_48000", "data/dpmr_1_48000.rawiq", ("dpmr",), None, False),
    ("wideband_2_5mhz", "data/synthesized_wideband_2.5MHz.rawiq", ("dmr",), None, True),
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build golden decoder vectors.")
    parser.add_argument("--project-root", default="/home/lzkj/lzkj_workspace/python_docs/DMR_demo")
    parser.add_argument("--out-dir", default="golden/current")
    args = parser.parse_args(argv)

    root = os.path.abspath(args.project_root)
    out_dir = os.path.abspath(args.out_dir)
    os.makedirs(out_dir, exist_ok=True)
    sys.path.insert(0, root)
    os.chdir(root)

    import scanner  # pylint: disable=import-error,import-outside-toplevel

    for name, rel_path, protocols, sample_rate, blind in SAMPLES:
        target = os.path.join(root, rel_path)
        if not os.path.exists(target):
            print(f"skip missing sample: {target}")
            continue
        out_path = os.path.join(out_dir, f"{name}.json")
        print(f"building {out_path}")
        scanner.scan_file(
            target,
            output_json=out_path,
            protocol_names=list(protocols),
            sample_rate=sample_rate,
            blind_search=blind,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

