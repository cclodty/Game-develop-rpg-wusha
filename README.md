# 江湖未遠｜小說與遊戲原型

本分支 `weiyuan-novel` 收錄六卷六十章的小說完整初稿（約21萬字，含標點）。

- **[小說入口與下載](novel/jianghu-weiyuan/README.md)**
- [直接閱讀完整正文](novel/jianghu-weiyuan/reading/jianghu-weiyuan.md)
- [Word可編修稿](novel/jianghu-weiyuan/reading/jianghu-weiyuan.docx)

本次新增僅為小說文字、設定與閱讀稿；未上傳本輪不採用的CG，未整合小說進遊戲。下方保留原武學原型的說明與既有資源。

---

## 原遊戲原型：內功與蓄勢

**從江湖經歷學武，以自己的配招決定怎樣交手。**

這個分支提供武學核心 v3：一種主兵器、一門常駐內功、十張招式牌，以真氣出招、以勢強化。新增三門內功、十二張驗證牌、留牌、普通／運勁選擇、三招的二選一精修與四類試戰對手。

以下為繼承自 `weiyuan-martial-core` 的原型說明及當時驗證紀錄：5,859項原生檢查及九組Chromium流程通過，最後兩行教學文字另經原生與瀏覽器補驗；完整範圍見 [VALIDATION.md](docs/VALIDATION.md)。[下載與開啟說明](https://github.com/cclodty/Game-develop-rpg-wusha/tree/weiyuan-martial-download)位於獨立 `weiyuan-martial-download`；既有[十八牌版](https://github.com/cclodty/Game-develop-rpg-wusha/tree/weiyuan-cards-download)及[即時動作版](https://github.com/cclodty/Game-develop-rpg-wusha/tree/weiyuan-download)保留。

## 兩個入口

- **武學試招：**直接選守中反擊／行雲變招／歸元爆發，與連擊、重甲、蓄勢或反制敵人比較。十二牌、三內功和三招精修開放調整，固定能力各5，獨立保存，不給正式旅程獎勵。
- **七日旅程：**姓名、三出身與六題〈抵達之前〉建角之後，走訪望溪鎮，安排練功、委託與探索。核心武學由固定師承取得，修橋與舊曲有本輪不同選修，學會後再自行換入牌組。

![三套內功牌組與四類對手的武學試招](docs/images/martial-hub.png)

## 怎樣交手

點選手牌與目標，再按「普通施展」或「運勁」；普通不耗勢，運勁消耗指定數量。每回合三真氣，勢最多三點、每輪最多獲得兩點，可跨回合保留。

回合末可留一張牌，下回合連同留牌補到五張。掠影步能換掉其他手牌，也可略過；換牌決定完成前不會繼續出招。用藥需一真氣、每場一次。敵人先公開意圖，閱讀與思考沒有倒數。

在鎮上或試招準備畫面可免費配招，開始活動後鎖定兵器、內功、牌組、精修與種子。學牌不會自動換牌；同次戰敗重試不重新扣時間或抽獎。

![真實瀏覽器中的普通施展、運勁與效果預覽](docs/images/martial-combat.png)

## 開啟與存檔

開發時用 Godot 4.6.3 標準版開啟 `project.godot`，等待匯入後按F5，或 `bash tools/run.sh`。Dialogue Manager 3.10.4 隨專案附上，不需.NET或Scenario。

下載Windows試玩ZIP後，先「全部解壓縮」，雙擊 `Play-Windows.cmd`，保留啟動視窗。macOS／Linux 執行 `python3 tools/serve_web.py`。新本機網址固定 `http://127.0.0.1:8072/`；不要直接雙擊 WebAssembly 的 `index.html`。

旅程存檔 `run-martial-v3.json`、試招 `lab-martial-v3.json`。兩者獨立，不讀寫舊 `run-cards-v2.json` 或 `run-v1.json`。瀏覽器存檔屬目前網站來源，使用同一瀏覽器與網址續玩；清除網站資料會移除存檔，沒有雲端同步。

## 文件與驗證

- [遊戲企劃](docs/GAME_DESIGN.md)：七日、角色、可靠學武來源、變動奇遇及結果。
- [核心卡牌設計與完整武學分類](docs/CARD_DESIGN.md)：十二牌、三內功、精修及示範配招。
- [序章樣稿](docs/PROLOGUE_SAMPLE.md)、[故事設定](docs/STORY_BIBLE.md)、[寫作指南](docs/WRITING_GUIDE.md)。
- [模型介面](docs/CARD_CONTRACT.md)、[整合合約](docs/BUILD_CONTRACT.md)、[美術與閱讀規格](docs/ART_DIRECTION.md)。
- [真人試玩流程](docs/PLAYTEST_PROTOCOL.md)、[當輪驗證記錄](docs/VALIDATION.md)、[v2歷史文件](docs/history/cards-v2/INDEX.md)。

三位首次玩家仍待招募／待測。普通卡戰2–4分鐘、序章6–8分鐘、首篇30–60分鐘都是待驗證目標。刀、指爪、長兵與醫毒的正式牌池仍是後續擴充，不因本輪已有分類藍圖便宣稱全部武學已製作。

公開檔案的HTTP下載校驗記錄見下載分支的 [validation/release.json](https://github.com/cclodty/Game-develop-rpg-wusha/blob/weiyuan-martial-download/validation/release.json)；本機ZIP附SHA256SUMS.txt。

第三方授權見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
