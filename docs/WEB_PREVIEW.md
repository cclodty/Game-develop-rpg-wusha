# 推送後試玩

本次依 2026-10-29 使用者要求，將最新原生 GAL 原始碼整理為 `gh-pages` 分支，使用 GitHub Pages 的分支部署。原生 HTML／CSS／JavaScript 不需要編譯，GitHub 收到更新後會自行發布。

預定網址：**https://cclodty.github.io/Game-develop-rpg-wusha/**，入口會轉到同站的 `web/`。這是公開試玩站；目前的實際發布狀態見根目錄 README。

## 第一次啟用

如果站點尚未啟用，由儲存庫管理員開啟 [Settings → Pages](https://github.com/cclodty/Game-develop-rpg-wusha/settings/pages)：

1. Source 選 **Deploy from a branch**。
2. Branch 選 **gh-pages**，目錄選 **/ (root)**，按 **Save**。
3. 等 GitHub 的 `pages build and deployment` 完成，再開啟試玩網址。

只需設定一次。GitHub 可能在偵測到新的 `gh-pages` 分支時自動選用它，仍應以實際部署狀態為準。Actions 中的環境 `github-pages` 會列出已上線網址與部署提交。

## 每次修改

在 `gh-pages` 分支改 `web/style.css`（外觀）、`web/app.js`（互動）、`chapter/content.js`（劇情）或 `chapter/model.js`（規則）。本機可執行 `python tools/dev_server.py`，固定使用 `http://127.0.0.1:8091/web/` 預覽。

檢查後 commit 並 push 到 `gh-pages`；GitHub Pages 會自動更新同一網址。使用 Pull Request 時，以 `gh-pages` 為目標，合併後才更新公開站。未合併的 PR 沒有獨立公開預覽網址。本分支可以直接在 GitHub 或 Codex 修改，不必重新下載或上傳 ZIP。

更新後若仍看到舊畫面，先等部署成功，再用 Ctrl+Shift+R 重新整理。儲存庫預設分支目前仍指向舊下載包，檢查／開發時請選 `gh-pages`。

## 存檔與檢查

沿用 `jianghu-gal-web-v1:*` 與閱讀偏好命名，不變更存檔格式。每次更新都使用相同網址與瀏覽器，正常更新不會清除網站資料。本機 8091 與公開試玩站是不同來源，需透過遊戲的 JSON 匯出／匯入搬移進度。日後若改動存檔結構，須先設計版本遷移。

執行：

```sh
node tests/test_ferry.cjs
node tests/test_card_art.cjs
python tools/test_web_hosting.py
```

最後一項需要 Python Playwright、Pillow 及 Chromium，只是開發驗證工具；玩家開網站不需要安裝它們。測試在與 GitHub Pages 相同的 `/Game-develop-rpg-wusha/` 路徑檢查根入口、素材、字型、改名、對話、行囊、閱讀設定與重新載入後續玩，並擷取 1440×900 及 960×600 畫面。它不驗證 GitHub 後台權限或部署佇列。

## 來源

網頁程式取自 `windows-local-dev-20261028` 的 `0254d93c4077f9b531eb731cb25901c0261e1544`，匯入前依 ZIP 內的 SHA-256 清單逐檔檢查。原始清單保留為 `docs/windows-dev-20261028-manifest.json`，用於追溯輸入版本，後續修改不會假裝仍與舊快照完全相同。

`weiyuan-ferry-trial` 的 `0870d64` 是較早的網頁章節；Godot 武學核心為 `57bffda`。歷史分支和下載包繼續保留，這份分支只承接最新原生網頁。

## 2026-10-29 本輪檢查

- 最新開發包的 60 個輸入檔案逐檔 SHA-256 通過；37 個遊戲程式及素材檔案維持原樣。
- 章節模型 20 項、牌面 4 項測試通過。
- Chromium 四組操作通過，實際使用 `/Game-develop-rpg-wusha/` 路徑，沒有失敗資產請求或瀏覽器錯誤。
- 1440×900 與 960×600 均操作改名、對話、行囊分類、閱讀設定及重新載入續玩；唯讀核對故事與閱讀位置，沒有注入遊戲狀態。
- 已目視檢查實際畫面：[卷首](images/web-preview-title.png)、[小視窗行囊](images/web-preview-inventory.png)、[對話](images/web-preview-dialogue.png)。

以上是本機模擬正式站路徑的驗證，公開部署尚需獨立核對。雲端目前的網路允許清單沒有 `api.github.com` 與 `cclodty.github.io`；GitHub API 回應 Forbidden，不能據此宣稱 Pages 已啟用。
