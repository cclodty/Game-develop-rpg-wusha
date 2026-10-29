# Windows 本機開發

建議位置：`G:\codex\Jianghu-weiyuan`。這是原生網頁專案，不需要 Godot、Docker 或虛擬機。

## 第一次準備

1. 下載 `jianghu-gal-windows-dev.zip`，全部解壓縮。將包內的 `Jianghu-weiyuan` 資料夾放到 `G:\codex`，不要覆蓋已有的其他專案。
2. 若電腦尚未安裝 Python，從 https://www.python.org/downloads/windows/ 安裝 Python 3.10 或更新版本。啟動工具會先檢查，沒有 Python 時會顯示說明，不會自行安裝軟體。
3. 雙擊 `Start-Local.cmd`，保留開啟的命令視窗。瀏覽器會開啟 `http://127.0.0.1:8091/web/`。
4. 在 Codex 桌面程式中新增或開啟這個資料夾作為**本機專案**，再從該專案建立工作。現有雲端對話不會因為下載檔案而自動取得你的本機磁碟權限。

日後：開啟同一個本機專案 → 雙擊啟動檔 → 在該專案的對話要求修改 → 在瀏覽器查看結果。

## 修改與回饋

- CSS 儲存後約一秒自動更新，保留正在查看的介面。
- JavaScript、HTML 或素材有變更時，頁面會出現重載按鈕；按下才重新載入。遊戲原有的離頁保存會先執行，重載後可選「續寫此程」。
- 本機網址固定為 `127.0.0.1:8091`。不要在 `localhost`、不同埠或直接開檔之間來回切換，這些可能使用不同的瀏覽器存檔空間。
- 雲端試玩的瀏覽器存檔不包含在開發包內。若要搬移進度，先在舊遊戲匯出 JSON，再在本機存讀頁匯入。
- 修改需求可寫成：「背包右側說明再往上 20px，保留其他布局；完成後在 1440×900 和 960×600 自查。」

## 給本機 Codex 的接續提示

> 這是《江湖未遠》的原生 GAL 網頁版。先讀 AGENTS.md、docs/LOCAL_WINDOWS.md、docs/CHAPTER_ONE_PLAN.md 和 docs/GAL_INTERFACE_FRAMEWORK.md，再檢查現有程式。使用 tools/dev_server.py 在 127.0.0.1:8091 啟動本地預覽。維持手繪畫風、靛藍主角、綠衣懷晴及全介面文楷。保留現有存檔與章節規則，不重新從零製作。每步完成後親自查看 1440×900 和 960×600 的實際畫面，操作受影響的按鈕，修正重疊與裁切，再交付截圖及檢查結果。沒有新的授權時不要推送 GitHub 或公開部署。

## 包內範圍與檔案位置

這是**可直接修改的網頁原始碼包**，不是完整 Godot 倉庫，也沒有 Git 歷史。保留源文件與素材、設計基準、主要實機圖及模型測試；計劃書提到的 Godot／3D 檔案屬雲端保留版本，未收進此包。

| 修改內容 | 位置 |
|---|---|
| 布局、字型大小、顏色 | `web/style.css` |
| 網頁互動及介面組裝 | `web/app.js` |
| 說話者與表情標記 | `web/presentation.js` |
| 章節文字 | `chapter/content.js` |
| 事件、日期、研習、戰鬥規則 | `chapter/model.js` |
| 人物與手繪素材 | `assets/generated/`、`chapter/assets/` |
| 設計與接續基準 | `docs/CHAPTER_ONE_PLAN.md`、`docs/GAL_INTERFACE_FRAMEWORK.md` |

預覽只需 Python 標準庫，無需 pip 套件。若要執行模型測試，另裝 Node.js 後執行 `node tests/test_ferry.cjs`、`node tests/test_card_art.cjs`。自動瀏覽器驗證另需 Playwright；這些不是開啟遊戲的前置要求。

若 8091 已被佔用，先關閉上一個預覽命令視窗，再啟動；不要任意換埠導致看似遺失存檔。結束預覽可在命令視窗按 Ctrl+C。

雲端可驗證伺服器及瀏覽器行為，但 Windows 批次檔的實機啟動仍須在你的電腦確認。
