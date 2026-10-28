# 江湖未遠 · Windows 本機開發包

[直接下載 Windows 開發包（約 72 MiB）](https://github.com/cclodty/Game-develop-rpg-wusha/raw/refs/heads/windows-local-dev-20261028/jianghu-gal-windows-dev.zip)

此分支提供 2026-10-28 的原生 GAL 網頁開發快照。包內包含可修改的 HTML/CSS/JavaScript、人物與場景素材、文楷字型及其授權、章節計劃書、介面設計基準、模型測試與本機 Codex 接續說明。不是完整 Godot 倉庫，也不含 Git 歷史或瀏覽器存檔。

## Windows 啟動

1. 下載上面的 ZIP，將包內 `Jianghu-weiyuan` 資料夾解壓到 `G:\codex`（也可選自己的專案位置）。
2. 若尚未安裝 Python，從 https://www.python.org/downloads/windows/ 安裝 Python 3.10 或更新版本。
3. 雙擊 `Start-Local.cmd`，保留命令視窗。瀏覽器會開啟 `http://127.0.0.1:8091/web/`。
4. 在 Codex 桌面程式開啟解壓後的資料夾作為本機專案。先讀 `AGENTS.md` 及 `docs/LOCAL_WINDOWS.md`，再接續修改。

CSS 儲存後自動更新；程式與素材更新時顯示重載按鈕，按下才重新載入。重載後選「續寫此程」可接續保存的進度。請固定使用相同網址與瀏覽器。

## 驗證

- 解壓後執行 20 項章節模型與 4 項牌面測試，全數通過。
- 已確認 CSS 更新保留開啟的背包，程式更新等待手動重載，重載後保留遊戲狀態與閱讀位置。
- 已檢查 1440×900 與 960×600 畫面，更新提示不遮擋背包邊框。
- ZIP 已逐檔校驗；完整檔案 SHA-256 見 `SHA256SUMS.txt`。
- Windows 批次檔尚未經 Windows 實機驗證；伺服器與瀏覽器流程已在雲端環境測試。

此次上傳僅提供本機開發包下載，沒有公開部署遊戲網站。後續發布仍需新的授權。
