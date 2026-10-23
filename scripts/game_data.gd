class_name WeiyuanData
extends RefCounted
## Content and balancing values. All time costs are whole activity slots.

const ORIGINS = {
	"herbalist": {"name": "藥鋪學徒", "description": "跟著師傅認草藥，也認得逞強的人。你帶著一張藥方走進望溪鎮。", "perk": "起始多兩份回復藥；採藥、學製藥各多得一份藥。", "money": 24, "medicine": 4, "insight": 0},
	"courier": {"name": "驛站跑腿", "description": "走過的路比寫過的字多。送到手裡的信，你總想親口等一句回覆。", "perk": "起始多十六文；送信差事每次多賺八文。", "money": 40, "medicine": 2, "insight": 0},
	"performer": {"name": "戲班子弟", "description": "戲臺教你站穩，也教你看人。這一次，你想演一回自己的江湖。", "perk": "起始見識一點；街頭演出每次多賺八文。", "money": 24, "medicine": 2, "insight": 1},
}

const NPCS = {
	"shen": {"name": "沈照嶺", "role": "照嶺門師傅", "description": "教你先站穩，再談劍鋒往哪裡去。"},
	"lu": {"name": "陸行雲", "role": "渡雲社引路人", "description": "會從你繞過的一塊石頭，看出你的心思。"},
	"tao": {"name": "陶半夏", "role": "半夏藥鋪掌櫃", "description": "嘴上嫌你添亂，藥包卻總會多放一份。"},
	"zhou": {"name": "周望山", "role": "望溪驛站主事", "description": "他記得每一封沒送到的信，也記得補上承諾的人。"},
	"xiao": {"name": "蕭小滿", "role": "戲班領班", "description": "半支曲子能逗笑一條街，剩下半支留給自己。"},
	"lin": {"name": "林知微", "role": "鎮史記錄人", "description": "舊路、舊橋、舊約定，他都肯替人多查一頁。"},
}

const SKILLS = {
	"sword_qi": {"name": "破雲劍氣", "description": "凝氣於劍，向前打出穿行的劍氣。適合正面把握敵人的空隙。"},
	"cloud_step": {"name": "掠影突進", "description": "短距離快速穿進戰局，沿路出劍。適合移位與連接普攻。"},
}

const SCHOOLS = {
	"zhaoling": {"name": "照嶺門", "description": "站得穩，守得住，也肯替承諾多走一步。"},
	"duyun": {"name": "渡雲社", "description": "看得清，走得活，把沿途見聞變成自己的劍。"},
	"stay": {"name": "留鎮續修", "description": "入山的日子可以晚些；願意再學，江湖便還在眼前。"},
}

