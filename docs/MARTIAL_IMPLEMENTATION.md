# 武學核心 v3 整合約定

本輪依使用者核准的「內功、蓄勢與武學混搭」計畫實作。分支 weiyuan-martial-core；保留 fc1e2ae 的卡牌 v2 分支與下載。這是開發接線約定，玩家規則另見 CARD_DESIGN.md。

## 責任與資料名稱

- catalog owner：scripts/card_catalog.gd、tests/test_martial_catalog.gd。
- battle owner：scripts/card_battle.gd、tests/test_card_battle.gd。
- run owner：scripts/run_state.gd、scripts/game_data.gd、tests/test_card_run.gd、tests/test_run_state.gd。
- arena owner：scripts/card_arena.gd、scripts/card_ui.gd、tests/test_card_arena.gd。
- root：scripts/main.gd、project.godot、export_presets.cfg、tests/run_tests.sh、發布。
- integration owner：tests/test_card_ui.gd、tools/test_martial_web.py。
- delivery owner：其他 docs、README、story/first_week.dialogue、tests/test_story.gd、包裝／啟動工具。

十二牌 ID：strike / guard / breath / observe / cloud_step（掠影步）/ opening_thrust / sword_qi / pushing_palm / yielding_palm / probing_stone / hidden_needle / gather_momentum。

內功 ID：shouzhong（守中訣）、xingyun（行雲訣）、guiyuan（歸元功）。兵器 ID：sword / saber / polearm / unarmed。招路 type：attack / guard / change。精修分支：stable / specialist。

## Catalog

保留 class_name WeiyuanCards；CARDS 恰為十二牌；新增 INNERS、WEAPONS、PRESETS（shouzhong/xingyun/guiyuan，含 name/description/deck/weapon/inner）。REFINABLE 為 opening_thrust/cloud_step/sword_qi。

card(id, refinement: Variant="", empowered=false) 回傳深拷貝，保留 id/name/type/group/cost/target/description/upgraded。新增 weapon（any 或指定）、discipline、refinement、boost_cost、momentum_cost、empowered、normal_description、boost_description。empowered=true 時直接回傳已合併的傷害等效果；momentum_cost=boost_cost，普通為0。bool true 的 refinement 可暫視為 stable 供既有呼叫相容，正式 run/main 用字串分支。

主要效果鍵：damage、block、draw、energy、exhaust、strip_block、guard_bonus、cycle_limit、delayed_damage、retaliation、momentum_gain。正常/運勁與三種精修數值完全依用戶表格。

validate_deck(deck, learned, weapon="sword") 驗證十張/最多兩張/已學/兵器；starting_deck 為 strike/guard/breath/observe/probing_stone 各二張。starting_learned 為這五牌加 gather_momentum（所有出身相同，出身保留物資與手藝收益）。初始兵器 sword，內功 guiyuan。

保證學習來源：sword_lesson→sword_qi+opening_thrust，並學 shouzhong；practice→pushing_palm；spar→yielding_palm；ridge_tracks→cloud_step，並學 xingyun；hermit_visit→hidden_needle。保留 cards_for_activity，新增 inners_for_activity。不以隨機奇遇取代這些來源。

## 純 Battle

保留 configure/status/snapshot/report/validate_snapshot 與舊 status aliases energy/medicine_left 等。快照 VERSION=2。stats 新增 weapon、inner、refinements（card ID→stable/specialist）；refinements 才是實際效果依據。新增 encounter_variant（空或 flurry/armored/charging/counter），行程層出發鎖定。

play_card(hand_index,target_index=0,empowered=false) 先驗證與支付。預覽 preview_card 使用相同參數及同一克隆模型，不改真實狀態、不洩露牌堆內容。

掠影步先扣費、從手牌移入 in_play、結算防護，再進 phase="choice"、pending_choice={kind:"cycle",max_count:1或2,...}。resolve_choice(indices:Array) 允許零張略過；選的是移除出牌後的手牌索引。棄指定牌後抽等量，完成內功回報，最後將 in_play 移入棄牌。不得抽回正在施展的牌。所有中間狀態須驗證及可存讀。

end_turn(retain_index=-1) 可留一張；其餘棄掉。回合末歸元如有真氣，扣1、獲1勢（即使已滿勢也不改其他資源；UI顯示規則）。敵人行動後，下一玩家回合清防護/反擊、重設3真氣與當輪旗標，處理到期伏針，再補至五張。保留牌不算新抽牌。

勢開場0、上限3；momentum_gained 當輪最多2，在玩家回合開始重設。以實際進入勢池的數量計額度，已滿不算額度；結束戰鬥清勢。守中：敵方回合首次實際吸傷，得1勢；每實付1勢在該牌效果後得2防護。行雲：只記實付真氣>0的相鄰牌 type，首次異類得1勢，0費不更新；首次實際耗勢牌效果後抽1。歸元：單張攻牌實付3勢時，整張加8傷害一次（在傷害結算內反映，不能打完再補第二次）。

