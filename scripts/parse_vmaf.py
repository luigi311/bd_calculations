#!/usr/bin/env python3
import os, argparse, json

import numpy as np

from pathlib import Path


def parse_vmaf_json(file: Path):
    try:
        with open(file, "r") as f:
            data = json.load(f)

        mean = data["pooled_metrics"]["vmaf"]["mean"]
        frames = data["frames"]
        scores = [frame["metrics"]["vmaf"] for frame in frames]
        percentile_5 = np.percentile(scores, 5)
    except Exception as e:
        print(f"Error parsing file {file}: {e}")
        os.exit(1)

    return mean, percentile_5


def main():
    parser = argparse.ArgumentParser(
        description="Parse VMAF JSON files for mean and 95 percentile values"
    )
    parser.add_argument("--input", "-i", type=Path, help="Input File")
    parser.add_argument("--output", "-o", type=Path, help="Output File")
    args = parser.parse_args()

    if not args.input.exists():
        print(f"File {args.input} does not exist")
        return

    mean, percentile_5 = parse_vmaf_json(args.input)

    with open(args.output, "w") as f:
        f.write(f"{mean},{percentile_5}")


if __name__ == "__main__":
    main()