const ACTIVITIES = {
	"sword_lesson": {
		"name": "聽劍入門", "npc": "shen", "cost": 2, "kind": "story", "repeatable": false,
		"description": "跟沈師傅學會讓氣隨劍走。先聽清出手的理由，再試第一道劍氣。",
		"reward_text": "武學 +2、沈師傅信任 +2，學會「破雲劍氣」；學費 12 文。",
		"fee": 12, "rewards": {"training": 2, "skills": ["sword_qi"], "favor": {"shen": 2}},
	},
	"practice": {
		"name": "劍坪練習", "npc": "shen", "cost": 1, "kind": "battle", "battle": "practice", "repeatable": true,
		"description": "在劍坪練習移位、連段和閃避。完成練習才記下這一份功夫。",
		"reward_text": "完成後武學 +1；可重複安排。", "rewards": {"training": 1},
	},
	"spar": {
		"name": "同門對練", "npc": "shen", "cost": 2, "kind": "battle", "battle": "spar", "repeatable": true,
		"description": "與候選弟子輪流切磋，試著讀懂比自己快半拍的劍。",
		"reward_text": "武學 +2、沈師傅信任 +1；需要武學 3。",
		"requires": {"training": 3}, "rewards": {"training": 2, "favor": {"shen": 1}},
	},
	"courier_work": {
		"name": "街巷送信", "npc": "zhou", "cost": 1, "kind": "task", "location": "wangxi", "repeatable": true,
		"description": "把兩封信交到收信人手裡，聽完回覆再回驛站。",
		"reward_text": "盤纏 +18 文（驛站出身 +26）、周主事信任 +1（此差事最多累積至 3）。",
		"rewards": {"money": 18, "favor": {"zhou": 1}}, "favor_cap": 3,
	},
	"stage_work": {
		"name": "街頭小戲", "npc": "xiao", "cost": 1, "kind": "task", "location": "wangxi", "repeatable": true,
		"description": "替蕭小滿搭臺、招呼觀眾，演一折讓人願意停下腳步的小戲。",
		"reward_text": "盤纏 +16 文（戲班出身 +24）、蕭小滿信任 +1（此差事最多累積至 3）。",
		"rewards": {"money": 16, "favor": {"xiao": 1}}, "favor_cap": 3,
	},
	"herb_errand": {
		"name": "溪谷尋藥", "npc": "tao", "cost": 2, "kind": "explore", "location": "grove", "battle": "grove", "repeatable": false,
		"description": "沿青篁溪谷尋回失落的藥籃，辨認草葉，再清出安全的回程。",
		"reward_text": "回復藥 +3、見識 +1、陶掌櫃信任 +2、盤纏 +8 文；藥鋪出身另得一份藥。",
		"rewards": {"medicine": 3, "insight": 1, "money": 8, "favor": {"tao": 2}},
	},
	"grove_survey": {
		"name": "青篁訪路", "npc": "lin", "cost": 2, "kind": "explore", "location": "grove", "battle": "grove", "repeatable": false,
		"description": "替林知微核對舊地圖。水痕、竹刻和岔路，各有一種不會說話的證詞。",
		"reward_text": "見識 +2、林知微信任 +1；記下一次探索經歷。",
		"rewards": {"insight": 2, "favor": {"lin": 1}},
	},
	"ridge_tracks": {
		"name": "望風尋跡", "npc": "lu", "cost": 3, "kind": "explore", "location": "ridge", "battle": "ridge", "repeatable": false,
		"description": "沿望風古道追尋陸行雲留下的足跡。這條路教的是身法，也是如何選路。",
		"reward_text": "見識 +2、陸行雲信任 +2，學會「掠影突進」。",
		"rewards": {"insight": 2, "skills": ["cloud_step"], "favor": {"lu": 2}},
	},
	"escort_promise": {
		"name": "守約護送", "npc": "zhou", "cost": 3, "kind": "explore", "location": "ridge", "battle": "ridge", "repeatable": false,
		"description": "替驛站護送遲到的藥箱，走完那段人人都想改口取消的山路。",
		"reward_text": "盤纏 +32 文、武學 +1、見識 +1、周主事信任 +2，得到守約證明。",
		"requires": {"completed": "courier_work"}, "rewards": {"money": 32, "training": 1, "insight": 1, "favor": {"zhou": 2}},
	},
	"bridge_repair": {
		"name": "小橋補板", "npc": "lin", "cost": 2, "kind": "task", "location": "wangxi", "repeatable": false,
		"description": "備木料、量橋板，讓河邊的老人不用再繞遠路。做完還要試試腳下穩不穩。",
		"reward_text": "見識 +1、林知微信任 +2、陸行雲信任 +1；木料費 12 文。",
		"fee": 12, "rewards": {"insight": 1, "favor": {"lin": 2, "lu": 1}},
	},
	"missing_letter": {
		"name": "未送達的信", "npc": "zhou", "cost": 2, "kind": "task", "location": "wangxi", "repeatable": false,
		"description": "一封退回多次的信，只寫著舊稱呼。從鎮上的人情裡找到真正的收信人。",
		"reward_text": "見識 +1、周主事信任 +2、沈師傅信任 +1，得到守約證明。",
		"rewards": {"insight": 1, "favor": {"zhou": 2, "shen": 1}},
	},
	"old_ballad": {
		"name": "半支舊曲", "npc": "xiao", "cost": 2, "kind": "story", "repeatable": false,
		"description": "聽蕭小滿唱完她總在中途停下的曲子，也替一位遠客找到回家的地名。",
		"reward_text": "見識 +2、蕭小滿信任 +2。", "rewards": {"insight": 2, "favor": {"xiao": 2}},
	},
	"hermit_visit": {
		"name": "風亭問路", "npc": "lu", "cost": 2, "kind": "story", "repeatable": false,
		"description": "帶著自己的見聞去找陸行雲。他會問你繞過什麼，也會問你為誰停過步。",
		"reward_text": "見識 +2、武學 +1、陸行雲信任 +2；需要見識 3。",
		"requires": {"insight": 3}, "rewards": {"insight": 2, "training": 1, "favor": {"lu": 2}},
	},
	"medicine_lesson": {
		"name": "藥鋪學方", "npc": "tao", "cost": 2, "kind": "story", "repeatable": false,
		"description": "把認草藥的功夫用在真正需要的人身上，學會包好一份能帶上山路的藥。",
		"reward_text": "回復藥 +3、見識 +1、陶掌櫃信任 +1；藥鋪出身另得一份藥。",
		"rewards": {"medicine": 3, "insight": 1, "favor": {"tao": 1}},
	},
	"meditate": {
		"name": "檐下讀記", "npc": "lin", "cost": 1, "kind": "story", "repeatable": true,
		"description": "坐在書攤檐下，把一路見過的細節記清楚。書頁能助你入門，更多見識仍在路上。",
		"reward_text": "見識 +1；此活動只可將見識提升至 6。", "insight_cap": 6, "rewards": {"insight": 1},
	},
	"rest": {
		"name": "歇腳備藥", "npc": "tao", "cost": 1, "kind": "rest", "repeatable": true,
		"description": "歇一歇腳，讓陶掌櫃替你備一小包路上用的藥。",
		"reward_text": "回復藥 +1；度過一個時段。", "rewards": {"medicine": 1},
	},
}

const EXPLORATIONS = ["herb_errand", "grove_survey", "ridge_tracks", "escort_promise"]
const MAX_SLOTS = 21
const MEDICINE_PRICE = 12

static func activities_for(npc: String) -> Array:
	var result: Array = []
	for id in ACTIVITIES:
		if str(ACTIVITIES[id].npc) == npc:
			result.append(id)
	return result
