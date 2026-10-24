# 內功與蓄勢版整合合約

適用 `weiyuan-martial-core`，Godot 4.6.3 標準版、Dialogue Manager 3.10.4。本文件說明實際模組責任；測試結果見 [VALIDATION.md](VALIDATION.md)。[卡牌 v2](history/cards-v2/BUILD_CONTRACT.md) 與 [動作版](history/action-prototype/BUILD_CONTRACT.md) 保留為歷史。

## 場景與責任

邏輯畫面1440×900，`world.gd` 與 `card_arena.gd` 的遊玩區為1080×640，由 main 放在(28,136)並裁切。main 管理入口、建角、試招、對話、活動、暫停與保存；模態畫面關閉世界／戰鬥輸入，不能同次點擊穿透。

| 模組 | 責任 |
|---|---|
| `character_creation.gd`／`creation_journey.gd` | 六題、能力及微調的單一計算／顯示；不發七日獎勵 |
| `run_state.gd` | journey/lab分流、建角、已學招式／內功、配招／精修、變動奇遇、活動交易與保存 |
| `game_data.gd` | 活動成本與收益、人物／地點、奇遇候選與對手線索 |
| `card_catalog.gd` | 唯一十二招／三內功／三示範組合及固定授招來源 |
| `card_battle.gd` | 純回合、資源、意圖、亂數、效果預覽、戰鬥快照；不操作檔案 |
| `card_arena.gd`／`card_ui.gd` | 真正模型的操作與讀取回饋；不另算傷害或發獎 |
| `world.gd` | 行走、人物與目標互動；不推日程 |
| `first_week.dialogue` | 已確認活動的敘事與訪談；無賦值或獎勵副作用 |

## 共用識別碼

出身是 `herbalist/courier/performer`，能力為 `constitution/strength/agility/resolve/aptitude/fortune`。人物 `shen/lu/tao/zhou/xiao/lin`；地點 `wangxi/grove/ridge`；去向 `zhaoling/duyun/stay`。代表招式 `sword_qi` 是破雲劍氣，`cloud_step` 現為掠影步。已學旗標不表示已配入，也不等於加入某派。

內功 `shouzhong/xingyun/guiyuan`，兵器 `sword/saber/polearm/unarmed`；驗證池只有三張劍限定招，其餘可混搭，刀與長兵選項不代表已有其專屬牌池。試招對手為 `flurry/armored/charging/counter`，旅程保留 `practice/spar/grove/ridge/exam`。

## 旅程、試招與配招 API

`WeiyuanRun` 為 RefCounted，公開 `data`。正式玩家呼叫 `start_creation(hero_name,origin,journey_seed=0)`，六題 `set_creation_answer`、移點 `move_creation_point`／`reset_creation_adjustments`、`confirm_creation` 完成後由 prologue→intro，再播 `arrival_morning`。`new_run()` 只作預設建角的規則／測試初始化，不能繞過玩家流程。

行程入口保留 `day/period/remaining/activity_status/begin_activity/complete_activity/retreat_activity/retry_activity/prepare_exam_now/begin_exam/complete_exam/choose_school/buy_medicine`。`activity_preview(id)` 在扣時前返回本輪奇遇、已學時的心得替代獎勵與沿途對手提示。

配招以 `set_loadout(deck,weapon,inner)` 原子驗證三者；相容入口 `set_deck(deck)` 保留。`upgrade_status(id)` 提供費用及首次悟性折扣；`upgrade_card(id,branch="stable")` 花心得解鎖，`set_refinement(id,branch)` 在已解鎖的穩定／專精練法間免費切換。只允許 intro/town、pending空時更改；同名兩張共用分支。試招允許清空分支以回到未精修基準。

`new_lab(preset="shouzhong")` 直接建立獨立試招：六能力各5、全十二招、三內功、三項精修已解鎖但未選分支、藥物1。`apply_lab_preset(id)` 重設對應牌組並清已選精修；`begin_trial(enemy,seed)` 建立零時段試招 pending。完成／撤退回試招準備，不發正式旅程資源或學武獎勵。既有旅程檔保留，不讓試招當作第八日或跨輪成長。

