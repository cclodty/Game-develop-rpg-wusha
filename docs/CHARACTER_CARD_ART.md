# 人物招式牌面 · 首批樣板

角色與招式共同決定插畫。規則仍由原本的卡牌目錄計算；換角色圖不複製或改寫傷害、費用、AI、學會清單與存檔格式。

| 人物 | 配色與動作 | 已製作 |
|---|---|---|
| 陳天佑 | 靛藍短旅行服、短束髮、褐色行囊；直接、穩定的出手姿態 | 現有十二張試招牌 |
| 宋懷晴 | 綠衣、長髮飄帶；較舒展、輕巧的劍勢 | 出劍、架勢、調息、審勢、掠影步、照隙一劍、破雲劍氣 |

懷晴牌面依 `chapter/model.js` 的實際已學清單製作；第八格為空白，不會當成額外招式。天佑的十二張圖是牌池樣板，章節中仍須依原有研習規則取得武學。

## 查看

Godot 卷首開啟「人物招式 · 牌面圖鑑」，可切換天佑／懷晴，或進入「同招對照」並逐招比較。

渡口試玩章節的實際手牌使用當前出招者的 ID 選圖，並顯示其名字。手動接管、同伴自行出牌、存讀後都沿用同一顯示邏輯。杜蘅尚未製作專屬牌圖，先顯示中性招路標記；不會出現天佑或懷晴代替她出招的畫面。

![照隙一劍的兩人版本](images/actor-card-comparison.png)

## 素材與接線

- `assets/generated/card-art.json` 是人物／招式／圖集區域的唯一來源。
- `python3 tools/sync_card_art.py` 產生 Godot 的 `scripts/card_art_catalog.gd`、章節的 `chapter/card_art.js`，並複製未修改的 PNG 到章節素材目錄。
- Godot 以 AtlasTexture 取樣；章節以 SVG viewBox 取樣並保持長寬比例。缺少人物或招式時回傳空值，介面顯示中性標記。
- 原圖、尺寸、生成來源與 SHA-256 記錄於 `assets/generated/card-art.provenance.json`。舊的共用綠衣牌圖保留為風格參考，現行手牌不再取用。

## 驗證

`node --test tests/test_card_art.cjs tests/test_ferry.cjs`：人物圖集範圍、章節素材一致性、牌組與已學招式覆蓋、中性替代、規則與存檔不被美術查詢修改。

`godot --headless --path . --script tests/test_actor_cards.gd`：每張牌的角色圖集、Godot 卡框接線、人物切換、七張牌的分頁邊界及同招對照。

`python3 tools/test_actor_cards_web.py`：隔離瀏覽器中用真實操作進入切磋、接管懷晴、輪到天佑、保存再載入、輪到杜蘅；核對牌圖人物與自訂名字，沒有注入遊戲狀態。畫面輸出到 `artifacts/actor-cards/`。
