# 卡牌版整合合約：江湖未遠

適用 `weiyuan-card-prototype`，Godot 4.6.3 標準版，Dialogue Manager 3.10.4。本檔描述目前模組責任與接入；是否通過整合測試見 [VALIDATION.md](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/VALIDATION.md)。舊即時戰鬥合約保留於 [歷史文件](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/history/action-prototype/BUILD_CONTRACT.md)。

## 場景與責任

邏輯畫面 1440×900。`world.gd` 與新的 `card_arena.gd` 都是 Node2D，遊玩區 1080×640，由 main 放在 (28,136) 並裁切；不要自行新增全螢幕 HUD 或 Camera2D。main 持有選單、建角入口、對話、活動與存檔流程。模態畫面應關閉世界／戰鬥輸入，避免同一次點擊穿透。

| 模組 | 責任 | 不可代做 |
|---|---|---|
| `character_creation.gd` | 六題資料、六能力、微調驗證與回顧 | 寫檔、扣日程、發七日活動獎勵 |
| `creation_journey.gd` | 顯示問答／結果／回顧／微調；呼叫 run 的建角方法 | 私自保存另一份能力或跳過確認 |
| `run_state.gd` | 旅程交易、建角保存、已學牌／配招／精修、活動、結局 | 卡牌傷害或動畫時鐘 |
| `card_catalog.gd` | 唯一的 18 牌效果／精修／來源與牌面說明 | 隨機掉牌或直接更改旅程 |
| `card_battle.gd` | 純回合、敵意圖、抽洗牌、預覽與快照 | 場景、檔案、活動發獎 |
| `card_arena.gd`／`card_ui.gd` | 真實模型的操作與可讀回饋 | 另算傷害、改抽牌結果、跨層發獎 |
| `world.gd` | 城鎮與探索行走、人物／目標互動 | 推動日程或直接完成活動 |
| `first_week.dialogue` | 已確認活動的敘事、NPC 訪談與收束 | `do`、賦值或隱藏的獎勵副作用 |

## 共用識別碼

- 出身：`herbalist` 藥鋪學徒、`courier` 驛站跑腿、`performer` 戲班子弟。
- 屬性：`constitution` 根骨、`strength` 力道、`agility` 身法、`resolve` 定力、`aptitude` 悟性、`fortune` 機緣。
- NPC：`shen` 沈照嶺、`lu` 陸行雲、`tao` 陶半夏、`zhou` 周望山、`xiao` 蕭小滿、`lin` 林知微。
- 地點：`wangxi` 望溪鎮、`grove` 青篁溪谷、`ridge` 望風古道。
- 代表武學：`sword_qi` 破雲劍氣、`cloud_step` 掠影突進；兩 ID 同時可作已習得旗標，實際戰鬥使用是否配入對應牌。
- 去向：`zhaoling`、`duyun`、`stay`。出身、動機與低能力都不直接封鎖去向。

## 建角與旅程 API

`WeiyuanRun` 為 RefCounted，公開 `data: Dictionary`。

玩家建立新旅程應呼叫 `start_creation(hero_name, origin)`，進入 `phase="prologue"`；`new_run()` 保留預設已完成建角作為規則／測試初始化，不可拿來跳過真正玩家的六題流程。

建角方法為 `set_creation_answer(index, choice)`、`move_creation_point(from,to)`、`reset_creation_adjustments()`、`confirm_creation()`，回傳 `{ok,message}`。確認後轉 `intro`，再接 `arrival_morning` 的三出身翌晨故事。`creation_journey.configure(run)` 顯示共用 run，發出 `changed`／`confirmed`／`closed`，main 負責保存與路由。

既有行程入口保留：`day()`、`period()`、`remaining()`、`activity_status(id)`、`begin_activity(id)`、`complete_activity(outcome="success",detail={})`、`retreat_activity(detail={})`、`retry_activity()`、`prepare_exam_now()`、`begin_exam()`、`complete_exam(won,detail={})`、`choose_school(id)`、`buy_medicine()`。條件與獎勵來自 `WeiyuanData.ACTIVITIES`，卡牌來源來自 `WeiyuanCards.ACTIVITY_CARDS`。

