#!/usr/bin/env python3
"""Read-only macOS process sampling. CPU 100% means one fully used logical core.

RSS is resident memory, not total GPU/WindowServer cost or physical footprint.
Run the same workload/display mode before comparing versions. This script never
opens/closes a window or changes a display mode.
"""
import argparse
import datetime
import json
import statistics
import subprocess
import time
from pathlib import Path


def cpu_seconds(value):
    fields = value.split(":")
    return sum(float(part) * (60 ** index) for index, part in enumerate(reversed(fields)))


def read_process(pid):
    result = subprocess.run(
        ["/bin/ps", "-p", str(pid), "-o", "pid=,pcpu=,rss=,time="],
        text=True, capture_output=True, check=True,
    )
    fields = result.stdout.split()
    if len(fields) != 4 or int(fields[0]) != pid:
        raise RuntimeError("Process exited or could not be read")
    return {
        "monotonic_seconds": time.monotonic(),
        "reported_cpu_percent": float(fields[1]),
        "rss_mib": int(fields[2]) / 1024,
        "cpu_seconds": cpu_seconds(fields[3]),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pid", type=int)
    parser.add_argument("--seconds", type=int, default=30)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--label", default="idle")
    args = parser.parse_args()
    if args.pid <= 0 or not 5 <= args.seconds <= 60:
        parser.error("Use a positive PID and 5–60 seconds")
    samples = [read_process(args.pid)]
    deadline = time.monotonic() + args.seconds
    while time.monotonic() < deadline:
        time.sleep(min(2, max(0, deadline - time.monotonic())))
        samples.append(read_process(args.pid))
    elapsed = samples[-1]["monotonic_seconds"] - samples[0]["monotonic_seconds"]
    rss = [sample["rss_mib"] for sample in samples]
    report = {
        "recorded_at": datetime.datetime.now().astimezone().isoformat(),
        "pid": args.pid, "label": args.label, "duration_seconds": round(elapsed, 3),
        "average_cpu_percent_one_core": round(100 * (samples[-1]["cpu_seconds"] - samples[0]["cpu_seconds"]) / elapsed, 3),
        "rss_mib": {"min": round(min(rss), 2), "mean": round(statistics.mean(rss), 2), "max": round(max(rss), 2)},
        "limitations": "Idle process sample only; RSS is not footprint. Excludes GPU and WindowServer, and does not isolate mirroring cost.",
        "samples": samples,
    }
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key != "samples"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
