# 卡牌模型與場景介面

此檔依目前 `card_catalog.gd`、`card_battle.gd`、`card_arena.gd` 及 `run_state.gd` 編寫。對外文字與數值見 [CARD_DESIGN.md](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/CARD_DESIGN.md)，整體接線見 [BUILD_CONTRACT.md](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/BUILD_CONTRACT.md)。不要將動作版快照傳給此模型。

## 卡牌目錄：WeiyuanCards

`card_catalog.gd` 為 RefCounted 的靜態資料來源：

| API | 回傳／用途 |
|---|---|
| `has(id)` | 合法牌 ID |
| `starting_deck()` | 五基本牌各兩張的十張 Array |
| `starting_learned(origin)` | 五基本牌＋該出身一張；只是已學列表 |
| `cards_for_activity(id)` | 活動成功後新學牌的候選 ID，run 去除已學重複 |
| `validate_deck(deck,learned)` | `{ok,message}`；恰好十張、已學、同種最多兩張 |
| `card(id,upgraded=false)` | 深拷貝效果、id/name/type/group/cost/target/upgraded/description |

類型為 `attack`／`skill`；target 為 `self`／`enemy`／`all_enemies`。精修替換同 ID 的指定效果值，不產生第十九種牌。牌面與 tooltip 要讀這份資料；正式預覽再由戰鬥模型計算，不在 UI 重寫公式。

## 純回合模型：WeiyuanCardBattle

`card_battle.gd` 不含 Node、輸入、秒鐘或檔案操作。

`configure(mode,stats,restore={}) -> Dictionary`：mode 為 `practice/spar/grove/ridge/exam`。成功回 `{ok:true,message,events:[]}`，非法 stats／快照回 `{ok:false,message,events:[]}`；不以新局代替損壞 restore。

`stats` 必需 `attributes`（六整數 2–8、總和30）、`deck`（十張合法牌）與 `origin`；其餘為 `upgraded_cards`、`medicine`、`seed`、`exam_aid`。seed 是可在 JSON 精確保存的 31 位整數，exam_aid 0–3。run 傳入的 training／insight／skills 是旅程相容資訊，不參與 `_fixed_stats()` 傷害計算。已學牌的權限由 run 驗證，模型只驗牌目錄及配置合法性。

| 方法 | 行為 |
|---|---|
| `skip_mulligan()` | 開場直接進玩家回合，消耗每場一次換牌機會 |
| `mulligan(indices:Array)` | 選定手牌索引去重／範圍／定力上限檢查；新牌先從剩餘牌堆抽，舊牌再放回洗牌 |
| `play_card(hand_index,target_index=0)` | 檢查 phase、費用與合法活目標，扣資源並產出事件 |
| `preview_card(hand_index,target_index=0)` | 用深拷貝執行同一模型，回實際扣血／防護／治療及 `can_play`；不改原資料或 RNG，不洩露將抽到哪張牌 |
| `use_medicine()` | 每回合一次、消耗一份、回復20且不溢出；全滿或無藥拒絕 |
| `end_turn()` | 棄手牌、敵依意圖行動、狀態衰減、建立下一玩家回合 |
| `status()` | 深拷貝狀態，加 ready/resolved/won、energy、medicine_left、牌堆數量、可操作旗標 |
| `snapshot()` | 可 JSON round-trip 的完整模型狀態 |
| `report()` | medicine_used/hits/damage_taken/turns/mode/won/seed/cards_played |
| `validate_snapshot(saved,mode="",stats={})` | 驗證版本、數值、牌張守恆、敵資料、固定出發 stats 與種子一致 |

phase 為 `mulligan`、`player`、`won`、`lost`。敵回合在 `end_turn()` 內完成；UI 動畫不繼續模擬。`preview_card` 即使目前真氣不足仍可提供效果說明，但 `can_play=false`；出牌時仍重新驗證。`amount` 是穿過防護的傷害，`hp_loss` 是被剩餘氣血上限截斷的真實扣血，不可把溢傷當成多扣血。

