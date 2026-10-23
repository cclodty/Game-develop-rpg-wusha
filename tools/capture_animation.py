#!/usr/bin/env python3
"""Validate and record the actual browser animation preview through visible controls.

No game-state injection or generated frames: screenshots and WebM are captured
directly from Chromium. Optional ffmpeg output only trims/re-encodes that video.
Requires Python Playwright/Pillow and Playwright's ffmpeg recorder; install the
recorder with `python3 -m playwright install ffmpeg`. A system ffmpeg additionally
enables the shareable MP4 copy.
"""
import argparse
from functools import partial
import hashlib
from http.server import ThreadingHTTPServer
import io
import json
from pathlib import Path
import shutil
import subprocess
from threading import Thread
import time

from PIL import Image, ImageChops
from playwright.sync_api import sync_playwright
from test_web import QuietHandler, READ_SAVE_JS


ACTORS = ["courier", "herbalist", "performer", "bandit", "lancer", "examiner", "shen", "lu", "tao", "zhou", "xiao", "lin"]
CLIPS = ["idle", "walk", "attack", "dodge", "hurt", "defeat"]
POSE_AREA = (365, 207, 1053, 612)  # Excludes changing labels and control highlights.


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser", default=shutil.which("chromium") or shutil.which("google-chrome"))
    parser.add_argument("--output", type=Path, default=root / "artifacts/animation-review")
    args = parser.parse_args()
    output = args.output
    output.mkdir(parents=True, exist_ok=True)
    (root / "artifacts/.gdignore").touch()
    (output / "result.json").unlink(missing_ok=True)
    web = root / "build/web"
    if not (web / "index.pck").exists():
        parser.error("Export the stable animation build first: bash tools/export_web.sh")
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietHandler, directory=str(web)))
    Thread(target=server.serve_forever, daemon=True).start()
    messages, checks, markers = [], [], []
    browser = None
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(executable_path=args.browser, headless=True, args=[
                "--no-sandbox", "--disable-dev-shm-usage", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
            ])
            context = browser.new_context(viewport={"width": 1440, "height": 900}, device_scale_factor=1,
                                          record_video_dir=str(output / "recordings"), record_video_size={"width": 1440, "height": 900})
            page = context.new_page()
            started = time.monotonic()
            page.on("console", lambda event: messages.append({"type": event.type, "text": event.text}))
            page.on("pageerror", lambda error: messages.append({"type": "pageerror", "text": str(error)}))

            def click(x, y):
                page.mouse.click(x, y)
                page.wait_for_timeout(120)

            def actor(name):
                index = ACTORS.index(name)
                click(113 + (index % 2) * 139, 234 + (index // 2) * 65)

            def clip(name):
                click(1246, 234 + CLIPS.index(name) * 65)

            def frame(index, name=None):
                click(429 + index * 112, 830)
                png = page.screenshot(path=str(output / f"{name}.png") if name else None)
                return Image.open(io.BytesIO(png)).convert("RGB").crop(POSE_AREA)

            def mark(name):
                markers.append({"name": name, "seconds": round(time.monotonic() - started, 3)})

            page.goto(f"http://127.0.0.1:{server.server_address[1]}/", wait_until="load")
            page.wait_for_function("!document.getElementById('status')", timeout=120000)
            page.wait_for_timeout(600)
            assert page.evaluate(READ_SAVE_JS) is None
            click(380, 710)  # Title's animation-preview button.
            page.wait_for_timeout(300)
            mark("preview-start")
            actor("courier")
            clip("walk")
            first = frame(0, "courier-walk-0")
            page.wait_for_timeout(350)
            paused = Image.open(io.BytesIO(page.screenshot())).convert("RGB").crop(POSE_AREA)
            assert ImageChops.difference(first, paused).getbbox() is None, "Paused preview continues moving"
            checks.append("Paused sprite pixels remain unchanged while real time passes")
            fingerprints = {hashlib.sha256(first.tobytes()).hexdigest()}
            for index in range(1, 6):
                pose = frame(index, f"courier-walk-{index}")
                fingerprints.add(hashlib.sha256(pose.tobytes()).hexdigest())
            assert len(fingerprints) == 6, "Courier walk does not render six distinct poses"
            checks.append("All six courier walk cells render as different actual sprite poses")

            for name in ACTORS:
                actor(name)
                clip("idle" if name in ACTORS[6:] else "attack")
                pose_a = frame(0)
                pose_b = frame(3, f"{name}-pose")
                assert ImageChops.difference(pose_a, pose_b).getbbox() is not None, f"No visible frame change for {name}"
            checks.append("All six fighters and six NPCs visibly change drawn frame through the browser controls")

            # Record uninterrupted playback of every hero clip, followed by
            # role-specific action/idle loops. These are real rendered frames.
            actor("courier")
            frame(0)
            click(709, 666)  # Resume after the explicit paused frame selection.
            mark("playback-start")
            for name in CLIPS:
                clip(name)
                mark("courier-" + name)
                page.wait_for_timeout(2200)
            for name in ACTORS[1:]:
                actor(name)
                clip("idle" if name in ACTORS[6:] else "walk" if name == "herbalist" else "attack")
                mark(name)
                page.wait_for_timeout(1400)
            click(709, 666)
            mark("preview-end")
            actor("courier")
            clip("walk")
            frame(2, "preview")
            click(1319, 59)
            page.wait_for_timeout(200)
            assert page.evaluate(READ_SAVE_JS) is None, "Animation preview wrote a player save"
            checks.append("Preview returns to the title without creating or mutating a player save")
            context.close()
            recording = output / "preview.webm"
            page.video.save_as(str(recording))
            browser.close()
        errors = [item for item in messages if item["type"] == "pageerror" or "SCRIPT ERROR" in item["text"] or item["text"].startswith("ERROR:")]
        assert not errors, errors
        hashes = {}
        for name in ("index.html", "index.js", "index.wasm", "index.pck"):
            with (web / name).open("rb") as stream:
                hashes[name] = hashlib.file_digest(stream, "sha256").hexdigest()
        report = {"checks": checks, "console": messages, "recording": str(recording), "markers": markers,
                  "state_injection": False, "synthetic_frames": False, "build_sha256": hashes}
        ffmpeg = shutil.which("ffmpeg")
        if ffmpeg:
            times = {entry["name"]: entry["seconds"] for entry in markers}
            review = output / "preview.mp4"
            # The short shareable clip focuses on uninterrupted playback;
            # original WebM also retains the interactive frame/pause checks.
            start = max(0, times["playback-start"] - 0.3)
            subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-ss", str(start), "-i", str(recording),
                            "-t", str(times["preview-end"] - start + 0.3), "-an",
                            # Chromium JPEG/VP8 recordings contain full-range
                            # values; explicit conversion avoids washed-out MP4.
                            "-vf", "scale=in_range=full:out_range=limited", "-color_range", "tv",
                            "-c:v", "libx264", "-preset", "medium",
                            "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(review)], check=True)
            report["review_mp4"] = str(review)
        (output / "result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
        print(f"ANIMATION BROWSER COMPLETE: {len(checks)} visual/input groups passed; actual recording: {recording}")
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
