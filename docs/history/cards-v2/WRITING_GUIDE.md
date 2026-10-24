# 《江湖未遠》情境建角與七日劇本指南

本輪有兩個敘事入口，內容與規則要分清楚：

| 內容 | 單一來源 | 狀態由誰處理 |
|---|---|---|
| 六題建角、十八分支、出身前言與熟人回顧 | [`character_creation.gd`](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/scripts/character_creation.gd) 的 `QUESTIONS`／`scene()`／`response()` | `WeiyuanCreation` 計算選擇與微調，`WeiyuanRun` 保存；`creation_journey.gd` 顯示頁面 |
| 入鎮、六人訪談、十六活動、選拔與收束 | [`first_week.dialogue`](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/story/first_week.dialogue)，Dialogue Manager | `WeiyuanRun` 扣成本、解鎖卡牌與發獎，主場景管理對話斷點 |

人物與主題見 [STORY_BIBLE.md](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/STORY_BIBLE.md)，完整建角稿見 [PROLOGUE_SAMPLE.md](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/PROLOGUE_SAMPLE.md)，數值見 [GAME_DESIGN.md](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/GAME_DESIGN.md)／[CARD_DESIGN.md](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/CARD_DESIGN.md)。歷史動作版指南另存，不再以 J／Space／Q／E 說明本輪戰鬥。

## 情境建角的編輯規則

六題順序固定為 `reason`、`packing`、`mud`、`rain`、`last_load`、`reflection`，每題三選。每個選項有 `label`、`attribute`、`tag`、`echo` 與完整 `response`。修稿要同時看前文、選項、結果和下一題承接，不可只改選項名稱卻留下另一種行動的結果。

六屬性各從 4 開始、每題 +1，總和 30；每個屬性在三題可選。編輯選項分配前先核對公平性，不能多給某條路點數。回顧可移動最多兩點、總和不變，範圍 2–8。改選會重設微調並從答案重算，不疊加獎勵；確認後停止修改建角。

`tag` 是後續回應依據，既有值不可無聲改義。動機 `prove`／`discover`／`belong` 不代表職業限制；泥車 `approach`、`support`、`finish` 用於承接做過的事，不用來診斷人格。根骨等能力的說明必須與實際卡牌效果一致，尤其定力是起手換牌、悟性是首次精修便利、機緣是首次外出提示，不能寫成未實作的防禦倍率、氣勁傷害或隨機掉寶。

正文分段供玩家正常閱讀，不能用空白頁、重複句或強制等待把時長湊到 6–8 分鐘。用三種出身看第一題前言和第六題熟人回應；用不同的第 3／4 題回答檢查接續。修改後同步 `PROLOGUE_SAMPLE.md`，以資料來源為準，避免兩份劇本逐漸分開。

## 日常編輯流程

1. 以 Godot 4.6.3 開啟此專案的 `project.godot`，等待資源匯入；確定 Dialogue Manager 外掛已啟用。
2. 在檔案面板打開 `story/first_week.dialogue`。搜尋目標 `~ title`，先閱讀它的入口、出口及相關收尾，再修改台詞。
3. 保留現有 ID。儲存後查看 Dialogue Manager 語法提示；有編譯錯誤時先處理，不用「主遊戲能啟動」代替劇本檢查。
4. 執行遊戲，以對應出身拜訪 NPC 或安排活動。分別看第一次與選項返回後的樣子，確認畫像、段落長度、出口與活動開始順序。
5. 使用本輪更新後的測試入口；劇本測試編譯 `.dialogue` 並以真正 Dialogue Manager 遍歷標題與選項，建角測試另查六題、能力公平性、微調與回顧。實際執行狀態見 `VALIDATION.md`，不可引用歷史動作版計數作為通過。
6. 把重要改動以新遊戲、活動中存讀、完成後再讀取各走一次。若改了條件，至少檢查三種出身及第 1、4、7 日。

Dialogue Manager 的獨立預覽不會自動擁有本遊戲的 `origin`、`day` 等上下文；請用主遊戲或提供完整上下文的測試來檢查條件分支，不把預覽中的未知變數誤判為存檔損壞。

## 格式與穩定 ID