模型快照版本為 1，與旅程外層存檔版本 2 不同。保存 mode、固定 stats、seed/rng_state、turn/phase、hp/max_hp/block/qi、hand/draw_pile/discard_pile/exhaust_pile、enemies、藥物使用、起手與首張效果旗標、skills_played/next_attack_bonus、戰鬥統計與事件紀錄。JSON 中的整數型浮點會正規化；非法 NaN／無限值／變造牌張等明確失敗。

## 視圖：WeiyuanCardArena

`card_arena.gd` 為 Node2D，大小1080×640。公開 `battle`、`action_buttons`、`restore_error`、`selected_card`、`selected_target`、`mulligan_selection`。

主要介面：`configure(mode,stats,restore={})`、`set_input_enabled(bool)`、`snapshot()`、`status()`、`report()`、`view_state()`。信號為 `finished(won,report)`、`status_changed(value)`、`changed`。main 仍負責活動 token、結果頁、重試與撤退；視圖不能直接發旅程獎勵。

操作介面為 `select_card(index)`、`select_target(index)`、`confirm_mulligan()`、`skip_mulligan()`、`end_turn()`、`use_medicine()`、`cancel_selection()`、`open_panel(kind)`、`close_panel()`。規則與牌堆面板開啟時停止出牌；main 的暫停還須關閉所有戰鬥輸入與短暫演出。

點牌時的具體行為：起手階段切換換牌勾選；玩家階段，自用／群體牌或唯一敵目標直接施放，多敵單體牌先選中再點對手施放。同牌再點可取消選中。牌面懸停提供完整說明與模型預覽，沒有額外的隱藏確認鍵。手牌每頁五張，可翻到其餘手牌。

場景快照在模型資料上新增 `_view`：selected_card、selected_target、mulligan_selection、page、panel、pile_tab。傳回模型前移除此鍵；視覺值只影響顯示，不可改回合。模型驗證失敗時顯示 `restore_error` 並關閉操作，不從空白狀態接著玩。

短暫位移／劍痕／受擊色閃只重現事件，結果模型早已結算。使用 generation guard 與單次發送旗標，避免舊場景 callback 或重複刷新多次發 finished。測試可用 `advance_presentation(delta)` 驗證演出凍結與結果回報，不能以此改變牌局。

## Run 層的鎖定與不變條件

呼叫 `run.battle_stats()` 取得鎖定資料，並傳 `pending.combat` 作 restore。每次 `changed` 及暫停／退出前保存快照；視圖選牌變化也可保存 `_view`。恢復後牌堆順序、意圖與下一次 RNG 必須相同。

完成／撤退回報必附目前 pending token；完整戰鬥 report 由主流程傳入。重試以原 pending stats/seed、空 restore 重新 configure，不用最新的 live deck，也不自行增加 serial。新安排活動才可建立新種子。

檔案名稱固定 `run-cards-v2.json`，未經另外的明確遷移工作，不接受動作版 `run-v1.json`。包裝器排除兩版存檔、備份與暫檔，正式發布檔不能帶入測試人物。

## 驗證要求

純模型套件檢查18種牌的基本／精修、首張加成不重複乘算、預覽不改資料、五場模式、精確種子重試與 JSON 恢復。視圖套件檢查真正按鈕、目標、多頁手牌、規則／牌堆、暫停、錯誤快照與單次完成信號。整合再檢查免費配牌、活動鎖定、一次精修優惠、一次機緣提示、保存後續玩與三出身收束。

這些是程式驗證要求，不是已完成的真人試玩。最終命令與結果寫入 [VALIDATION.md](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/VALIDATION.md)，真人觀察使用 [PLAYTEST_PROTOCOL.md](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/PLAYTEST_PROTOCOL.md)。