反擊：防護實際吸收一段攻擊且玩家存活時，對該敵造成準備值，敵方回合最多一次；準備多次取max不累加。反擊殺死敵人則取消該敵剩餘段數。力道不加反擊/延遲；身法只加本回合首張提供防護的牌，不加內功的防護回報。

敵人反制為當前公開 intent 的 counter_damage：玩家直接 attack 牌結算及內功回報後，若該敵尚活且本玩家回合未反制，回擊一次（可被玩家防護抵消）；不觸發玩家反擊或守中產勢。被直接攻擊但傷害全被護住仍會反制。變招/延遲不觸發反制。

用藥：1真氣、每場一次、回復20，全滿拒絕不扣費。敵意圖在玩家回合開始固定；只有下一回合才切頭目半血階段。預覽包含反制風險、產勢/耗勢、延遲與待選牌資訊。

支援模式：practice/spar/grove/ridge/exam，加獨立 flurry/armored/charging/counter 四模式。保留敵人kind供既有Q版圖集使用；意圖需提供 damage/hits/block/counter_damage 及可讀名稱。四試戰可調初始數值，但不得靠修改用戶十二牌數值或隱藏作弊保證勝出。

## Run / Lab

旅程存檔 user://run-martial-v3.json，試招 user://lab-martial-v3.json；外層 SAVE_VERSION=3，舊 v1/v2 不讀寫。data.mode 為 journey/lab；其他 phase 繼續沿用現有流程。

新增 data.weapon、inner、learned_inners、refinements；upgraded_cards 保留作已付費解鎖精修的三張 ID，解鎖後可免費切 stable/specialist。set_loadout(deck,weapon,inner) 原子驗證後更新；set_deck 保留；upgrade_card(id,branch="stable") 與 set_refinement(id,branch)；upgrade_status 只允許三種精修牌。pending 鎖定 weapon/inner/refinements/encounter_variant。

new_lab(preset_id="shouzhong") 建立 mode=lab、phase=town，姓名「試招行者」、三出身無關固定能力各5（合法 creation answers=[0,0,2,1,2,2]）、全部十二牌與三內功可用；三種精修已解鎖但初始 refinements 為空，試招可選未精修或分支。各preset實際十張牌依用戶表。藥一份，沒有行程扣時或旅程獎勵；日誌可記試戰結果但不可灌入正式旅程。

begin_trial(enemy_mode,seed=固定可重現正整數) 建立 pending.id="trial"、battle_mode=四模式之一，cost/fee=0、stage=combat；其餘鎖定/種子/token/重試同活動。complete_activity/retreat_activity 在lab trial只結算試招並返回town，不發正式獎勵。apply_lab_preset(id) 僅lab且pending空時套用三範例之一，清refinements還原基準。save_game/load_game 依mode分流，load預設仍為正式SAVE_PATH，root明示LAB_SAVE_PATH。

變動奇遇以開局seed決定、保存且載入驗證：至少兩個既有可選支線提供變動授招/支援，付時段前可讀 activity_preview(id)={text,...}；已學重複牌時改給1心得並提前明示。固定學武來源不受影響。遭遇變體也在開局決定，在pending鎖定，同次重試不重抽。可加入 story_context 的 activity_variant/variant_title/variant_text 供無副作用劇本回應。

## Arena 與 root

保留1080×640與原信號。改為點牌選中後，明確「普通施展／運勁」按鈕，顯示成本/模型預覽；不能點到牌就偷偷運勁。提供 select_card/select_target、play_selected(empowered=false)、toggle_retain(index)、confirm_cycle(indices)、end_turn() 等可測入口；phase=choice時顯示待選手牌與確認/略過，禁止出別牌/結束回合。可保留一張以標記；出牌後無效索引須清掉。_view 保存所有選擇、運勁/留牌/棄牌面板狀態。

root 在標題提供「武學試招」與獨立續玩；lab hub可選三預設/四敵人、開啟同一角色配招介面（兵器/內功/精修），正式旅程也能配招。所有存檔、返回、戰敗重試與撤退必須按mode分流。實際世界/劇情不提供lab全牌特權。

## 交付

新增獨立下載分支 weiyuan-martial-download，包名 jianghu-weiyuan-martial-{web,source}.zip，輸出 artifacts/martial-release，本機port8072。不覆蓋舊 weiyuan-cards-download、weiyuan-download、playable-download。

原生規則/實際UI/真Chromium均需當輪驗證與實圖檢查。三名首次玩家尚待真人安排，不以自動化結果宣稱已完成理解度/時長驗收。
