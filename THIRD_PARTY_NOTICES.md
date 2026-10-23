# 素材與依賴來源

## Godot Engine

使用 Godot 4.6.3 標準版與 Compatibility renderer。Godot 採 MIT License，授權與第三方元件聲明分別保存在 `licenses/Godot-LICENSE.txt`、`licenses/Godot-COPYRIGHT.txt`，來自官方 `4.6.3-stable` 標籤；Web 匯出另附於 `build/web/licenses/`。

來源：<https://github.com/godotengine/godot/tree/4.6.3-stable>。

## Dialogue Manager

使用 Nathan Hoad 的 [Dialogue Manager v3.10.4](https://github.com/nathanhoad/godot_dialogue_manager/releases/tag/v3.10.4)，MIT License。上游 commit 為 `5487c524b9eac303b059e5859e2980b134c59d79`。完整授權在 `addons/dialogue_manager/LICENSE`，Web 包另附 `build/web/licenses/DialogueManager-LICENSE.txt`。

本專案使用原有已驗證的插件副本；不需要 .NET、雲端帳號或付費 API。

## Noto CJK 字體

`assets/fonts/JianghuSans.otf` 與 `JianghuSerif.otf` 來自 Noto Sans CJK TC／Noto Serif CJK TC，經子集處理並重新命名，採 SIL Open Font License 1.1。來源與完整授權在 `assets/fonts/README.md`、`assets/fonts/LICENSE-NOTO.txt`；Web 包附有 `build/web/LICENSE-NOTO.txt`。

## 原創內容與生成美術

《江湖未遠》的世界、角色、劇情與遊戲程式為本專案原創。既有《山河行》的輕量合成環境音樂與按鈕音效沿用作為本次試玩的音訊基礎。沒有使用《金庸群俠傳3》的程式、角色、對話、音樂或遊戲資產。

`assets/generated/` 由 OpenAI image generation 為本次新作生成；規範及來源見 `docs/ART_DIRECTION.md` 與生成記錄。原始圖像保留不變，必要的圖集取樣由 Godot 在執行時完成。

Scenario 未列為本版執行依賴，遊玩不需要 Scenario 帳號或 Creative Units。