```text
~ example_question
沈照嶺: 先說清楚，今天想練哪一步？ [#portrait=shen] [ID:JW_EXAMPLE_001]
if origin == "courier"
	你: 我想學會趕路之後，還能把腳站穩。 [#portrait=hero] [ID:JW_EXAMPLE_002]
- 再談談步法。 [ID:JW_EXAMPLE_003]
	沈照嶺: 腳留一點餘地，劍才有下一步。 [#portrait=shen] [ID:JW_EXAMPLE_004]
- 先回去想想。 [ID:JW_EXAMPLE_005]
	=> END
=> END
```

示例內使用真正的 Tab 縮排；寫入檔案時亦使用 Tab，不將反斜線與字母 t 當作縮排。標題行用 `~ title`，跳轉用 `=> title`，結束用 `=> END`。一般台詞格式為 `角色: 內容`；旁白也使用 `旁白:`。

每條可見對白、旁白、回應選項均需 `[ID:唯一值]`。既有格式為 `JW_<標題大寫>_<三位數>`。**編輯、移動、插入新句時不得重新編號原來的 ID。** 新句用該標題未使用過的編號；刪去的 ID 不挪給另一句。ID 用於翻譯與追蹤，不是讀檔游標的替代品，劇本版本不同仍須由主程式處理恢復位置。

同一人物台詞一行以一個完整意思為單位，通常 20–60 個中文字，必要時可至約 90；再長就拆成有停頓的兩句。選單最多四項，問題通常三項，加一個清楚的返回／查看活動出口。避免只有「……」而沒有角色意圖的連續空白點擊。

## 可用角色、畫像與條件

| 顯示角色 | 畫像標籤 |
|---|---|
| 你 | `[#portrait=hero]` |
| 沈照嶺 | `[#portrait=shen]` |
| 陸行雲 | `[#portrait=lu]` |
| 陶半夏 | `[#portrait=tao]` |
| 周望山 | `[#portrait=zhou]` |
| 蕭小滿 | `[#portrait=xiao]` |
| 林知微 | `[#portrait=lin]` |
| 旁白 | 不加畫像標籤 |

畫像標籤必須緊接 `[#`，不能寫成 `[ #portrait=...]`。不在文本中塞入機制標記、獎勵程式碼或介面操作說明。

主程式透過 `run.story_context()` 傳入以下唯讀資料：

| 變數 | 型別／意義 | 可用例子 |
|---|---|---|
| `hero_name` | 字串，自訂姓名 | 預留給需要稱名的場景；目前主角說話者由介面顯示姓名 |
| `origin` | `herbalist`／`courier`／`performer` | `if origin == "herbalist"` |
| `day` | 整數 1–8 | `if day >= 7`、`elif day >= 4` |
| `remaining` | 整數 0–21 | 可讀剩餘準備時段 |
| `training` | 整數，武學 | `if training >= 6` |
| `insight` | 整數，見識 | `if insight >= 6` |
| `has_sword_qi` | 布林，是否已習得對應劍氣 | 可用於已學後問候，不代表必已放進牌組 |
| `has_cloud_step` | 布林，是否已習得對應身法 | 可用於古道回顧，不代表已加入渡雲 |
| `school` | 字串，所選去向或空字串 | 收束後問候；資格仍由規則判定 |
| `creation_motivation` | `prove`／`discover`／`belong` | 呼應離家的理由 |
| `creation_approach` | `unload`／`brace`／`observe` | 呼應泥車第一步 |
| `creation_support` | `fetch`／`steady`／`ask` | 呼應雨前協作 |
| `creation_finish` | `carry`／`sequence`／`path` | 呼應把人貨帶到地方的收尾 |

不可直接讀取 `favor`、`completed`、`money` 等未列入的變數，也不要自行在劇本新增全域狀態。若故事確實需要任務完成後問候，先同步 `story_context()`、存讀相容與測試，再寫條件。現在的日數問候只能反映時間，不能據此斷言玩家去過某地或完成某事。

## 活動接入：何時說、何時發獎

| 入口型態 | 劇本責任 | 遊戲責任 |
|---|---|---|
| `arrival_morning` | 建角翌晨的熟人早餐、晨街、兩位師傅與七日規則；不重演離家或忘記歇腳的熟人 | 已確認建角後進入七日旅程，回到鎮上 |
| `npc_<id>` → `<id>_questions` | 日數問候、出身回應、可返回的詢問 | 普通交談不扣時；結束後顯示可安排活動 |
| `activity_<id>`：故事／休息型 | 完整的已確認活動場景 | 在入口前一次扣成本，END 後統一結算 |
| `activity_<id>`：任務／探索／戰鬥型 | 接受活動後的簡報；只說準備和目標 | END 後進入行走目標或戰鬥，不在簡報結束時發獎 |
| `complete_<id>` | 實際成功後的敘事收束 | 操作達成後才播放；END 後結算一次 |
| `exam_intro` | 提醒規則、看見七日準備 | 進入教頭切磋；認輸亦可判定資格 |
| `ending_<school>` | 對應去向的情感落點 | 玩家在合資格結果中選擇，播放後呈現完成畫面 |

