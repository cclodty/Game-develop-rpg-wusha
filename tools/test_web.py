#!/usr/bin/env python3
"""Real Chromium/WebGL input smoke test; reads saves but never injects game state.

Requires Python Playwright and Pillow. Uses an isolated temporary browser profile
and a random loopback port, leaving the player's port-8070 save untouched.
With --record-video, install the recorder using `python3 -m playwright install ffmpeg`.
"""
import argparse
from functools import partial
from http.server import ThreadingHTTPServer
import hashlib
import io
import json
from pathlib import Path
import shutil
from threading import Thread
import time

from PIL import Image, ImageStat
from playwright.sync_api import sync_playwright
from serve_web import GameHandler


READ_SAVE_JS = r"""async () => {
    for (const info of await indexedDB.databases()) {
        const db = await new Promise((resolve, reject) => {
            const request = indexedDB.open(info.name);
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
        });
        try {
            for (const name of db.objectStoreNames) {
                const store = db.transaction(name).objectStore(name);
                const requests = [store.getAllKeys(), store.getAll()];
                const [keys, records] = await Promise.all(requests.map(request => new Promise((resolve, reject) => {
                    request.onsuccess = () => resolve(request.result);
                    request.onerror = () => reject(request.error);
                })));
                for (let i = 0; i < records.length; i++) {
                    if (!String(keys[i]).endsWith('/run-v1.json') || !records[i].contents) continue;
                    try {
                        const value = JSON.parse(new TextDecoder().decode(new Uint8Array(records[i].contents)));
                        if (value.version === 1 && value.data && value.data.hero_name) return value.data;
                    } catch (_) { /* Ignore non-save files in the browser filesystem. */ }
                }
            }
        } finally { db.close(); }
    }
    return null;
}"""


class QuietHandler(GameHandler):
    def log_message(self, _format, *_args):
        pass


