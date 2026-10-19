"""Record only the full demo window, using the verified window-snapshot capture path.

Usage: python3 record-frames.py /path/to/window-list /path/to/frames-directory
No desktop, other windows, microphone, or system audio is captured.
"""
import json
import pathlib
import subprocess
import sys
import time

window_list, output = sys.argv[1:]
folder = pathlib.Path(output)
folder.mkdir(parents=True, exist_ok=True)
deadline = time.monotonic() + 100
window_id = None
while time.monotonic() < deadline and window_id is None:
    windows = json.loads(subprocess.check_output([window_list]))
    window_id = next((w["id"] for w in windows if w["title"] == "MergeformShot:02-mapping"), None)
    if window_id is None:
        time.sleep(0.2)
if window_id is None:
    raise RuntimeError("The named demo window did not appear")
print("Recording full demo-window frames", flush=True)
start = time.monotonic()
frames = []
while time.monotonic() - start < 25:
    elapsed = time.monotonic() - start
    name = f"frame-{len(frames)}.png"
    subprocess.run(["/usr/sbin/screencapture", "-x", "-o", "-l", window_id, str(folder / name)], check=True)
    frames.append({"file": name, "seconds": elapsed})
    time.sleep(0.08)
(folder / "frames.json").write_text(json.dumps(frames))
print(f"Recorded {len(frames)} full-window frames over 25 seconds", flush=True)
