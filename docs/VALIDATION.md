# 內功與蓄勢 v3 驗證狀態

分支：`weiyuan-martial-core`。Godot 4.6.3、Dialogue Manager 3.10.4。更新日期：2026-10-24。

本輪原生驗證已完成：`bash tests/run_tests.sh` 的九個套件共 **5,859 項通過、0失敗**，退出碼0，沒有SCRIPT ERROR或ERROR。Godot 4.6.3 Web匯出成功，Chromium九組真實操作流程通過；公開下載HTTP校驗另由下載分支記錄。

| 項目 | 狀態 |
|---|---|
| 十二牌／三內功／兵器／精修目錄 | 原生通過 |
| 勢／留牌／反擊／伏針／中途選牌存讀 | 模型及原生場景通過 |
| 正式旅程、變動奇遇、活動鎖定／一次獎勵 | 原生通過 |
| 試招三套牌組、四類敵人、獨立存檔 | 原生通過；合法策略72場勝出 |
| 原生實際畫面與 Chromium 真實輸入 | 原生UI及九組Chromium流程通過，0 console error／pageerror |
| 8072 Python啟動器 | 通過；四個主要檔案HTTP內容與匯出SHA256相同，wasm MIME及HEAD正確 |
| ZIP完整性／存檔排除 | 兩包CRC／SHA256通過，均小於100MiB，無任何版本的玩家存檔 |
| 公開下載HTTP核對 | 結果見下載分支 `validation/release.json` |
| 三名首次玩家 | 全部待招募／待測 |

舊 v2 的3,707項原生與七組瀏覽器流程見 [歷史驗證](history/cards-v2/VALIDATION.md)，不計作本輪結果。更早動作原型的8,013項亦保留在歷史目錄。

## 原生套件與範圍

| 套件 | 通過數 | 重點 |
|---|---:|---|
| `test_run_state.gd` | 563 | 七日、活動交易、條件與保存回歸 |
| `test_creation.gd` | 1,564 | 六題公平性、回看微調、能力與序章回應 |
| `test_martial_catalog.gd` | 256 | 十二牌普通／運勁、三精修、三牌組、兵器與來源 |
| `test_card_battle.gd` | 2,249 | 支付／產勢、三內功、留牌、反擊／延遲、合法交手及精確快照 |
| `test_card_run.gd` | 650 | 可靠師承、變動奇遇、旅程／試招隔離、精修與活動鎖定 |
| `test_card_arena.gd` | 66 | 真實普通／運勁按鈕、目標、留牌、換牌、多頁、暫停及恢復 |
| `test_world.gd` | 104 | 城鎮／探索行走與互動回歸 |
| `test_story.gd` | 81 | 正式編譯、唯一ID、唯讀、三出身／三日期與四個奇遇回應 |
| `test_card_ui.gd` | 326 | 三出身建角及學武配招、四類試招合法勝利、敗北重試、兩種續玩 |
| **合計** | **5,859** | **0失敗** |

模型的第一組36場為三套牌組×四類對手×種子7／42／2026，能力統一各5，全部合法勝出。第二組36場為三種真實問答能力配置×三套牌組×四類對手，種子42，亦全部勝出。策略只用當前可見手牌及意圖，不改敵人氣血、不重排起手，也不偷看牌堆；這72場證明有合法解法，不代表所有種子、所有合法配點或任意混搭都已平衡。

規則單元測試另有手牌／防護fixture，用於隔離難以自然同時發生的邊界；不能把它們計為自然通關。五個旅程遭遇以基本牌組驗證可終止與快照有效，其中首場練習明確檢查勝出，未把其餘四場都宣稱為基本牌勝利。原生UI另以實際控制項跑四類對手、合法不出牌敗北與同種子重試；結果頁fixture只檢查畫面路由。

原生記錄在 `artifacts/martial-validation/native.log`，匯入及匯出記錄為同目錄的 `import.log`／`export.log`。這些是本機驗證產物，不混入玩家存檔或發布包。

## 真實 Chromium 流程

`tools/test_martial_web.py` 以滑鼠鍵盤完成九組流程，三種出身分別使用獨立瀏覽器context；`state_injection=false`，未注入敵人血量、活動結果或獎勵。

- 三出身各完成六題、移點、翌晨導入與鎮上自由移動；其中一輪在序章中保存、重開並接回原回應與能力。
- 守中對連擊、行雲對重甲、歸元對蓄勢，三場由當前可見手牌合法操作勝出，結算不影響正式旅程。第四種反制敵確認實際公開意圖後撤退，**沒有把它列作瀏覽器勝利**。
- 實際使用普通與運勁；留牌標記及掠影步挑牌中的選擇經保存、瀏覽器重開後精確恢復，再繼續操作。
- 試招與旅程兩個續玩入口各回正確角色／狀態，試招不消耗七日資源。