class Journey:
    def __init__(self, page, url, output, name):
        self.page, self.url, self.output, self.name = page, url, output, name
        # Godot receives canvas keyboard events. Playwright insert_text() emits
        # a DOM input event, which does not emulate a real Chinese IME here.
        self.hero_name = {"herbalist": "YaoXing", "courier": "WangShan", "performer": "XiaoMan"}.get(name, name)
        self.started = time.monotonic()
        self.markers = []

    def mark(self, name):
        self.markers.append({"name": name, "seconds": round(time.monotonic() - self.started, 3)})

    def loaded(self):
        self.page.wait_for_function("!document.getElementById('status')", timeout=120000)
        self.page.wait_for_timeout(700)

    def capture(self, stage):
        return self.page.screenshot(path=str(self.output / f"{self.name}-{stage}.png"))

    def save(self, predicate, description, timeout=20):
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            last = self.page.evaluate(READ_SAVE_JS)
            if isinstance(last, dict) and predicate(last):
                print("PASS WEB:", description, flush=True)
                return last
            self.page.wait_for_timeout(150)
        self.capture("failure")
        (self.output / f"{self.name}-failure-save.json").write_text(json.dumps(last, ensure_ascii=False, indent=2))
        raise AssertionError(f"Timed out: {description}; actual save={last}")

    def create(self, origin):
        self.page.goto(self.url, wait_until="load", timeout=30000)
        self.loaded()
        self.capture("title")
        self.page.mouse.click(380, 552)
        self.page.wait_for_timeout(150)
        self.page.mouse.click(460, 230)
        self.page.keyboard.press("Control+A")
        self.page.keyboard.type(self.hero_name, delay=35)
        self.page.mouse.click({"herbalist": 334, "courier": 719, "performer": 1104}[origin], 655)
        self.capture("creation")
        self.page.mouse.click(1109, 758)
        return self.save(lambda data: data["hero_name"] == self.hero_name and data["origin"] == origin and data.get("dialogue", {}).get("cursor"), f"{origin}: real mouse/keyboard character creation")

    def finish_dialogue(self, maximum=90):
        """Read genuine lines; choose the visible jade return option at question hubs."""
        data = self.save(lambda value: True, "read current dialogue checkpoint")
        for _ in range(maximum):
            dialogue = data.get("dialogue", {})
            if not dialogue:
                return data
            cursor = dialogue.get("cursor", "")
            snapshot = Image.open(io.BytesIO(self.page.screenshot())).convert("RGB")
            green_rows = []
            for y in range(635, 850):
                red, green, blue = snapshot.getpixel((700, y))
                if 30 < red < 90 and 65 < green < 140 and 50 < blue < 130 and green > red * 1.35:
                    green_rows.append(y)
            if len(green_rows) >= 18:
                # Only the final dialogue response has a solid jade background.
                self.page.mouse.click(800, (green_rows[0] + green_rows[-1]) / 2)
            else:
                self.page.keyboard.press("Enter")
            data = self.save(lambda value: not value.get("dialogue") or value["dialogue"].get("cursor") != cursor, "dialogue input advances the saved checkpoint")
        raise AssertionError("Dialogue did not return to gameplay within its authored line limit")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser", default=shutil.which("chromium") or shutil.which("google-chrome"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--origins", nargs="+", choices=("herbalist", "courier", "performer"), default=["herbalist", "courier", "performer"], help="Focus a regression run after a scoped change; default checks all origins.")
    parser.add_argument("--record-video", action="store_true", help="Record genuine browser playback for animation review; clips/markers are written under the output directory.")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output or root / "artifacts" / "web"
    output.mkdir(parents=True, exist_ok=True)
    (root / "artifacts" / ".gdignore").touch()
    (output / "result.json").unlink(missing_ok=True)
    web = root / "build" / "web"
    if not (web / "index.html").exists():
        parser.error("Export first: bash tools/export_web.sh")
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietHandler, directory=str(web)))
    Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_address[1]}/"
    messages, checks, recordings = [], [], []
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(executable_path=args.browser, headless=True, args=[
                "--no-sandbox", "--disable-dev-shm-usage", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
            ])
            for origin in args.origins:
                context_options = {"viewport": {"width": 1440, "height": 900}, "device_scale_factor": 1}
                if args.record_video:
                    context_options.update(record_video_dir=str(output / "recordings"), record_video_size={"width": 1440, "height": 900})
                context = browser.new_context(**context_options)
                page = context.new_page()
                page.on("console", lambda event: messages.append({"type": event.type, "text": event.text}))
                page.on("pageerror", lambda error: messages.append({"type": "pageerror", "text": str(error)}))
                journey = Journey(page, url, output, origin)
                opening = journey.create(origin)
                capability = page.evaluate("({width:canvas.width,height:canvas.height,threads:GODOT_THREADS_ENABLED,isolated:crossOriginIsolated,webgl:!!canvas.getContext('webgl2')})")
                assert capability == {"width": 1440, "height": 900, "threads": False, "isolated": False, "webgl": True}, capability
                png = journey.capture("opening")
                assert min(ImageStat.Stat(Image.open(io.BytesIO(png)).convert("RGB")).stddev) > 12
                assert opening["dialogue"]["title"] == "intro_" + origin
                assert opening["spent"] == 0
                if origin == "herbalist":
                    checkpoint = opening["dialogue"].copy()
                    page.reload(wait_until="load")
                    journey.loaded()
                    page.mouse.click(380, 632)
                    journey.save(lambda data: data.get("dialogue", {}).get("cursor") == checkpoint["cursor"], "reload/Continue retains exact opening line")
                town = journey.finish_dialogue()
                assert town["spent"] == 0 and town["phase"] == "town" and not town["pending"]
                page.wait_for_timeout(4900)  # Let the welcome toast clear for a legible HUD capture.
                journey.capture("town")
                before = town["world_position"].copy()
                journey.mark("walking-start")
                page.keyboard.down("d")
                page.wait_for_timeout(650)
                page.keyboard.up("d")
                if args.record_video:
                    # Capture both real facing directions while retaining a
                    # net rightward displacement for the persisted-input check.
                    page.keyboard.down("a")
                    page.wait_for_timeout(450)
                    page.keyboard.up("a")
                    page.keyboard.down("d")
                    page.wait_for_timeout(500)
                    page.keyboard.up("d")
                page.keyboard.press("Control+s")
                moved = journey.save(lambda data: data["world_position"][0] > before[0] + 35, "WASD moves the rendered character and persists its position")
                assert moved["spent"] == 0
                journey.mark("walking-end")
                checks.append(f"{origin}: WebGL, creation, bespoke intro, free town walking, independent persistent save")
                if origin == "herbalist":
                    exercise_activity(journey, checks)
                context.close()
                if args.record_video:
                    target = output / "recordings" / f"{origin}-gameplay.webm"
                    page.video.save_as(str(target))
                    recordings.append({"origin": origin, "path": str(target), "markers": journey.markers})
            browser.close()
        errors = [message for message in messages if message["type"] == "pageerror" or "SCRIPT ERROR" in message["text"] or message["text"].startswith("ERROR:")]
        assert not errors, errors
        hashes = {}
        for name in ("index.html", "index.js", "index.wasm", "index.pck"):
            with (web / name).open("rb") as stream:
                hashes[name] = hashlib.file_digest(stream, "sha256").hexdigest()
        (output / "result.json").write_text(json.dumps({"checks": checks, "origins": args.origins, "console": messages, "state_injection": False, "build_sha256": hashes, "recordings": recordings}, ensure_ascii=False, indent=2))
        print(f"WEB TESTS COMPLETE: {len(checks)} flow groups passed; no engine/browser errors", flush=True)
    finally:
        server.shutdown()
        server.server_close()


