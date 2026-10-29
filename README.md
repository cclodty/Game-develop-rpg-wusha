# 江湖未遠 · 網頁開發與試玩

最新原生 GAL 網頁版的可修改原始碼，取自 2026-10-28 Windows 開發包。

**試玩網址：[cclodty.github.io/Game-develop-rpg-wusha](https://cclodty.github.io/Game-develop-rpg-wusha/)**

部署狀態：GitHub 已自動啟用 Pages，首次 [pages build and deployment](https://github.com/cclodty/Game-develop-rpg-wusha/actions/runs/40811410978) 成功。之後推送到 `gh-pages` 會更新同一網址。

部署分支為 **`gh-pages`**。入口、素材、字型、劇情與遊戲規則均隨分支提供，玩家使用桌面 Chrome 或 Edge 開啟網址即可。首次啟用及當輪部署核對見 [WEB_PREVIEW.md](docs/WEB_PREVIEW.md)。

## 邊玩邊修改

1. 在 Codex 或 GitHub 選 `gh-pages` 分支。
2. 修改程式並推送；使用 PR 時，合併至 `gh-pages`。
3. 等 Actions 的 `pages build and deployment` 成功，重新整理同一試玩網址。

外觀在 `web/style.css`，互動在 `web/app.js`，劇情在 `chapter/content.js`，卡牌／日期等規則在 `chapter/model.js`。本機預覽執行 `python tools/dev_server.py`，開啟 `http://127.0.0.1:8091/web/`；Windows 可用 `Start-Local.cmd`。

公開站與本機網址的存檔空間各自獨立，需要遊戲內的 JSON 匯出／匯入來搬移。網站沿用既有存檔命名與格式；正常程式更新不會主動清除進度。沒有雲端同步。

## 版本與檢查

這是手繪 GAL、四處探索、十四事件、三人卡牌戰鬥及三種章末結果的原生網頁試玩。正式創角問答、小說核稿和第二區域仍待製作。背景、人物與全介面文楷沿用已確認素材。

開發檢查：`node tests/test_ferry.cjs`、`node tests/test_card_art.cjs`、`python tools/test_web_hosting.py`。網頁部署及 1440×900／960×600 的實際操作檢查詳見 [部署說明](docs/WEB_PREVIEW.md)。

- [第一章製作計劃](docs/CHAPTER_ONE_PLAN.md)
- [介面基準](docs/GAL_INTERFACE_FRAMEWORK.md)
- [Windows 本機開發](docs/LOCAL_WINDOWS.md)
- [原始開發包](https://github.com/cclodty/Game-develop-rpg-wusha/tree/windows-local-dev-20261028)

本分支承接最新網頁原始碼；Godot、舊試玩與下載包留在既有歷史分支。字型授權及素材來源隨 `assets/`、`chapter/assets/` 提供。
