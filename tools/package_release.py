"""Package the source and an already exported playable web build, without saves."""
from pathlib import Path
import hashlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts" / "martial-release"
WEB = ROOT / "build" / "web"
MAX_ARCHIVE_BYTES = 100 * 1024 * 1024
SAVE_NAMES = {
    base + suffix
    for base in ("run-v1.json", "run-cards-v2.json", "run-martial-v3.json", "lab-martial-v3.json")
    for suffix in ("", ".bak", ".tmp")
}

PLAY_GUIDE = """江湖未遠 — 入山之前 · 內功與蓄勢

先選擇如何回應路上的人與事，再安排自己的七日江湖。
這是內功、蓄勢、運勁與武學混搭的驗證版，舊卡牌與即時劍戰版另行保留。

Windows 開始遊玩：
1. 在下載的 ZIP 上按右鍵，選「全部解壓縮」。
2. 進入解壓後的 jianghu-weiyuan-martial-web 資料夾，雙擊 Play-Windows.cmd。
3. 遊戲會在預設瀏覽器開啟；遊玩時保留啟動視窗。
4. 想先試新規則，可進入「武學試招」選三套牌組與四類對手。
   想走故事，可自訂姓名與出身，完成六次情境選擇後開始七日準備。
5. 結束時關閉遊戲分頁與啟動視窗即可。

不需要安裝 Godot 或 Python。Windows 啟動器使用系統內建 PowerShell。
固定本機網址：http://127.0.0.1:8072/
若瀏覽器未自動開啟，待啟動視窗顯示 ready 後，手動開啟此網址。
若提示埠已占用，先關閉之前的卡牌遊戲啟動視窗，再重新開啟。

macOS／Linux：
在解壓後的資料夾開啟終端，執行 python3 tools/serve_web.py，
再以瀏覽器開啟終端顯示的網址。這個方式需要 Python 3。

城鎮操作：
WASD／方向鍵：移動；也可以點擊地面走動。
F／Enter：與附近人物或目標互動，也可點擊人物後走近互動。
暫停、行程、角色與配招、地圖與對話選項使用畫面按鈕。

卡牌戰鬥：
先查看敵方意圖，點選手牌與目標，再明確選「普通施展」或「運勁」。
普通施展不花勢；運勁花牌面指定的勢，勢不足時仍可使用普通版本。
牌組固定十張、每種最多兩張，主修一門內功、裝備一種主兵器。
每回合恢復三點真氣，可留一張牌，下一回合連同留牌補至五張。
勢上限三點，每輪最多取得兩點，可以跨回合保留，戰鬥結束清空。
掠影步可挑其他手牌換掉，也可略過；未完成挑牌前不會進入下一招。
用藥需一點真氣，每場最多一次；本場除外的牌不再洗回。
決定好出招和留牌後按「結束回合」。
鎮上沒有進行中活動時，可免費調整牌組；活動開始後暫時鎖定。
學會新招式不會自動換牌，請在「角色與配招」選擇帶入的十張牌。

每天早、午、晚三個時段，七日後參加選拔。
走路、閱讀與思考出牌的現實時間不扣行程；活動開始前會明示成本。
戰敗可重試，重試不重扣時段，保留該次出發的牌組與抽牌種子。
正式撤退保留已花費時間，不發未完成獎勵。

旅程存檔為 run-martial-v3.json，武學試招另存 lab-martial-v3.json。
兩者獨立保存在目前瀏覽器的網站資料；請固定使用同一瀏覽器與網址續玩。
不載入或改寫舊 run-cards-v2.json／run-v1.json。
本版使用 8072，舊卡牌版保留 8071，動作版 8070，舊《山河行》8060。

直接雙擊 build/web/index.html 無法正確載入 WebAssembly，請使用啟動器。
此版本以桌面橫向畫面為主；手機、手把及 Safari 尚未列為主要支援目標。
序章 6–8 分鐘、首篇 30–60 分鐘是設計目標，真人試玩結果另見驗證文件。
授權資訊見 THIRD_PARTY_NOTICES.md 與 build/web/licenses/。
"""


def package() -> None:
    for name in ("index.html", "index.js", "index.wasm", "index.pck"):
        if not (WEB / name).is_file():
            raise SystemExit(f"Missing {name}; run bash tools/export_web.sh first.")
    for name in ("Godot-LICENSE.txt", "Godot-COPYRIGHT.txt", "DialogueManager-LICENSE.txt"):
        if not (WEB / "licenses" / name).is_file():
            raise SystemExit(f"Missing license: {name}; export again before packaging.")

    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT.parent / ".gdignore").touch(exist_ok=True)
    # A failed/oversized rebuild must not leave an apparently current manifest.
    (OUTPUT / "SHA256SUMS.txt").unlink(missing_ok=True)
    source_zip = OUTPUT / "jianghu-weiyuan-martial-source.zip"
    excluded = {".git", ".godot", "artifacts", "build", "__pycache__", ".pytest_cache"}
    with zipfile.ZipFile(source_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(ROOT.rglob("*")):
            relative = path.relative_to(ROOT)
            if any(part in excluded for part in relative.parts) or not path.is_file():
                continue
            if path.suffix in {".tmp", ".pyc"} or path.name in SAVE_NAMES | {".DS_Store"}:
                continue
            archive.write(path, Path("jianghu-weiyuan-martial-source") / relative)

    web_zip = OUTPUT / "jianghu-weiyuan-martial-web.zip"
    with zipfile.ZipFile(web_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(WEB.rglob("*")):
            if path.is_file() and path.suffix not in {".import", ".tmp"} and path.name not in SAVE_NAMES | {".gdignore", ".DS_Store"}:
                archive.write(path, Path("jianghu-weiyuan-martial-web/build/web") / path.relative_to(WEB))
        for name in ("tools/serve_web.py", "tools/serve_web_windows.ps1", "Play-Windows.cmd", "THIRD_PARTY_NOTICES.md"):
            archive.write(ROOT / name, Path("jianghu-weiyuan-martial-web") / name)
        archive.writestr("jianghu-weiyuan-martial-web/開始遊玩.txt", PLAY_GUIDE)

    for path in (source_zip, web_zip):
        if path.stat().st_size >= MAX_ARCHIVE_BYTES:
            raise SystemExit(f"Archive exceeds the 100 MiB delivery limit: {path.name}")

    with (OUTPUT / "SHA256SUMS.txt").open("w") as hashes:
        for path in (source_zip, web_zip):
            with path.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            hashes.write(digest + "  " + path.name + "\n")
            print(f"{path}: {path.stat().st_size / 1024 / 1024:.1f} MiB; SHA256 {digest}")


if __name__ == "__main__":
    package()
