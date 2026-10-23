# 既有動畫素材的沿用範圍

完整十二格動畫合約已移至 [動作原型歷史文件](history/action-prototype/ANIMATION_CONTRACT.md)，對應提交 `9f6f187`。其中即時攻擊命中時間、反應操作、0.65 秒戰敗演出與舊存檔說明屬當時的動作原型，不是目前卡牌規則。

卡牌版仍保留原始動畫 PNG、`animation_bank.gd`、世界行走／NPC 動畫與獨立逐格圖鑑作為已有資產。原有 42 組／504 姿勢不代表新卡牌玩法已驗收。世界行走沿用固定腳底與比例、暫停凍結等要求。

新戰鬥由 `card_battle.gd` 決定效果、`card_arena.gd` 顯示固定角色與短暫回饋。出牌沒有即時命中窗口，演出不額外發傷害；新存檔為 `run-cards-v2.json`。目前介面見 [CARD_CONTRACT.md](CARD_CONTRACT.md)，美術用途見 [ART_DIRECTION.md](ART_DIRECTION.md)。
