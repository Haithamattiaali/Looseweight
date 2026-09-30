"""Prints the UDID of the best available iPhone simulator: newest iOS runtime, a Pro model when possible."""
import json
import subprocess
import sys

listing = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
best = None
for runtime, devices in listing["devices"].items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in runtime.split(".iOS-")[1].split("-") if part.isdigit())
    for device in devices:
        name = device["name"]
        if not name.startswith("iPhone"):
            continue
        is_plain_pro = "Pro" in name and "Max" not in name
        score = (version, is_plain_pro, name)
        if best is None or score > best[0]:
            best = (score, device["udid"], name, runtime)
if best is None:
    sys.exit("no iPhone simulator available")
print(f"Using {best[2]} ({best[3]})", file=sys.stderr)
print(best[1])
