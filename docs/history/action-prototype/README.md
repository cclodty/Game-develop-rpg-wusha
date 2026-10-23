> 歷史文件：動作原型，來源提交 `9f6f187`。此檔描述即時劍戰版，不是目前卡牌版規格或驗證結果。新企劃見 [目前遊戲企劃](../../GAME_DESIGN.md)。

# 江湖未遠

**七日安排，一程江湖。**

《入山之前》是繁體中文、單人、俯視角 2D 武俠養成試玩篇：玩家從三種出身啟程，在七日早／午／晚共 21 個時段內安排練功、人情與探索，以即時劍戰參加第八日選拔。

本作在獨立 Godot 專案及存檔位置中製作，舊版《山河行》與其 GitHub 下載分支保留。30–60 分鐘是首篇的設計目標，尚需真人試玩驗證實際時長。

## 開始遊玩

[下載可玩版本](https://github.com/cclodty/Game-develop-rpg-wusha/raw/refs/heads/weiyuan-download/jianghu-weiyuan-web.zip) · [下載完整 Godot 原始碼](https://github.com/cclodty/Game-develop-rpg-wusha/raw/refs/heads/weiyuan-download/jianghu-weiyuan-source.zip) · [下載頁與校驗碼](https://github.com/cclodty/Game-develop-rpg-wusha/tree/weiyuan-download)

![望溪鎮實際遊戲畫面](https://raw.githubusercontent.com/cclodty/Game-develop-rpg-wusha/9f6f18760e450b22e86b4f42e366905568a59971/docs/images/town.png)

**Windows：**下載 `jianghu-weiyuan-web.zip` → 右鍵「全部解壓縮」→ 進入解壓後資料夾 → 雙擊 `Play-Windows.cmd`。瀏覽器會自動開啟；遊玩時保留啟動視窗，結束後關閉即可。使用 Windows 內建 PowerShell，不需要安裝 Python 或 Godot。

固定網址為 `http://127.0.0.1:8070/`，只供自己電腦連線。這與舊版的 8060 分開，瀏覽器存檔也分開。若瀏覽器未開啟，待啟動視窗顯示 ready 後，手動開啟網址；若埠占用，先關閉之前的遊戲啟動視窗。

**macOS／Linux：**在下載包資料夾執行 `python3 tools/serve_web.py`，再開啟顯示的網址。不要直接雙擊 `index.html`，WebAssembly 需要經 HTTP 載入。

**Godot 編輯器：**使用 Godot **4.6.3 標準版**匯入 `project.godot`，按 F5。或執行 `bash tools/run.sh`；不需要 .NET。

## 逐格動畫

標題畫面按「逐格動畫圖鑑」即可查看全部角色；支援播放／暫停、前後逐格、左右朝向與半速播放，也可直接點選底下兩排、共十二格縮圖。這個圖鑑不改動遊戲存檔。

[觀看實際動畫錄影（MP4）](https://github.com/cclodty/Game-develop-rpg-wusha/raw/refs/heads/weiyuan-download/preview.mp4)

![逐格動畫圖鑑](https://raw.githubusercontent.com/cclodty/Game-develop-rpg-wusha/9f6f18760e450b22e86b4f42e366905568a59971/docs/images/animation-preview.png)

三種主角造型與三種戰鬥對手各有待機、行走、出招、閃避、受擊及倒地；六名鎮民各有自己的待機動作。每組由 6 格增加到 12 格，合共 42 組、504 格獨立姿態。保留原有動作時長，待機由每秒 6 格提高至 12 格、行走由每秒 10 格提高至 20 格。城鎮與戰鬥會直接播放這些獨立繪製的畫格，對話仍使用原有肖像。

## 操作與時間

| 操作 | 按鍵 |
| --- | --- |
| 行走 | WASD／方向鍵，或點擊地面 |
| 與人物／目標互動 | 走近後 F／Enter，或點擊人物自動靠近 |
| 普攻 | 滑鼠左鍵／J |
| 閃避 | Space |
| 武功 | Q：破雲劍氣；E：掠影突進，需先學會 |
| 用藥 | R |
| 暫停／返回 | Esc；也可按右上角暫停 |
| 手動存檔 | Ctrl+S（平時亦會自動存檔） |
| 選單、行程、地圖、對話 | 畫面按鈕 |

普通走路、閱讀、查看人物與紀事，以及實際戰鬥經過的秒數不扣行程。正式活動在確認前顯示時段與條件；同一趟外出的往返、探索和交戰合併結算。失敗可重試，不重扣活動時段；撤退保留已投入時間。

三種出身為藥鋪學徒、驛站跑腿與戲班子弟。武功和門派不被出身鎖死；照嶺門與渡雲社根據準備成果與選拔表現提供機會，落榜也有「留鎮續修」的收束。

## 開發與劇本

- [遊戲企劃](https://github.com/cclodty/Game-develop-rpg-wusha/blob/9f6f18760e450b22e86b4f42e366905568a59971/docs/GAME_DESIGN.md)：範圍、行程、成長路線及驗收目標。
- [人物與故事工作稿](https://github.com/cclodty/Game-develop-rpg-wusha/blob/9f6f18760e450b22e86b4f42e366905568a59971/docs/STORY_BIBLE.md)：六名人物、三種出身、第一週事件。
- [編劇指南](https://github.com/cclodty/Game-develop-rpg-wusha/blob/9f6f18760e450b22e86b4f42e366905568a59971/docs/WRITING_GUIDE.md)：Dialogue Manager 劇本與試讀。
- [美術規範](https://github.com/cclodty/Game-develop-rpg-wusha/blob/9f6f18760e450b22e86b4f42e366905568a59971/docs/ART_DIRECTION.md)：統一 Q 版角色、場景與素材來源。

Godot 4.6.3 與 Dialogue Manager v3.10.4 已固定。素材載入、行走與即時戰鬥、七日規則、對話呈現分開維護。Scenario 是候選素材工具，本版不依賴其付費服務。

## 測試與匯出

```bash
bash tests/run_tests.sh
bash tools/export_web.sh
python3 tools/test_web.py
python3 tools/package_release.py
```

雲端環境先執行 `source /workspace/.godot-environment/activate.sh`。匯出腳本驗證官方 4.6.3 模板的 SHA-512，重用既有模板快取；第一次重建若沒有快取，會下載約 1.17 GiB 的官方多平台模板包。已下載的可玩包不需要重建。

瀏覽器測試需要 Python Playwright 與 Chromium，使用暫存網址與獨立瀏覽器資料，不碰玩家存檔。測試會檢查 WebGL 載入、真正輸入操作及存檔；實測結果另列於 `docs/VALIDATION.md`。

打包輸出在 `artifacts/release/`，包含 `jianghu-weiyuan-source.zip`、`jianghu-weiyuan-web.zip` 與 `SHA256SUMS.txt`。原始碼包排除匯入快取、匯出檔與測試產物，可玩包只包含 Web 檔案、啟動器與授權。

## 存檔與支援範圍

原生版本使用獨立的 `user://run-v1.json`，Windows 預設位於 `%APPDATA%/jianghu-weiyuan/`；瀏覽器版本使用該網站來源的 IndexedDB。請固定使用同一個瀏覽器與網址。清除網站資料會移除瀏覽器存檔。

本次以桌面鍵盤滑鼠、1440×900 橫向畫面和 Chromium 系瀏覽器為主要驗證範圍。手機、手把與 Safari 未列入本版實測承諾。第三方授權見 [素材與依賴來源](https://github.com/cclodty/Game-develop-rpg-wusha/blob/9f6f18760e450b22e86b4f42e366905568a59971/THIRD_PARTY_NOTICES.md)。

角色採統一 Q 版逐格動畫；目前是三分之四視角搭配左右翻轉，尚未製作獨立的八方向造型。門派修業、自由遊歷與江湖大事是後續企劃，並未包含於此試玩篇。
