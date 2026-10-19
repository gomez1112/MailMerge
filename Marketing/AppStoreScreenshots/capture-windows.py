"""Save the six named demo screens; capture no other windows or desktop content."""
import json
import pathlib
import subprocess
import sys
import time

window_list, output = sys.argv[1:]
folder = pathlib.Path(output)
folder.mkdir(parents=True, exist_ok=True)
saved = set()
deadline = time.monotonic() + 120
while time.monotonic() < deadline and len(saved) < 6:
    windows = json.loads(subprocess.check_output([window_list]))
    for window in windows:
        name = window["title"].removeprefix("MergeformShot:")
        if name == "transition" or name in saved:
            continue
        subprocess.run(["/usr/sbin/screencapture", "-x", "-o", "-l", window["id"], str(folder / (name + ".png"))], check=True)
        saved.add(name)
        print("Captured", name, flush=True)
    time.sleep(0.25)
if len(saved) != 6:
    raise RuntimeError(f"Captured {len(saved)} of 6 demo screens")
