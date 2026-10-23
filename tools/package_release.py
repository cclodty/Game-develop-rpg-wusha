"""Package the source and an already exported playable web build, without saves."""
from pathlib import Path
import hashlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts" / "cards-release"
WEB = ROOT / "build" / "web"
MAX_ARCHIVE_BYTES = 100 * 1024 * 1024

PLAY_GUIDE = """江湖未遠 — 入山之前 · 卡牌原型

先選擇如何回應路上的人與事，再安排自己的七日江湖。
這是情境建角與回合制卡牌版本，舊即時劍戰版另行保留。

Windows 開始遊玩：
1. 在下載的 ZIP 上按右鍵，選「全部解壓縮」。
2. 進入解壓後的 jianghu-weiyuan-cards-web 資料夾，雙擊 Play-Windows.cmd。
3. 遊戲會在預設瀏覽器開啟；遊玩時保留啟動視窗。
4. 自訂姓名與出身，完成六次情境選擇及能力回顧，開始七日準備。
5. 結束時關閉遊戲分頁與啟動視窗即可。

不需要安裝 Godot 或 Python。Windows 啟動器使用系統內建 PowerShell。
固定本機網址：http://127.0.0.1:8071/
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
先查看敵人本回合意圖與牌面預覽，再點牌出招；多名對手時再點目標。
決定好後按「結束回合」。
牌組固定十張、每種最多兩張；每回合抽五張、恢復三點真氣。
回合結束時丟棄手牌；標示「本場除外」的牌在這場戰鬥不再抽到。
鎮上沒有進行中活動時，可免費調整牌組；活動開始後暫時鎖定。
學會新招式不會自動換牌，請在「角色與配招」選擇帶入的十張牌。

每天早、午、晚三個時段，七日後參加選拔。
走路、閱讀與思考出牌的現實時間不扣行程；活動開始前會明示成本。
戰敗可重試，重試不重扣時段，保留該次出發的牌組與抽牌種子。
正式撤退保留已花費時間，不發未完成獎勵。

卡牌版存檔名稱為 run-cards-v2.json，保存在目前瀏覽器的網站資料。
請固定使用同一瀏覽器與網址續玩；不會載入或改寫動作版 run-v1.json。
本版使用 8071，動作版保留 8070，舊《山河行》保留 8060。

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
    source_zip = OUTPUT / "jianghu-weiyuan-cards-source.zip"
    excluded = {".git", ".godot", "artifacts", "build", "__pycache__", ".pytest_cache"}
    with zipfile.ZipFile(source_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(ROOT.rglob("*")):
            relative = path.relative_to(ROOT)
            if any(part in excluded for part in relative.parts) or not path.is_file():
                continue
            if path.suffix in {".tmp", ".pyc"} or path.name in {"run-v1.json", "run-v1.json.bak", "run-cards-v2.json", "run-cards-v2.json.bak", ".DS_Store"}:
                continue
            archive.write(path, Path("jianghu-weiyuan-cards-source") / relative)

    web_zip = OUTPUT / "jianghu-weiyuan-cards-web.zip"
    with zipfile.ZipFile(web_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(WEB.rglob("*")):
            if path.is_file() and path.suffix != ".import" and path.name != ".gdignore":
                archive.write(path, Path("jianghu-weiyuan-cards-web/build/web") / path.relative_to(WEB))
        for name in ("tools/serve_web.py", "tools/serve_web_windows.ps1", "Play-Windows.cmd", "THIRD_PARTY_NOTICES.md"):
            archive.write(ROOT / name, Path("jianghu-weiyuan-cards-web") / name)
        archive.writestr("jianghu-weiyuan-cards-web/開始遊玩.txt", PLAY_GUIDE)

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