故事／休息完整場景共有六項：`sword_lesson`、`old_ballad`、`hermit_visit`、`medicine_lesson`、`meditate`、`rest`。

另十項皆有簡報與完成場景：`practice`、`spar`、`courier_work`、`stage_work`、`herb_errand`、`grove_survey`、`ridge_tracks`、`escort_promise`、`bridge_repair`、`missing_letter`。

**所有劇本唯讀，禁止 `do`、變數賦值或直接發錢／技能／信任。** `WeiyuanRun` 統一持有活動 token、已扣時段與結算狀態。反覆閱讀、返回選單、載入正在閱讀的台詞都不得改變收益。七日劇本中的表達選項目前只改回應，不改數值；六題建角的 +1 則由已定義的建角規則處理。若新增七日決策後果，先定義活動結果資料，再接入中央結算與保存，不用台詞副作用繞過規則。

出場簡報應採「要去做」「今天先」等尚未完成的語氣。成功場景才描述藥帶回、橋板修好、對練結束。未完成時玩家可能撤退，必須仍有合理敘事。

## 原創語氣與一致性檢查

- 使用繁體中文，以自然口語配少量武俠詞，不把每個人都寫成古文師父。沈簡短，陸輕巧，陶直接，周講憑據，蕭帶台感，林願意承認不知道。
- 一個人物說大道理前，先讓他做一件小事：修劍、數回執、收紅綢、讓橋上的人先過。笑點要服務關係，不嘲笑玩家失敗。
- 保持中武尺度。破雲劍氣是可學會的戰鬥招式，沒有真的劈開天際；掠影突進是攻守銜接，不等於瞬移到任何地方。
- 三種出身都能拜兩派。不要因一句對話判定職業限制，也不把照嶺與渡雲寫成道德對立。兩派牌可混學，學牌不等於已拜師。
- 普通交談不許說「聊完天就過了半天」。正式活動成本由確認頁提供；劇本可自然提及工夫，不再扣一次。
- 保留任務物件一致：溪谷有失落藥籃，護送主貨物為藥箱、木偶是順帶小匣；未送達的信以「木劍先生」舊稱尋人，確定後原封交給沈照嶺。
- 留鎮結局可由已有邀請者主動選擇，文字不要預設「沒有人肯收你」。三個結局都要明示首篇結束。
- 不把 Scenario 帳號、生成方式、Godot 類名或付費資訊寫進人物對話。這些屬製作文件，不是望溪鎮居民會說的話。

## 測試邊界

[`tests/test_story.gd`](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/tests/test_story.gd) 負責正式編譯、必需標題、ID 唯一性、禁止突變，以及不同出身／日期／能力下的可達對話與出口；建角另由 `tests/test_creation.gd` 覆蓋，主遊戲流程由本輪卡牌 UI 測試檢查。它們可以找出斷鏈與不能結束的問答，但不能證明故事好讀、角色討喜或首次遊玩達到目標時長。

人工閱讀至少記下三件事：哪一句讓人物變得可辨識、哪一個選項不清楚會去哪裡、下一輪想嘗試哪件沒有做的事。若玩家只記得門檻數字而不記得人，優先改場景與回應；不要用增加無意義等待來湊遊玩時間。

卡牌效果文案來自 `card_catalog.gd`；不要在對話另寫一套容易過期的傷害表。老師可用自然說法介紹「先架勢再出劍」，確切費用、防護、追加傷害由牌面提供。角色可以談節奏，但不要暗示玩家閱讀時還有反應倒數。真人可讀性與動機的檢查方式見 [PLAYTEST_PROTOCOL.md](https://github.com/cclodty/Game-develop-rpg-wusha/blob/fc1e2ae957349caafec2e4163cf5737320584e5e/docs/PLAYTEST_PROTOCOL.md)，未測項目維持待測。
