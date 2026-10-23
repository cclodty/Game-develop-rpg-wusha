#!/usr/bin/env python3
"""Extract short review clips from recorded browser gameplay, without frame synthesis.

Run test_web.py with --record-video first. The original WebM and marker report are
retained; ffmpeg only trims/re-encodes the real frames into portable MP4 files.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=root / "artifacts/web/result.json")
    parser.add_argument("--output", type=Path, default=root / "artifacts/animation-review")
    args = parser.parse_args()
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        parser.error("Install ffmpeg to extract MP4 clips; the original browser WebM remains playable.")
    report = json.loads(args.report.read_text())
    recordings = report.get("recordings", [])
    if not recordings:
        parser.error("No recordings found. Run python3 tools/test_web.py --record-video first.")
    args.output.mkdir(parents=True, exist_ok=True)
    clips = []
    for recording in recordings:
        markers = {entry["name"]: entry["seconds"] for entry in recording["markers"]}
        ranges = []
        if "walking-start" in markers and "walking-end" in markers:
            ranges.append(("walking", max(0, markers["walking-start"] - 0.5), markers["walking-end"] + 0.5))
        if "combat-start" in markers:
            ranges.append(("combat", max(0, markers["combat-start"] - 0.5), markers["combat-start"] + 4.0))
        for name, start, end in ranges:
            destination = args.output / f"{recording['origin']}-{name}.mp4"
            subprocess.run([
                ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-ss", str(start),
                "-i", recording["path"], "-t", str(end - start), "-an",
                "-vf", "scale=in_range=full:out_range=limited", "-color_range", "tv",
                "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(destination),
            ], check=True)
            clips.append({"path": str(destination), "source": recording["path"], "start_seconds": start, "end_seconds": end})
            print("Captured browser clip:", destination)
    (args.output / "clips.json").write_text(json.dumps({"clips": clips, "source_build_sha256": report.get("build_sha256", {}), "synthetic_frames": False}, indent=2))


if __name__ == "__main__":
    main()
