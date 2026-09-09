"""Sample one local test process. RSS excludes WindowServer and is not physical footprint."""
import argparse
import json
import pathlib
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("pid", type=int)
parser.add_argument("--seconds", type=int, default=30)
parser.add_argument("--output", required=True)
parser.add_argument("--label", default="idle")
args = parser.parse_args()

def cpu_seconds(text):
    parts = [float(x) for x in text.split(":")]
    return sum(value * 60 ** index for index, value in enumerate(reversed(parts)))

samples = []
start = time.monotonic()
for index in range(args.seconds // 5 + 1):
    output = subprocess.check_output(["/bin/ps", "-p", str(args.pid), "-o", "rss=,time="], text=True).split()
    if len(output) != 2:
        raise RuntimeError("The test process is not running")
    samples.append({"elapsed_seconds": round(time.monotonic()-start, 3), "rss_kib": int(output[0]), "cpu_seconds": cpu_seconds(output[1])})
    if index < args.seconds // 5:
        time.sleep(5)
duration = samples[-1]["elapsed_seconds"]-samples[0]["elapsed_seconds"]
result = {
    "label": args.label,
    "pid": args.pid,
    "metric": "Process resident set size (KiB) and cumulative user+system CPU time from ps; not total system memory or battery energy",
    "duration_seconds": duration,
    "rss_mib_min": min(s["rss_kib"] for s in samples)/1024,
    "rss_mib_max": max(s["rss_kib"] for s in samples)/1024,
    "average_cpu_percent_one_core": round(100*(samples[-1]["cpu_seconds"]-samples[0]["cpu_seconds"])/duration, 4),
    "samples": samples,
}
path = pathlib.Path(args.output)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(result, indent=2)+"\n")
print(json.dumps({k:v for k,v in result.items() if k != "samples"}, indent=2))