## 保存與活動交易

外層 `{version:3,data:{...}}`。旅程 `user://run-martial-v3.json`，試招 `user://lab-martial-v3.json`；`current_save_path()` 根據 mode 選擇。`save_game(path="")` 預設保存目前模式；`load_game()` 預設載入旅程，試招續玩須明確傳 LAB_SAVE_PATH。備援 `.bak`、原子寫入 `.tmp`；不讀寫舊 `run-cards-v2.json` 或 `run-v1.json`。失敗報錯，不能靜默開新局。

保留姓名、日期、資源、關係、事件、世界位置與對話斷點；v3資料重點如下：

| 欄位 | 內容 |
|---|---|
| `mode` | `journey/lab`，不能互相當成續玩檔 |
| `creation/attributes` | 六題與微調，六能力需與建角重算一致、總額30 |
| `learned_cards/learned_inners` | 已學唯一ID，初始普通招式加收勢、歸元功 |
| `deck/weapon/inner` | 十張合法牌與當前裝備 |
| `upgraded_cards/refinements/mastery` | 已解鎖精修、各牌目前分支及心得 |
| `aptitude_discount_used/fortune_hint_used` | 首次便利旗標，讀檔不重發 |
| `journey_seed/opportunities/encounter_variants` | 新局確定的奇遇與探索對手；重試不重抽 |
| `pending` | 活動token、成本、階段、鎖定配置、觀察目標、世界位置與戰鬥快照 |

`begin_activity()` 一次扣時及必要費用，鎖定 attributes/deck/weapon/inner/refinements/upgraded_cards/skills/training/insight/origin/exam_aid/seed、藥物額度與對手變體。`battle_stats()` 只回鎖定配置；活動途中改 live 欄位也不能影響已出發戰鬥。

成功／撤退報告須帶 pending_token，藥物以 medicine_used 統一扣除。過期或重複回報拒絕，招式、內功、心得及信任只發一次。重試保留原token、出發種子與配置，不重扣時。奇遇核心不隨機：修橋只追加推碑／卸力其中一種，舊曲只追加掠影／伏針其中一種；固定師承仍能取得所有核心牌。已學追加牌改心得1，確認前明示。

## 劇本與行走

`world.configure(location,origin,initial_position)`、`set_objectives`、`set_input_enabled`、`get_player_position`；信號 `npc_requested/hotspot_requested/exit_requested` 交給 main 路由。世界不持有收益規則。

主劇本入口 `arrival_morning`，另有 `npc_<id>`、`activity_<id>`、操作後 `complete_<id>`、`exam_intro` 及三結局。舊 `intro_<origin>/arrival` 保留相容與固定ID。`story_context()` 提供姓名、出身、day/remaining/training/insight、has_sword_qi/has_cloud_step、school、四項creation回應標記，另有 `activity_variant/variant_title/variant_text`；沒有pending時後三者為空。

普通訪談不扣時。故事／休息的 END 結算已確認活動；操作型簡報 END 只啟動行走／戰鬥，成功收尾 END 才發獎。Dialogue Manager 文字保持唯讀，ID與畫像標籤穩定；完整寫作規則見 [WRITING_GUIDE.md](WRITING_GUIDE.md)。

## 交付與驗證

卡牌模型及視圖細節見 [CARD_CONTRACT.md](CARD_CONTRACT.md)。測試入口 `bash tests/run_tests.sh`，涵蓋建角、牌目錄、模型、場景、run、故事、世界與UI；真實瀏覽器以 `tools/test_martial_web.py` 操作，不能用存檔注入代替玩家可走通的路徑。實際通過數與限制只寫入驗證報告。

新版交付 `artifacts/martial-release/jianghu-weiyuan-martial-{web,source}.zip`，固定本機port8072，來源分支 `weiyuan-martial-core`、下載分支 `weiyuan-martial-download`。包裝器拒絕100MiB以上單包，附SHA256、授權與啟動說明，排除所有版本的旅程／試招存檔及備份。舊卡牌8071／下載分支與動作8070／下載分支保留；發布完成與否以README及校驗檔為準。