def exercise_activity(journey, checks):
    page = journey.page
    page.mouse.click(1276, 653)
    page.wait_for_timeout(200)
    journey.capture("planner")
    page.mouse.click(784, 341)  # First planner row: sword lesson.
    page.wait_for_timeout(150)
    journey.capture("activity-cost")
    assert journey.save(lambda data: True, "preview activity cost")["spent"] == 0
    page.mouse.click(970, 670)
    lesson = journey.save(lambda data: data.get("pending", {}).get("id") == "sword_lesson" and data["spent"] == 2, "confirming lesson pays exactly its two slots")
    assert "sword_qi" not in lesson["skills"]
    learned = journey.finish_dialogue()
    assert learned["spent"] == 2 and learned["training"] == 2 and "sword_qi" in learned["skills"] and not learned["pending"]
    checks.append("Visible cost confirmation and completed story award the advertised skill exactly once")

    page.mouse.click(1276, 653)
    page.wait_for_timeout(200)
    page.mouse.click(784, 464)  # Second row: repeatable sword practice.
    page.wait_for_timeout(150)
    page.mouse.click(970, 670)
    journey.save(lambda data: data.get("pending", {}).get("id") == "practice" and data["spent"] == 3, "practice adds one activity slot")
    journey.finish_dialogue()
    began = journey.save(lambda data: data.get("pending", {}).get("stage") == "combat", "briefing enters the real-time battlefield")
    journey.mark("combat-start")
    page.wait_for_timeout(1000)
    page.mouse.move(815, 410)
    page.keyboard.down("j")
    page.keyboard.down("d")
    page.wait_for_timeout(550)
    page.keyboard.up("d")
    page.keyboard.press("q")
    page.keyboard.press("Space")
    page.wait_for_timeout(200)
    page.keyboard.up("j")
    journey.capture("battle")
    page.mouse.click(1320, 65)
    paused = journey.save(lambda data: data.get("pending", {}).get("combat", {}).get("qi_cooldown", 0) > 0, "combat keyboard input casts learned sword qi")
    battle = paused["pending"]["combat"]
    assert battle["position"] != began["pending"]["combat"]["position"]
    assert battle["combo"] > 0 and battle["stamina"] < 100
    journey.capture("battle-paused")
    page.wait_for_timeout(1100)
    page.keyboard.press("Control+s")
    still = journey.save(lambda data: data.get("pending", {}).get("combat", {}).get("elapsed") == battle["elapsed"], "pause retains the battlefield simulation timestamp")
    assert still["pending"]["combat"]["hp"] == battle["hp"]
    page.mouse.click(910, 665)
    page.wait_for_timeout(300)
    page.reload(wait_until="load")
    journey.loaded()
    page.mouse.click(380, 632)
    page.wait_for_timeout(120)
    page.mouse.click(1320, 65)
    page.wait_for_timeout(300)
    resumed = journey.save(lambda data: data.get("pending", {}).get("stage") == "combat" and data.get("pending", {}).get("combat", {}).get("elapsed", 0) >= battle["elapsed"], "reload/Continue restores the active battle")
    assert resumed["spent"] == 3 and resumed["pending"]["token"] == paused["pending"]["token"]
    assert resumed["pending"]["combat"]["position"] == battle["position"]
    assert resumed["pending"]["combat"]["qi_cooldown"] > 0
    journey.capture("battle-resumed")
    checks.append("Actual J/D/Space/Q inputs, pause freeze and battle save/reload preserve one-time activity cost")
    journey.mark("combat-resumed")
    page.mouse.click(530, 665)
    page.wait_for_timeout(120)
    page.mouse.click(1276, 737)
    page.wait_for_timeout(120)
    page.mouse.click(912, 574)
    town = journey.save(lambda data: not data["pending"] and data["phase"] == "town", "retreat returns to town")
    assert town["spent"] == 3 and town["training"] == 2 and "practice" not in town["completed"]
    checks.append("Retreat retains spent time and does not issue unfinished practice rewards")

    page.mouse.click(1276, 592)
    page.wait_for_timeout(200)
    journey.capture("map")
    page.mouse.click(720, 644)
    page.wait_for_timeout(150)
    page.mouse.click(1139, 373)
    page.wait_for_timeout(150)
    page.mouse.click(970, 670)
    journey.save(lambda data: data.get("pending", {}).get("id") == "herb_errand", "map books the two-slot grove exploration")
    journey.finish_dialogue()
    journey.save(lambda data: data.get("pending", {}).get("stage") == "explore", "grove scene opens with an active exploration")
    page.mouse.click(368, 446)
    visited = journey.save(lambda data: "first" in data.get("pending", {}).get("visited", []), "click-to-walk reaches and collects the actual grove clue")
    assert visited["spent"] == 5
    journey.capture("grove-clue")
    page.mouse.click(1320, 65)
    page.wait_for_timeout(150)
    page.mouse.click(910, 665)
    page.wait_for_timeout(300)
    page.reload(wait_until="load")
    journey.loaded()
    page.mouse.click(380, 632)
    restored = journey.save(lambda data: data.get("pending", {}).get("stage") == "explore" and data.get("pending", {}).get("visited") == ["first"], "Continue retains exploration progress")
    assert restored["spent"] == 5
    page.mouse.click(738, 361)
    second = journey.save(lambda data: set(data.get("pending", {}).get("visited", [])) == {"first", "second"}, "restored exploration accepts the next real clue without repeating the first")
    assert second["spent"] == 5
    journey.capture("grove-resumed")
    checks.append("Map travel, actual grove walking and clue/save/reload progression share a single trip cost")
    page.mouse.click(1276, 726)
    page.wait_for_timeout(150)
    page.mouse.click(912, 574)
    journey.save(lambda data: not data["pending"] and data["spent"] == 5, "exploration retreat retains the single trip cost")
    page.mouse.click(1276, 653)
    page.wait_for_timeout(180)
    page.mouse.click(1115, 789)
    page.wait_for_timeout(150)
    journey.capture("early-exam-confirmation")
    assert journey.save(lambda data: True, "early exam still awaits explicit confirmation")["spent"] == 5
    page.mouse.click(920, 632)
    journey.save(lambda data: data.get("pending", {}).get("id") == "exam" and data["spent"] == 21, "confirmed early exam forfeits only the remaining preparation")
    journey.finish_dialogue()
    journey.save(lambda data: data.get("pending", {}).get("stage") == "combat", "exam story opens the live examiner battle")
    page.mouse.click(1276, 737)
    page.wait_for_timeout(150)
    page.mouse.click(912, 574)
    result = journey.save(lambda data: data["phase"] == "results" and not data["pending"], "concession completes the exam without forced retries")
    assert result["exam_result"]["won"] is False and result["exam_result"]["eligible"] == []
    journey.capture("exam-results")
    page.mouse.click(1118, 645)
    journey.save(lambda data: data["school"] == "stay" and bool(data.get("dialogue")), "available stay choice opens its authored ending")
    ending = journey.finish_dialogue()
    assert ending["school"] == "stay" and ending["phase"] == "ending" and ending["spent"] == 21
    journey.capture("ending")
    checks.append("Real browser journey reaches the eighth-day exam and stay ending through explicit choices, without state injection")


if __name__ == "__main__":
    main()
