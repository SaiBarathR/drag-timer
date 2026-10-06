#!/bin/zsh
set -euo pipefail

# Prints a Markdown table of line coverage per source file from the last
# `swift test --enable-code-coverage` run.
root="${0:A:h:h}"
cd "$root"

report="$(swift test --show-codecov-path)"
if [[ ! -f "$report" ]]; then
    echo "No coverage report at $report; run swift test --enable-code-coverage first." >&2
    exit 1
fi

/usr/bin/python3 - "$report" <<'PY'
import json, sys

files = json.load(open(sys.argv[1]))["data"][0]["files"]
rows = []
for entry in files:
    name = entry["filename"]
    if "/Sources/DragTimer/" not in name:
        continue
    lines = entry["summary"]["lines"]
    rows.append((name.split("/Sources/DragTimer/")[1], lines["covered"], lines["count"]))

covered = sum(row[1] for row in rows)
total = sum(row[2] for row in rows)
print("| File | Line coverage |")
print("| ---- | ------------: |")
for name, hit, count in sorted(rows):
    print(f"| `{name}` | {100 * hit / max(count, 1):.0f}% |")
print(f"| **Total** | **{100 * covered / max(total, 1):.0f}%** |")
PY