result.json中只有24條一般log，沒有console error或pageerror。保存三份實際遊玩錄影與截圖；詳見本機 `artifacts/martial-validation/web/result.json`、同目錄recordings。測試對四個匯出檔在前後計算SHA256，確認過程中未更換遊戲檔。此流程沒有從新角色完整玩到三個七日結局；其日程、錄取、結果頁與保存規則由原生套件分別檢查。

## 最後教學文案修正的補驗

完整九組瀏覽器流程的PCK為 `4c2e617dfa750517e54062728feb9e6da16ccce0a82be94bd984028f438d9d61`。之後只修正 `character_creation.gd` 的兩行教學文字：初始牌把舊「虛招」改為「飛石問路」，均衡配置提示改為拆防配合防護；戰鬥、旅程及保存規則沒有改動。

重新匯出的最終PCK是 `53e3c0ab105666b2f49a24ddbd9ef0a5c276282b5d6794342b135627c02beff6`。對此版本另做兩組真實Chromium流程：序章中途存讀及藥鋪出身六題／微調／新教學文字／翌晨／走動，0console error／pageerror；結果另存 `artifacts/martial-validation/web-final-copy/result.json`，沒有覆蓋原九組報告。

原生建角套件補跑1,564項、0失敗；另用實際Creation／Run產生均衡配置，確認新拆防建議、無舊卡名，4行共108px完整容納145px文字區。補驗是重測，沒有加進5,859項合計湊數。已目視 [最終建角教學畫面](images/martial-creation-advice.png)。

## 必須說清楚的驗證範圍

規則測試要核對支付先於回報、產勢配額、零費牌不更新行雲的付費招路、保留後補五張、選牌中間態、反擊與死亡順序、伏針取消、頭目意圖鎖定及同活動重試。UI需實際看清普通／運勁、真氣／勢、留牌、換牌中的選擇及長文字；只看退出碼或控制項bounds不夠。

真瀏覽器測試使用獨立來源與context，從滑鼠鍵盤操作，只讀存檔核對，不注入敵人氣血或獎勵假裝通關。若有用於特定結果介面的fixture，與合法戰鬥／路線結果分開列出。

已檢視當輪實際Chromium畫面：[試招準備](images/martial-hub.png)、[普通／運勁預覽](images/martial-combat.png)、[換牌中途讀檔](images/martial-cycle-resumed.png)。這些圖片來自上述真實流程，並非舊版畫面或美術構想圖。

## 本輪文件與交付工具檢查

`python3 -m py_compile tools/package_release.py tools/serve_web.py` 通過。Markdown本機連結無失效；新劇本文字在JianghuSans／JianghuSerif均無缺字。`Play-Windows.cmd` 保持ASCII與CRLF；這是檔案檢查，不能替代Windows實機。

Linux啟動 `python3 tools/serve_web.py`，以預設8072實際取得index.html、index.js、index.wasm、index.pck，各檔SHA256與當輪匯出一致。wasm回傳application/wasm；HEAD保持正確MIME與空body。Windows PowerShell尚未在本環境執行。

最終兩個ZIP已逐一通過CRC與SHA256SUMS.txt核對；source包每個成員與最後工作樹逐字一致，web包四個主要檔案與最終匯出一致。包內Godot、Dialogue Manager及Noto授權齊備，排除v1／v2／v3／試招存檔、備援、暫檔與Godot快取。解壓web包後再次從包內啟動8072，四檔HTTP雜湊及wasm MIME／HEAD通過。記錄在 `artifacts/martial-release/package-check.json`；校驗碼以同目錄SHA256SUMS.txt為準。

公開下載檔案與來源提交的關係、HTTP下載雜湊核對，請查看下載分支的 [validation/release.json](https://github.com/cclodty/Game-develop-rpg-wusha/blob/weiyuan-martial-download/validation/release.json)。本文件的本機檢查不代替該HTTP結果。

## 真人與平台待測

[PLAYTEST_PROTOCOL.md](PLAYTEST_PROTOCOL.md)及三份空白記錄已備妥，尚無真人結果。普通戰鬥2–4分鐘、序章6–8分鐘、首篇30–60分鐘仍是目標。需要玩家能解釋內功、一次留牌與一次提早花勢的理由，再談理解度與重玩價值。

真正Windows桌面、中文輸入法、Safari、手機與手把依實際執行結果逐項記錄；本輪不沿用舊版通過數來宣稱已完成實機驗證。
