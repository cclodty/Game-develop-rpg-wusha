武俠物品庫｜重建版 v1
完成日期：2026-10-26
交付：240件通用＋八派各16件＝368件設定，23張透明圖集、368個圖示區域。

本庫為使用者授權重新設計的資料，並非原有240件清單的逐項復原。
240件江湖通用物品與128件門派物品分開編號；舊版ID對照未知。
八派：少林、武當、峨眉、華山、崑崙、崆峒、丐幫、唐門。
不包含照嶺門、渡雲社或克蘇魯24件物品。

使用方式
解壓後開啟 index.html，即可離線搜尋、篩選及查看物品詳情。
catalog.json 為完整資料；catalog.csv 可用試算表開啟；CATALOG.txt 是文字版。
data/ 保存各類原始設定；assets/atlases/ 保存實際生成的圖集。
圖集依4×4、從左到右再由上而下排列；cell_index為0至15。
生成圖格若不是精確等分，atlas-regions.json另存量測座標；圖鑑依座標顯示，原PNG不改動。
圖片是否完成以catalog.json及圖鑑實際狀態為準，不能把美術描述當成已生成圖片。

內容規則
每派16件：外功秘籍4、內功心法3、輕功身法2、修練心得1、兵器2、服飾1、信物1、補給1、傳承物1。
門派獨有表示師承、取得來源與外觀特徵；不一律禁止跨派學習或裝備。
物品用途與代價目前是設計資料；戰鬥數值、配方、交易價格及劇情接線仍需後續實作。
本包不修改現有遊戲、存檔、門派系統或下載版本。

保存與來源
research-and-scope.json 記錄本次範圍、參考網址與重建限制。
atlas-manifest.json記錄圖集來源、尺寸、SHA-256與排列。
原始圖片保留，以圖集座標顯示縮圖，不修改原圖像素。

重新建立
安裝Python3後執行：python3 tools/build_catalog.py
資料驗證：python3 tools/validate_catalog.py
產物不需要Python才能瀏覽；維護腳本才需要。
重新量測圖集需Pillow：python3 tools/measure_atlases.py
check_browser.py為此環境使用的額外驗證腳本，需要Playwright與Chromium；一般瀏覽不需安裝。
建議保存wuxia-items-368.zip及SHA256SUMS.txt，方便獨立備份與核對。
