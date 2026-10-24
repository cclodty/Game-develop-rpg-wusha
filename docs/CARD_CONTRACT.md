# 內功與蓄勢：卡牌模型及場景介面

適用 `weiyuan-martial-core`。規則數值見 [CARD_DESIGN.md](CARD_DESIGN.md)，流程接線見 [BUILD_CONTRACT.md](BUILD_CONTRACT.md)。外層存檔版本為 3、戰鬥模型快照版本為 2；不接收舊卡牌版或即時戰鬥快照。[舊版介面](history/cards-v2/CARD_CONTRACT.md) 只供查閱。

## 單一牌目錄：WeiyuanCards

`card_catalog.gd` 是 RefCounted 靜態資料源。`CARDS` 收錄十二招，`WEAPONS`／`INNERS`／`PRESETS`／`DISCIPLINES` 分別提供兵器、三門內功、三套示範與武學分類；後四類藍圖不等於已有可玩的完整卡池。

| API | 用途 |
|---|---|
| `has(id)` | 查合法招式 ID |
| `starting_deck()` | 出劍、架勢、調息、審勢、飛石問路各兩張 |
| `starting_learned(origin)` | 上述五招及收勢；三出身相同，背景便利由旅程層處理 |
| `cards_for_activity(id)`／`inners_for_activity(id)` | 固定師承的招式／內功來源；不是隨機掉落 |
| `validate_deck(deck, learned, weapon="sword")` | 檢查十張、已學、同名至多兩張及兵器需求，回 `{ok,message}` |
| `card(id, refinement="", empowered=false)` | 深拷貝已合併分支與普通／運勁模式的效果 |
| `refinement_description(id, branch)` | 指定精修分支說明 |

類型是 `attack/guard/change`，顯示為攻／守／變；兵器需求和類型獨立。`refinement` 為空字串或 `stable/specialist`，只有 `opening_thrust/cloud_step/sword_qi` 可精修。舊布林參數相容僅用於內部轉接，不表示可以讀取舊版牌組。

牌資料含 `id/name/type/group/cost/target/description/upgraded`、`weapon/discipline/refinement/boost_cost/momentum_cost/empowered/normal_description/boost_description`。效果鍵為 `damage/block/draw/energy/exhaust/strip_block/guard_bonus/cycle_limit/delayed_damage/retaliation/momentum_gain`。普通、運勁和精修的牌面讀同一資料；實際預覽由模型計算，UI 不另寫傷害公式。

## 純回合模型：WeiyuanCardBattle

`card_battle.gd` 不含場景、秒鐘或檔案操作。`configure(mode,stats,restore={})` 成功回 `{ok:true,message,events}`；不合法 stats 或快照明確失敗，不自動開新戰鬥取代。

mode 為旅程 `practice/spar/grove/ridge/exam` 或試招 `flurry/armored/charging/counter`。stats 包含六能力（整數 2–8、總額30）、十張 deck、origin、weapon、inner、refinements、medicine、seed、exam_aid；已學權限和精修解鎖由 run 先檢查。種子是可精確保存的31位整數。`encounter_variant` 由旅程在出發時鎖定，不能重試時重抽。

| 方法 | 行為 |
|---|---|
| `skip_mulligan()`／`mulligan(indices)` | 每場一次換起手；索引不可重複或超過定力上限，先抽新牌再洗回舊牌 |
| `play_card(hand_index,target_index=0,empowered=false)` | 重新驗證階段、目標、真氣和勢；先支付，再結算招式與內功 |
| `resolve_choice(indices)` | 掠影步已支付後，選擇零至上限張其他手牌換掉，完成剩餘結算 |
| `preview_card(hand_index,target_index=0,empowered=false)` | 在深拷貝上執行同規則；不改原資料或 RNG，不洩露待抽牌名 |
| `end_turn(retain_index=-1)` | 可留一張、棄其餘；歸元回報、敵方行動、下回合清防護及延遲效果、補至五張 |
| `use_medicine()` | 消耗一真氣和一份藥，本場至多一次、回復20；滿血或無資源拒絕 |
| `status()` | 狀態深拷貝及 ready/resolved/won、牌堆數量、操作旗標 |
| `snapshot()`／`report()` | 完整可保存狀態／戰鬥結算紀錄 |
| `validate_snapshot(saved,mode="",stats={})` | 檢查版本、守恆、固定出發配置、種子、階段及中間狀態 |

