# 卡牌原型驗證記錄

測試日期：2026-10-23。分支：`weiyuan-card-prototype`。環境：Godot 4.6.3 標準版、Dialogue Manager 3.10.4、Linux 雲端。

## 原生模型與場景

新入口 `bash tests/run_tests.sh` 使用隔離的暫存使用者目錄，不碰玩家存檔。每套測試必須輸出明確完成計數；即使 Godot 退出碼為 0，只要出現 `SCRIPT ERROR`／`ERROR` 仍視為失敗。

| 套件 | 最新通過數 | 覆蓋範圍 |
|---|---:|---|
| `test_run_state.gd` | 562 | 原有七日時段、活動、門派、獎勵、重試與原子存讀回歸，已接卡牌狀態 |
| `test_creation.gd` | 1,564 | 六題／十八選項、能力分配公平性、總和30、2–8範圍、最多兩點轉移、回顧／改選／保存與能力說明 |
| `test_card_battle.gd` | 641 | 十八牌基本／精修、首張加成、群攻與多段、起手換牌、狀態、防護、洗牌與除外、五模式、精確預覽／RNG／快照與損壞資料 |
| `test_card_run.gd` | 469 | 活動解鎖、免費配牌、心得與牌種精修、一次悟性／機緣便利、鎖定牌組與種子、七日路線、卡牌旅程存讀 |
| `test_card_arena.gd` | 46 | 實際卡牌視圖的按鈕、目標、起手、分頁、規則／牌堆、暫停、恢復及結果信號 |
| `test_world.gd` | 104 | 沿用城鎮／探索的碰撞、目標、人物、行走動畫與暫停 |
| `test_story.gd` | 67 | 正式 Dialogue Manager 編譯、出身／日數／建角回應、可達標題與出口、固定 ID、禁止劇本副作用 |
| `test_card_ui.gd` | 254 | 三出身實際場景流程、六題與回顧存讀、配牌、合法卡戰勝出、成本／結算、門派結果呈現、正文／能力標題／長姓名版面 |

最新各套件合計 **3,707 項自動化檢查通過**。這是斷言數，不是3,707位玩家，也不是同一份執行日誌的單次計數。`artifacts/cards-validation/native.log` 記錄完整套件當時的 UI 214 項；最後文字可見性與版面修正後，UI 單獨回歸至 254 項，記錄在 `native-ui-final.log`。計算合計時使用後者取代214，不將兩次UI相加。

沒有腳本或引擎錯誤。隨附 Dialogue Manager 測試場景會有 UID 失效後改用檔案路徑的警告；不影響正式劇本編譯與本輪測試結果。

原生 UI 測試按真正場景按鈕，卡戰使用合法卡牌／結束回合操作。門派邀請與結局呈現使用明示的資格資料 fixture；兩條路線能否在七日內以真實活動成本達成，由 `test_card_run.gd` 另行驗證。這些測試不等同陌生玩家自行找到路線。

## 真正瀏覽器回歸

新增 `tools/test_cards_web.py`，保留舊動作版 `test_web.py`。在1440×900的真正 Chromium／WebGL 2 完成 **7 組流程，無引擎或瀏覽器錯誤**。腳本使用隨機 loopback 網址與獨立瀏覽器 context，只讀取 IndexedDB 核對 `run-cards-v2.json`，不注入能力、卡牌、獎勵或敵人氣血。

| 真實操作流程 | 核對結果 |
|---|---|
| 藥鋪學徒第三題回應中保存、離開、重新載入 | 答案、頁面與回應階段精確恢復 |
| 藥鋪學徒完成六題、微調、翌晨、WASD行走 | 總和30且每項2–8，入鎮仍有21時段，位置保存 |
| 角色與配招 | 9張牌不能套用；成功以1張隨身藥敷取代1張出劍，維持10張且不耗時 |
| 練習卡戰 | 起手換牌、暫停凍結、保存離開後精確恢復；合法出牌／結束回合勝出，僅扣1時段、結算1次 |
| 驛站跑腿完成建角、微調、翌晨與行走 | 專屬出身與能力保存，免費行走不推進行程 |
| 戲班子弟能力回顧中保存、離開、重新載入 | 六題答案、回顧頁與微調精確恢復 |
| 戲班子弟完成建角、翌晨與行走 | 專屬出身與能力保存，免費行走不推進行程 |

正文、六能力標題／數值、長選項、配招列表、起手牌／意圖與戲班回讀畫面已以實際截圖檢視。工具保留三出身的原始瀏覽器錄影；腳本快速閱讀與操作的秒數不作為6–8分鐘真人時長證據。姓名使用逐鍵 ASCII 輸入，中文輸入法仍未驗證。

本地完整結果為 `artifacts/cards-validation/web/result.json`，執行日誌為 `artifacts/cards-validation/web.log`。公開下載分支另附 [web-result.json](https://github.com/cclodty/Game-develop-rpg-wusha/blob/weiyuan-cards-download/validation/web-result.json)、[native.log](https://github.com/cclodty/Game-develop-rpg-wusha/blob/weiyuan-cards-download/validation/native.log)及[native-ui-final.log](https://github.com/cclodty/Game-develop-rpg-wusha/blob/weiyuan-cards-download/validation/native-ui-final.log)。README三張預覽直接複製自這次瀏覽器輸出。

測試開始與結束核對同一組匯出檔案雜湊；`index.pck` SHA-256 為 `16842492f325f6f0beaebe27f13027fdb6e4338e3314ba066f793e8c76546325`，`index.html` 為 `2b7cf3057b89916576207e0b310adf666379376f4bcbab6223512d1efacc8ce8`。JS／WASM完整雜湊也在結果JSON內。

## 工具與交付邊界

新包裝輸出改為 `artifacts/cards-release/jianghu-weiyuan-cards-{web,source}.zip`，啟動器固定8071，排除兩版存檔與暫檔。Python 工具通過語法檢查；CMD 保持 ASCII、CRLF 與引號包住的相對路徑，Python／PowerShell 預設埠均已核對。沒有把舊Windows啟動器的36項檢查重新計作本輪原生Windows驗收。

本輪匯出記錄在 `artifacts/cards-validation/export.log`，仍使用經SHA-512核對的官方4.6.3模板。既有 `weiyuan-download` 保留動作原型，卡牌版使用獨立 [weiyuan-cards-download](https://github.com/cclodty/Game-develop-rpg-wusha/tree/weiyuan-cards-download)。

## 歷史與真人驗證

動作原型 `9f6f187` 的 **8,013 項檢查**、動畫圖鑑、錄影及舊瀏覽器流程保留於 [歷史驗證記錄](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/history/action-prototype/VALIDATION.md)，不列入本輪卡牌通過數。

序章6–8分鐘與首篇30–60分鐘均為設計目標。動機、能力理解、敵意圖閱讀、時間取捨與重玩價值仍需首次玩家證明。[PLAYTEST_PROTOCOL.md](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/PLAYTEST_PROTOCOL.md) 與三份空白記錄已備妥，**三位全部待招募／待測，尚無真人結果**。

真正Windows桌面、中文輸入法、Safari、手機與手把未完成本輪實機驗收。可玩程式、模型通關或腳本按完選項，均不代表商業品質或真人時長已達標。