新增 `set_deck(deck:Array)`、`upgrade_status(id)`、`upgrade_card(id)`；配招與精修只允許 `intro`／`town` 且 pending 為空。`upgrade_status` 提供 `ok/message/cost/discounted`，確認前要展示真實成本。`battle_stats()` 取得本次鎖定資料，不能由 UI 另組目前 live 配牌覆蓋它。

## 活動交易與新存檔

檔案為 `user://run-cards-v2.json`，外層 `{version:2,data:{...}}`，備援 `.bak`、原子寫入暫檔 `.tmp`。不讀寫舊 `run-v1.json`。讀檔驗證失敗可恢復上一份有效備援，但不能以靜默新遊戲取代錯誤。

旅程保留姓名、出身、日期時段、資源、武學、見識、人物信任、技能旗標、完成活動、紀事、pending、phase、選拔結果、去向、世界位置與對話斷點。新增：

| 欄位 | 內容 |
|---|---|
| `creation` | 內部版本 1；六答案、微調紀錄、目前頁／題與回看狀態 |
| `attributes` | 六項整數，完成後 2–8、總和 30；須與 creation 計算一致 |
| `learned_cards` | 合法、唯一的已學牌 ID |
| `deck` | 十張已學牌，每種最多兩張 |
| `upgraded_cards`／`mastery` | 已精修牌種與剩餘練習心得 |
| `aptitude_discount_used` | 首次悟性精修優惠是否用過 |
| `fortune_hint_used` | 首次機緣外出提示是否用過；開始外出時記錄 |

`begin_activity()` 建立唯一 token 並一次扣成本，鎖定 `attributes/deck/upgraded_cards/skills/training/insight/origin/exam_aid/seed` 與藥物額度。pending 可保存 `stage/visited/combat/world_position/report/battle_won`；主流程處理走到危險點、已完成觀察與戰後待結算等中斷邊界。

同次重試保留 token、種子與出發配置，只清掉本次戰場結果，不重新扣時／發藥。成功／撤退回報附 `pending_token`，藥物以 `medicine_used` 結算。重複或過期回報拒絕；活動完成後牌卡解鎖與心得只發一次。機緣提示不是新獎勵，不完成 `visited`，重試也不重設首次旗標。

## 行走與劇本

`world.configure(location,origin="herbalist",initial_position=Vector2(-1,-1))`、`set_objectives(Array)`、`set_input_enabled(bool)`、`get_player_position()`；信號 `npc_requested(id)`／`hotspot_requested(id)`／`exit_requested(destination)`。目標由 main 提供，不在 world 裡定義活動收益。

Dialogue Manager 新主入口為 `arrival_morning`（舊 `intro_<origin>`／`arrival` 保留相容），另有 `npc_<id>`、`activity_<id>`、操作活動的 `complete_<id>`、`exam_intro` 與三結局。`run.story_context()` 額外提供 `has_sword_qi`、`has_cloud_step`、`school`、`creation_motivation/approach/support/finish`；其餘明示鍵為 `hero_name/origin/day/remaining/training/insight`。不得任意讀未提供的存檔欄位。

一般訪談不扣時。故事／休息場景的 END 才結算已確認活動；任務／探索／戰鬥簡報 END 只啟動操作，成功收尾 END 才結算。固定可見 ID 與 `[#portrait=...]` 保留，詳見 [WRITING_GUIDE.md](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/WRITING_GUIDE.md)。

## 卡牌、素材與驗證入口

卡牌的精確函式與快照見 [CARD_CONTRACT.md](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/CARD_CONTRACT.md)，數值與意圖見 [CARD_DESIGN.md](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/CARD_DESIGN.md)。新卡牌場景取代 main 的即時戰鬥；舊 `arena.gd` 與動畫素材可保留作歷史參考，不能因舊測試過關就忽略新的回合套件。

本輪測試應覆蓋 `test_creation.gd`、`test_card_battle.gd`、卡牌視圖、卡牌 run-state 與新 UI 流程，再加上仍適用的故事、世界與存讀回歸。入口由本輪 `tests/run_tests.sh` 統一；最終實際執行數與 browser 證據只寫入 `VALIDATION.md`，本合約不預先宣告通過。

卡牌版預定交付 `artifacts/cards-release/jianghu-weiyuan-cards-{web,source}.zip`，本機 port 8071，另用 `weiyuan-cards-download`。舊下載分支、8070 與舊存檔保留；發布仍以實際測試、匯出與校驗完成為準。