phase 是 `mulligan/player/choice/won/lost`。敵回合在 `end_turn()` 內結算；選牌中的 `choice` 可讀檔恢復，此時不能再出牌、用藥或結束回合。出牌暫存 `in_play`，待結算完才進棄牌／除外堆，因此換牌或洗牌不能抽回正在施展的同一張牌。`amount` 與 `hp_loss` 分別是穿過防護的傷害及實際扣血，不能把溢傷當作多扣血。

勢為0–3，每輪實得至多2；滿勢未獲得的部分不占額度。付費牌才更新行雲的相鄰招路，零費牌不打斷或推進判定。當輪產勢額度、內功觸發旗標、首張攻／防加成、反擊準備與已反擊狀態皆由模型維護。伏針延後結算不再支付／產生耗勢回報；力道也不套用於伏針或反擊。

玩家反擊在敵方攻擊確實被防護吸收且主角存活後檢查，一個敵方回合至多一次，重複準備取高值。敵方反制則是玩家直接攻牌完整結算後、敵仍活著時每玩家回合一次；不能連鎖觸發玩家反擊或守中產勢。擊殺、連擊中斷及反制的精確順序見規則文件和模型測試。

快照保存固定 stats、seed/rng_state、turn/phase、hp/max_hp/block/qi、hand/draw_pile/discard_pile/exhaust_pile/in_play、enemies/intent、momentum、當輪上限與內功旗標、保留後的hand、pending_choice、delayed、反擊與用藥狀態、起手及首張加成旗標、統計與事件。JSON 的整數型浮點可正規化；NaN、無限值、變造牌張或不一致階段必須失敗。

## 真實模型視圖：WeiyuanCardArena

場景為1080×640的 Node2D，公開 `battle/action_buttons/restore_error/selected_card/selected_target/mulligan_selection/retained_index/cycle_selection`。主要入口為 `configure/set_input_enabled/snapshot/status/report/view_state`；信號為 `finished(won,report)`、`status_changed(value)`、`changed`。視圖只呈現事件，不發旅程獎勵。

操作為 `select_card(index)`、`select_target(index)`、`play_selected(empowered=false)`、`toggle_retain(index)`、`confirm_cycle(indices=[])`、`confirm_mulligan()`、`skip_mulligan()`、`end_turn()`、`use_medicine()`、`cancel_selection()`、`open_panel(kind)`、`close_panel()`。

玩家階段點牌只選取，再明確按普通施展或運勁；點敵只改目標。留牌獨立標記，不會自動把最後點的牌留下。`choice` 階段點其他手牌勾選換出，按確認或略過；起手階段則勾選起手換牌。每頁五張，額外抽牌可翻頁。規則／牌堆面板阻止出牌，關閉後保留原選擇。

場景快照在模型上加 `_view`：`selected_card/selected_target/mulligan_selection/retained_index/cycle_selection/page/panel/pile_tab`。傳入模型前移除；不合法視覺索引可限制／清除，不可用視覺資料改戰局。模型驗證失敗顯示 `restore_error` 並禁止操作。

短位移、劍痕與色閃只重現已結算效果。暫停凍結演出；generation guard 和單次發送旗標避免舊回呼或重複刷新再次發 `finished`。`advance_presentation(delta)` 是演出測試入口，不能推動回合。

## Run、保存與驗證

以 `run.battle_stats()` 的出發快照配置戰鬥，以 `pending.combat` 恢復；每次 changed 及暫停／離開前保存，包括換牌未確認與留牌標記。重試保留活動 token、seed、兵器、內功、精修與牌組，只清當次戰場，不再扣時。

旅程 `run-martial-v3.json`、試招 `lab-martial-v3.json` 分開，包裝器排除兩者、舊 v1/v2、備援及暫檔。程式檢查需覆蓋三內功、十二牌／三分支、留牌、選牌中間狀態、零費洗牌循環、預覽無副作用、四種對手及旅程模式；整合確認來源、鎖定、種子與一次結算。真實執行紀錄見 [VALIDATION.md](VALIDATION.md)，三位首次玩家另依 [PLAYTEST_PROTOCOL.md](PLAYTEST_PROTOCOL.md) 記錄。
