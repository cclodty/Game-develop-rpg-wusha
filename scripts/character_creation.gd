class_name WeiyuanCreation
extends RefCounted
## Read-only authored scenes and deterministic creation rules. No run/save side effects.

const VERSION = 1
const BASE = 4
const MAX_MOVES = 2
const ATTRIBUTE_KEYS = ["constitution", "strength", "agility", "resolve", "aptitude", "fortune"]
const LABELS = {"constitution": "根骨", "strength": "力道", "agility": "身法", "resolve": "定力", "aptitude": "悟性", "fortune": "機緣"}
const EFFECTS = {
	"constitution": "最大氣血為 52＋根骨×3。",
	"strength": "每回合第一張攻擊牌，整張額外造成力道÷2取整傷害。",
	"agility": "每回合第一張提供防護的牌，額外獲得身法÷2取整防護。",
	"resolve": "每場開局可換牌一次，上限為 1＋定力÷3取整張。",
	"aptitude": "悟性達 6，首次精修只需 1 點心得；一般需 2 點。",
	"fortune": "機緣達 6，首次外出提前得知一條線索；仍須親自調查。",
}
const MOTIVATIONS = {
	"prove": {"id": "prove", "label": "想把難事做成", "text": "你出門，是想親手做成一件從前做不到的事。"},
	"discover": {"id": "discover", "label": "想看懂更大的世界", "text": "你想看看書頁與傳聞之外，真正的江湖是什麼樣子。"},
	"belong": {"id": "belong", "label": "想找到願意留下的地方", "text": "你想找到值得相處的人，以及自己願意長久做的事。"},
}
const FAMILIARS = {"herbalist": {"name": "陶半夏", "portrait": "tao"}, "courier": {"name": "周望山", "portrait": "zhou"}, "performer": {"name": "蕭小滿", "portrait": "xiao"}}

const QUESTIONS = [
	{
		"id": "reason", "chapter": "收拾行囊", "title": "這一趟，為自己走", "speaker": "你", "portrait": "hero", "location": "wangxi",
		"body": "天還沒亮，屋裡只點著一盞小燈。行囊放在桌上，收了又打開；舊衣、盤纏和一路要用的東西，每一樣都像還有話沒交代。\n\n門外有人催車，卻沒有催你回答。你原以為只要把東西裝好，出發便是一件很簡單的事。真到了這一刻，反而想起許多沒做完的小事：半本沒看完的書，一個下回再說的約定，還有別人口中那個『等你長大』。\n\n望溪鎮就在山的另一邊。你尚未決定要拜誰為師，也沒有人替你寫好往後的路。若這一趟終於能由自己作主，你最想帶走的是哪個念頭？",
		"prompt": "你把行囊繩結握在手裡，想了想……",
		"choices": [
			{"label": "我想親手做成一件，以前總做不到的事。", "attribute": "strength", "tag": "prove", "echo": "為了親手做成難事而出發。", "response": "你想起那次沒能獨自完成的差事。當時旁人說了一聲『下回吧』，你也笑著點頭，心裡卻一直留著那一小塊不服氣。\n\n這回不必先把話說得很大。能多擔一點、把一件事做完，便算向前走了一步。你把最重的一包挪到背上試了試，再放下調整繩子；想做成事，不等於非要逞強。\n\n你沒有把『一定成為大俠』寫進行囊。那裡放不下這麼大的字，倒放得下一雙肯走路的鞋。門外的車鈴又響了一聲，你應了一句：『來了。』"},
			{"label": "我想看看，傳聞以外的江湖到底是什麼樣子。", "attribute": "aptitude", "tag": "discover", "echo": "為了看懂傳聞以外的世界而出發。", "response": "你把讀過的故事想了一遍。書裡的人走進客棧，總會遇到大事；可寫書的人沒說，若只是遇見一碗很好吃的麵，算不算值得記下的一天。\n\n你決定親自去看。也許江湖比故事熱鬧，也許沒有想像中威風；看見不一樣的地方時，先別急著說誰錯了。行囊側袋裡，你留下一小疊空紙，好記自己真正遇到的事。\n\n燈芯輕輕跳了一下。你發覺自己最期待的，竟不是找到一個答案，而是終於可以問一些從前不知道怎麼問的問題。"},
			{"label": "我想找到一些人和事，讓我願意認真留下。", "attribute": "resolve", "tag": "belong", "echo": "為了找到願意留下的人與事而出發。", "response": "你並不討厭原來的日子。正因為有值得惦記的人，才知道『留下』不能只是沒有別處可去；它也可以是一件自己認真選過的事。\n\n路上也許會有人招手，也許有些門一時還進不去。你想先把人認清，把事情做過，再決定什麼值得長久放在心上。這個念頭不響亮，卻像行囊底那件舊衣，放進去就踏實了。\n\n你回身把小燈熄好，沒有把門帶得很重。離開並不等於忘記。等下次回來，你希望能慢慢說清楚：這一程，自己為什麼停下，又為什麼往前。"},
		],
	},
	{
		"id": "packing", "chapter": "收拾行囊", "title": "最後一點空處", "speaker": "你", "portrait": "hero", "location": "wangxi",
		"body": "行囊已經裝得差不多，你卻又解開一次。出發的車會在午前翻過山口，午後可能有雨。坐在車上聽起來省力，但誰也不知道哪一段要下來走。\n\n桌角還放著乾糧與布條，鞋帶有一截磨出了毛邊，信封上寫著望溪鎮一位熟人的名字。它們都用得上，卻不必每樣都做得十全十美才能啟程。\n\n你聽見趕車的人在門外和鄰居說笑。等車的人並沒有只顧自己的行囊，有人替另一人扶著包袱，有人把沿路的地名又念了一遍。出門前剩下這一小會兒，你打算先把哪一件事做好？",
		"prompt": "你留下一點工夫，準備自己的第一段路。",
		"choices": [
			{"label": "把乾糧和布條分好，讓路上能吃好、歇好。", "attribute": "constitution", "tag": "supplies", "echo": "出發前先照顧一路的吃食與歇腳。", "response": "你把乾糧分成幾份，留一份放在伸手就拿得到的地方；布條捲好，沒有塞到行囊最底下。做完以後，東西並沒有變多，取用卻比方才順手。\n\n有人笑你像要走很遠。你也笑了：眼下只走到望溪，往後多遠，得等走到以後才知道。先把今天照顧好，並不妨礙以後想得遠一點。\n\n上車時，你特地試了試肩帶。它還是有些重，但已經不是一團讓人心慌的重量。車輪開始轉動，你把最後一口溫水喝完，將空碗好好放回原處。"},
			{"label": "重繫鞋帶，將常用的東西換到順手的位置。", "attribute": "agility", "tag": "light", "echo": "整理鞋帶與行囊，讓轉身取物更俐落。", "response": "你蹲下重新繫鞋帶，又站起來走了兩步。那截磨毛的繩子還能用，只是不能再讓它拖在腳邊。你將最常用的小包移到側邊，試著轉身，果然少了一點牽扯。\n\n這不是讓行囊憑空變輕的祕法。你只是終於分清楚，哪些重量非帶不可，哪些麻煩是自己隨手放出來的。旁人遞來包袱時，你騰出手接過，沒有再被肩帶絆住。\n\n車鈴響起，你最後回望了一眼門口。今天的第一個長進，沒有劍光，也沒有掌聲，只是上車那一步，比方才走得穩了一點。"},
			{"label": "把介紹信收好，再向同行的人打聲招呼。", "attribute": "fortune", "tag": "introduce", "echo": "帶好介紹信，也記住了同行人的稱呼。", "response": "你將信封另包一層，免得午後的雨把字淋開。接著走到車旁，問清楚同路人的稱呼。有位挑貨的大叔說自己耳背，名字最好喊大聲些；你照做，他便笑著替你挪出一個位置。\n\n這一聲招呼不保證路上事事順利，卻讓幾個陌生人不再只能互相叫『喂』。你也聽見了望溪鎮的消息：哪家湯熱，哪段坡滑，誰家門口有地方晾濕衣。\n\n車子動起來時，介紹信仍好好收在衣襟裡。你覺得路沒有忽然變短，但沿途可以開口詢問的地方，似乎多了一些。"},
		],
	},
	{
		"id": "mud", "chapter": "雨前的驛車", "title": "車輪停在半坡", "speaker": "同行人", "portrait": "hero", "location": "ridge",
		"body": "午後的雲壓低了。驛車在山口停了一回，再往前走，左輪便慢慢陷進一處被雨泡軟的泥窩。趕車人剛一催，輪子空轉，濕泥濺到所有人鞋邊。\n\n車上沒有需要爭奪的寶物，只有藥箱、布匹、幾包要送進鎮的日用品。可若把它們淋壞，今晚就會有幾戶人家白等。另一邊的車輪還站在硬地上，車身歪著，暫時不算危險。\n\n大家七嘴八舌說了幾句，都想幫忙，卻還沒有人把第一步定下來。你下車看了看。離下雨還有一點工夫，但每試錯一次，輪子都可能再陷深一點。",
		"prompt": "你先從哪裡著手？",
		"choices": [
			{"label": "先把靠左的貨卸下來，減輕陷輪的重量。", "attribute": "strength", "tag": "unload", "echo": "陷車時先卸貨減重，再想辦法推車。", "response": "你沒有立刻喊大家一起推，而是先接下靠左的一包貨。東西比看起來沉，你換好手位才慢慢往下放。旁邊的人見狀，順著你的次序把另外兩包也卸了。\n\n車身稍微回正，趕車人才敢下來看看輪子。泥窩還在，車也沒有自己出來，但眼前至少多了一點能動手的餘地。你把藥箱墊在乾石上，提醒大家別讓箱底沾水。\n\n有人說：『再推一回？』你望向雲底，又看向地上的貨。這一步做成了，還有下一步；卸下來的東西也得有人照顧，不能一轉身就忘了。"},
			{"label": "先扶住車身，讓人下車、把重心慢慢移回來。", "attribute": "constitution", "tag": "brace", "echo": "陷車時先穩住車身，讓同行人從容下來。", "response": "你先站到不滑的那一側，扶住車架，請車上的人一個一個下來。第一位下車時還有些慌，腳往泥邊探，你提醒他看你的鞋，再把落腳處讓出來。\n\n扶車不像故事裡托住千斤巨石那樣威風。手臂會酸，鞋底會滑，你得不斷換一點力，讓自己也站得穩。最後一人下車後，大家才終於能一起看清輪子陷在哪裡。\n\n車沒有翻，也還沒脫困。趕車人向你點頭，將一根較結實的木棍拿過來。你把手慢慢鬆開，抖掉掌心的泥，準備和他們商量下一步。"},
			{"label": "先看清輪子卡住的位置，找一個能墊實的支點。", "attribute": "aptitude", "tag": "observe", "echo": "陷車時先找支點，分清輪子為何空轉。", "response": "你蹲到輪旁，沒有把手伸進車輪底下。外圈的泥看起來很深，真正讓輪子空轉的，卻是下面一小段被水沖走的硬地。若繼續直推，只會把那一處刨得更空。\n\n你指給趕車人看，請他暫時別催車，又將附近一塊鬆石搬到邊上比了比。石頭還不夠大，方向也得再調整，但大家第一次知道，力氣應該送往哪裡。\n\n『原來不是多喊兩聲就行。』有人說。你笑了一下，站起來時才發現褲腳已沾滿泥。把問題看清楚，也得付出一點實在的髒鞋錢。"},
		],
	},
	{
		"id": "rain", "chapter": "雨前的驛車", "title": "讓力氣往同一處去", "speaker": "同行人", "portrait": "hero", "location": "ridge",
		"body": "第一步有了著落，山風卻也帶來幾點雨。遠處不算晴，近處還能看得清；大家都知道要快一些，但越急，說話的人反而越多。\n\n趕車人拿出繩子，同行的大叔找了一塊木板。前方坡邊有幾塊乾石，另一輛車正慢慢靠近。能用的東西和人都在，只是需要有人把它們接在一起。\n\n你低頭看看自己沾泥的手。剛才的辦法並沒有讓你突然成為領頭的大俠，但同行的人開始願意聽你把話說完。這回，你準備怎樣讓大家一起把車送出泥窩？",
		"prompt": "雨點落在車棚上，你作了下一個決定。",
		"choices": [
			{"label": "去坡邊取乾石，先把輪子前方的短路墊實。", "attribute": "agility", "tag": "fetch", "echo": "雨來時往返取石，補出一段可用的路。", "response": "你沿著硬地走到坡邊，沒有抄看起來更近的滑泥。石頭一次搬不了很多，便挑合手的帶回；轉身前先踩實，比摔一跤再站起來省事。\n\n大家接過你找來的乾石，將木板墊在上面。這不是一條漂亮的新路，只夠車輪向前走半步。可眼下，半步就很有用。你回到輪旁時，肩上已經有了雨痕。\n\n趕車人把繩子收緊，其他人站好位置。你沿剛才走過的那一小段檢查一遍，確認沒有人把腳放進車輪要經過的地方，才抬手示意可以試了。"},
			{"label": "先說清拉與推的次序，讓大家聽同一個口令。", "attribute": "resolve", "tag": "steady", "echo": "雨來時穩住節奏，讓推拉的人同時出力。", "response": "你先請大家停一小會兒。並不是雨忽然不急了，而是有人向前推、有人向後拽，再大的力也只會讓車在原處搖。你把先墊板、再收繩、最後推車的次序說了一遍。\n\n大叔聽到一半便問：『誰喊？』你本想指別人，話到嘴邊又收回來。既然是自己提的辦法，就先把這一回喊清楚。聲音不用像戲台那麼響，要讓每個動手的人聽見便夠了。\n\n第一聲只讓大家試試鬆緊。第二聲，繩子同時拉直。你聽見輪軸動了一點，沒有急著喊第三聲，先確認每個人都還站穩。"},
			{"label": "向後車說明情況，借一條繩，也請對方搭把手。", "attribute": "fortune", "tag": "ask", "echo": "雨來時向後車借力，把陌生人也請進合作裡。", "response": "你走到後車旁，先說清前面沒有受傷的人，也不是要攔路收錢。對方原本有些戒備，聽見只缺一條繩，便探頭看看，將捲好的粗繩遞給你。\n\n你沒有把幫忙當作理所當然，問了繩子怎麼綁、回鎮後送去哪裡。對方索性下車指給你看，同行的大叔便騰出位置，讓新來的人也能站穩。多一個人，不是多一聲口號，而是多了一處真正用得上的力。\n\n你將名字和還繩的地方記在心裡。眼前這點機會，不是從天上落下的福氣；它是有人願意開口，也有人願意回答。"},
		],
	},
	{
		"id": "last_load", "chapter": "雨前的驛車", "title": "出泥以後，還有半段路", "speaker": "你", "portrait": "hero", "location": "ridge",
		"body": "輪子終於越過木板，車身在硬地上輕輕一震。有人笑出聲，接著才記起喘氣。雨沒有變大，卻已把坡邊那條近路淋得發亮。\n\n還有最後一箱貨、幾件工具，以及剛才借來的東西要收好。若只顧著把車推上去就走，眼前的成功也會留下別人的麻煩。趕車人看了看天色，說望溪的燈已經不遠了，不必為了快一口氣再出差錯。\n\n你擦掉額角的汗，站在車旁想了一下。最難的那一下已經過去，接下來更容易讓人鬆懈。你準備怎樣把這件事好好收尾？",
		"prompt": "你把注意力放回還沒完成的地方。",
		"choices": [
			{"label": "接過最後一箱，陪走慢的人一起上到硬地。", "attribute": "constitution", "tag": "carry", "echo": "脫困後接過最後一箱，陪同行人走完餘路。", "response": "你接過貨箱時，手臂立刻提醒你方才已經用過不少力。於是你沒有急著抬高，只把箱底托穩，和走得較慢的人約好一步一步來。\n\n這半段路比想像中安靜。沒有人再喊口令，你聽見鞋底離開濕泥的聲音，也聽見同行的人終於能慢慢把氣喘勻。到了硬地，你先放好箱子，再扶著車架歇了一會兒。\n\n後來大家說起脫困的那一刻，多半記得輪子突然動起來。你還記得最後這幾步：事情做完以前，願意陪人慢一點，也是把路走完的一種本事。"},
			{"label": "按次序清點貨物和借物，確認沒有人落下。", "attribute": "resolve", "tag": "sequence", "echo": "脫困後核對人貨與借物，將收尾也列進承諾。", "response": "你請大家先別急著上車，照剛才卸下的次序把東西點回去。藥箱一只、布包兩件、木板一塊，借來的繩子另放。數到最後，果然有一小包布條留在乾石旁。\n\n有人笑著說你比趕車的還像趕車的。你也笑，卻仍將同行的人看過一遍，等最後一人坐穩才把車沿的包袱推好。認真不必擺出嚴厲的臉，只需要肯多看那一眼。\n\n車輪再次轉動時，你將沒做完的事一件件從心裡放下。今晚若有人問這趟路怎麼樣，你大概會先說：大家都到了，該送的東西也都還在。"},
			{"label": "先試走一段乾路，替大家指出避開滑泥的落腳處。", "attribute": "agility", "tag": "path", "echo": "脫困後試出乾路，替同行人標清落腳處。", "response": "你沒有一口氣跑到前面，而是先走幾步，再回頭看看後面的人能不能照著走。自己跨得過的水窪，挑著箱子的人未必跨得過；你便換了一處稍遠、卻較寬的乾石。\n\n這一次，你找的不是只讓自己快的路。當最後一人從你指過的地方走上來，你才把鞋邊的泥刮掉，回到車旁。那幾個落腳處很小，天一黑可能就看不見了，眼下卻正好派上用場。\n\n你抬頭，看見山口那邊已有一點燈。望溪鎮沒有因此近很多，但你開始懂得，帶人走到地方與自己先到，原來是兩件不同的事。"},
		],
	},
	{
		"id": "reflection", "chapter": "入鎮歇腳", "title": "把今天說給一個人聽", "speaker": "熟人", "portrait": "familiar", "location": "wangxi",
		"body": "望溪鎮的燈亮起來時，你終於坐到一張不會搖晃的凳子上。屋簷擋住了雨，熱水放在手邊，行囊倚著桌腳。眼下沒有人催你去見師傅，也沒有人要求你立刻想清楚將來。\n\n你把陷車的事從頭說起。說到一半，才發現自己記得最清楚的，不一定是輪子動起來的那一下；有些很小的動作，當時忙著做，現在坐下來才知道它為什麼要緊。\n\n對方沒有急著替你下結論，只將熱水推近一點。『若再走一次，你最想記住什麼？』這不是要你選一個最像大俠的答案，只是請你替今天留下一句自己的話。",
		"prompt": "你想把哪一點，帶到明天？",
		"choices": [
			{"label": "能動手的時候，我想真的替眼前的事出一份力。", "attribute": "strength", "tag": "act", "echo": "回望途中，想記住親手出力的踏實。", "response": "你望著掌心洗不掉的一點泥，說自己想記住動手以後的感覺。不是每件事都能靠自己做完，但若總等旁人先開始，就很難知道自己能做到哪裡。\n\n你也承認，今日有幾回差點使蠻力，幸好旁人出聲提醒。願意出力與願意聽人說話，並不衝突。明天若要學武，你希望學到的也不只是一個好聽的招名，而是知道這份力該放在哪裡。\n\n說完這些，你才發覺肚子餓了。桌上的飯仍熱著，今晚的第一件大事，於是變成了把飯好好吃完。至於山門，留待天亮再看。"},
			{"label": "我想先看懂事情，再決定自己的下一步。", "attribute": "aptitude", "tag": "understand", "echo": "回望途中，想記住先弄清楚再行動。", "response": "你說起泥窩、木板和那條看似很近的滑路。它們都沒有藏什麼驚天祕密，只是需要人肯停一下，把眼前的東西看清楚。看懂以後，下一步才不會只剩碰運氣。\n\n但你也記得，若一直只看不動手，雨仍會落下來。你想學的是找到足夠開始的線索，再讓做過的事教自己修正。明天遇見新的人、新的武學，也可以照這樣慢慢認識。\n\n窗外的雨輕了些。你將今天最想記住的一句話放在心裡，沒有急著把它說成道理；能在下一件小事用上，就已經很好。"},
			{"label": "我想記住同行的人；能開口，也要記得回應。", "attribute": "fortune", "tag": "together", "echo": "回望途中，想記住同行與互相回應的機會。", "response": "你先念了幾個剛記住的稱呼，怕睡一覺就忘。陷車時有人遞木板，有人借繩，也有人只是替你扶穩了那只貨箱。若少掉其中一個，今天大概都沒有這樣從容。\n\n你不覺得自己遇上的全是大俠。他們也會嫌泥深、怕淋雨、惦記晚飯；正因如此，那一聲願意幫忙才顯得真切。以後若輪到別人開口，你也想記得今天有人怎樣回答自己。\n\n桌上的熱氣慢慢散開。你忽然不再急著問江湖到底有多遠。至少今晚，有個地方願意聽你把一天的事說完，而你也願意好好記住。"},
		],
	},
]

static func draft() -> Dictionary:
	return {"version": VERSION, "answers": [-1, -1, -1, -1, -1, -1], "adjustments": [], "page": "question", "question": 0, "review_return": false, "move_source": ""}

static func default_completed() -> Dictionary:
	var result = draft()
	for index in range(6):
		result = with_answer(result, index, 0).creation
	result.page = "summary"
	return result

static func with_answer(state: Dictionary, index: int, choice: int) -> Dictionary:
	var check = validate(state)
	if not check.ok: return check
	if index < 0 or index >= QUESTIONS.size() or choice < 0 or choice >= 3:
		return _fail("這個選擇不存在。")
	for earlier in range(index):
		if int(state.answers[earlier]) < 0: return _fail("請先走完前面的路。")
	var next = state.duplicate(true)
	next.answers[index] = choice
	next.adjustments = []
	next.move_source = ""
	next.question = index
	next.page = "aftermath"
	return {"ok": true, "message": "已記下選擇。", "creation": next}

static func move_point(state: Dictionary, source: String, destination: String) -> Dictionary:
	var check = validate(state, true)
	if not check.ok: return check
	if source not in ATTRIBUTE_KEYS or destination not in ATTRIBUTE_KEYS or source == destination:
		return _fail("請選兩項不同的能力。")
	if state.adjustments.size() >= MAX_MOVES: return _fail("已挪動兩點；可重設微調後重新分配。")
	var values = _attributes(state)
	if int(values[source]) <= 2: return _fail("能力最低為 2。")
	if int(values[destination]) >= 8: return _fail("能力最高為 8。")
	var next = state.duplicate(true)
	next.adjustments.append({"from": source, "to": destination})
	next.move_source = ""
	return {"ok": true, "message": "%s -1，%s +1。" % [LABELS[source], LABELS[destination]], "creation": next}

static func reset_adjustments(state: Dictionary) -> Dictionary:
	var check = validate(state)
	if not check.ok: return check
	var next = state.duplicate(true)
	next.adjustments = []
	next.move_source = ""
	return {"ok": true, "message": "已回到六次選擇形成的能力。", "creation": next}

static func validate(state: Dictionary, require_complete: bool = false) -> Dictionary:
	if not _integer(state.get("version"), VERSION, VERSION): return _fail("建角資料版本不符。")
	if not state.get("answers") is Array or state.answers.size() != 6: return _fail("建角選擇資料不完整。")
	var gap = false
	var complete = true
	for answer in state.answers:
		if not _integer(answer, -1, 2): return _fail("建角選項超出範圍。")
		if int(answer) == -1:
			gap = true
			complete = false
		elif gap:
			return _fail("建角故事不可跳過尚未作答的段落。")
	if require_complete and not complete: return _fail("請先走完六段選擇，再確認能力。")
	if not state.get("adjustments") is Array or state.adjustments.size() > MAX_MOVES: return _fail("微調最多挪動兩點。")
	if not complete and not state.adjustments.is_empty(): return _fail("六段選擇完成後才能微調。")
	var values = _base_attributes(state)
	for adjustment in state.adjustments:
		if not adjustment is Dictionary: return _fail("微調資料格式不符。")
		var source = str(adjustment.get("from", ""))
		var destination = str(adjustment.get("to", ""))
		if source not in ATTRIBUTE_KEYS or destination not in ATTRIBUTE_KEYS or source == destination: return _fail("微調能力不存在或相同。")
		values[source] -= 1
		values[destination] += 1
		if int(values[source]) < 2 or int(values[destination]) > 8: return _fail("能力需維持在 2 至 8。")
	if str(state.get("page", "")) not in ["question", "aftermath", "summary", "review"]: return _fail("找不到建角頁面。")
	if not _integer(state.get("question"), 0, 5) or not state.get("review_return") is bool: return _fail("建角頁面位置不正確。")
	if state.page in ["summary", "review"] and not complete: return _fail("尚未完成的旅程不能進入總覽。")
	if state.page == "aftermath" and int(state.answers[int(state.question)]) < 0: return _fail("尚未選擇，不能跳到回應。")
	if state.review_return and not complete: return _fail("回看需要先走完六段選擇。")
	if not state.get("move_source", "") is String or str(state.get("move_source", "")) not in ATTRIBUTE_KEYS + [""]: return _fail("找不到微調中的能力。")
	for earlier in range(int(state.question)):
		if int(state.answers[earlier]) < 0: return _fail("目前頁面前仍有未完成選擇。")
	return {"ok": true, "message": "建角資料有效。", "complete": complete}

static func final_attributes(state: Dictionary) -> Dictionary:
	return _attributes(state) if validate(state).ok else {}

static func effect_text(attribute: String, value: int) -> String:
	match attribute:
		"constitution": return "最大氣血 %d（52＋根骨×3）。" % (52 + value * 3)
		"strength": return "每回合首張攻擊牌額外 +%d 傷害；整張只加一次。" % floori(float(value) / 2.0)
		"agility": return "每回合首張提供防護的牌，額外 +%d 防護。" % floori(float(value) / 2.0)
		"resolve": return "每場開局可換牌一次，最多換 %d 張。" % (1 + floori(float(value) / 3.0))
		"aptitude": return "首次精修省 1 點心得：只需 1 點，往後需 2 點。" if value >= 6 else "精修需 2 點心得；悟性達 6 時首次省 1 點。"
		"fortune": return "首次外出提前獲得一條路線提示；仍須親自調查。" if value >= 6 else "親自調查同樣能取得核心線索與招式；達 6 可提早得提示。"
	return ""

static func card_advice(state: Dictionary) -> String:
	var values = final_attributes(state)
	if values.is_empty(): return ""
	var common = "起始十張牌：出劍、架勢、調息、審勢、虛招各兩張。先讀敵人意圖，再安排攻防；調息補真氣，審勢找牌。"
	if int(values.strength) > int(values.agility): return common + " 你的首張攻擊較有力，可留意第一張出劍的時機。"
	if int(values.agility) > int(values.strength): return common + " 你的首張防護較厚，可先用架勢穩住再回擊。"
	return common + " 目前攻防均衡，可以先嘗試防護與虛招的搭配。"

static func summary(state: Dictionary) -> Dictionary:
	var check = validate(state)
	if not check.ok: return {"complete": false, "attributes": {}, "base_attributes": {}, "motivation": {}, "echoes": [], "choice_echoes": {}, "answer_rows": [], "moves_used": 0}
	var echoes: Array = []
	var rows: Array = []
	var choice_echoes: Dictionary = {}
	var motivation: Dictionary = {}
	for index in range(6):
		var selected = int(state.answers[index])
		if selected < 0: continue
		var question: Dictionary = QUESTIONS[index]
		var choice: Dictionary = question.choices[selected]
		echoes.append(str(choice.echo))
		rows.append({"question_index": index, "choice_index": selected, "question": question.title, "answer": choice.label, "attribute": choice.attribute, "label": LABELS[choice.attribute], "effect": "%s +1" % LABELS[choice.attribute]})
		if index == 0: motivation = MOTIVATIONS[choice.tag].duplicate(true)
		if index == 2: choice_echoes.approach = choice.tag
		if index == 3: choice_echoes.support = choice.tag
		if index == 4: choice_echoes.finish = choice.tag
	return {"complete": bool(check.complete), "attributes": _attributes(state), "base_attributes": _base_attributes(state), "motivation": motivation, "echoes": echoes, "choice_echoes": choice_echoes, "answer_rows": rows, "moves_used": state.adjustments.size()}

static func scene(state: Dictionary, index: int, origin: String, hero_name: String) -> Dictionary:
	var result: Dictionary = QUESTIONS[index].duplicate(true)
	if result.speaker == "你": result.speaker = hero_name
	if result.portrait == "hero": result.portrait = origin
	if index == 0:
		var openings = {"herbalist": "藥鋪師父替你重新貼好瓶上的標記，沒有考你藥名，只問：『這趟不替鋪子送貨，你自己想去做什麼？』", "courier": "驛站的前輩把空信袋還給你，說這趟沒有人催回執：『難得自己的路自己走，想好了為什麼出門沒有？』", "performer": "戲班散了早場，前輩替你收好戲服，笑問：『這回沒有寫好的台詞，你打算怎麼開場？』"}
		result.body = str(openings.get(origin, openings.herbalist)) + "\n\n" + str(result.body)
	if index == 3 and int(state.answers[2]) >= 0:
		result.body = ["卸下的貨已墊好，車身輕了一些；現在要讓輪子跨過泥窩。", "同行人已平安下車，車身也穩住了；現在終於能把力用在輪子上。", "你指出的支點讓大家有了方向；接下來得找齊能把想法做成的東西。"][int(state.answers[2])] + "\n\n" + str(result.body)
	if index == 4 and int(state.answers[3]) >= 0:
		result.body = ["你取來的乾石托住木板，輪子總算有了能咬住的地方。", "大家聽著同一個口令出力，輪子終於沒有再向後打滑。", "後車借來的繩子接上了最後一段力，兩車的人一起把車送了出來。"][int(state.answers[3])] + "\n\n" + str(result.body)
	if index == 5:
		var familiar: Dictionary = FAMILIARS.get(origin, FAMILIARS.herbalist)
		result.speaker = familiar.name
		result.portrait = familiar.portrait
		var greetings = {"herbalist": "陶半夏收下介紹信，先看你的手，再看藥瓶。『藥沒灑就好。人若累了，也別把自己當成不用歇的藥櫃。坐，慢慢說。』", "courier": "周望山接過信袋，這回先放到一旁。『今晚不問你送得多快。鞋上這些泥，看來有一段自己的故事；先喝口水。』", "performer": "蕭小滿把你歪掉的行囊扶正，沒有急著講笑話。『今天沒有人替你打鑼吧？坐下來說說，你自己的第一折，演到哪裡了。』"}
		result.body = str(greetings.get(origin, greetings.herbalist)) + "\n\n" + str(result.body)
	return result

static func response(state: Dictionary, index: int, origin: String, hero_name: String) -> Dictionary:
	var selected = int(state.answers[index])
	var question: Dictionary = QUESTIONS[index]
	var choice: Dictionary = question.choices[selected]
	var result = {"title": "這一步之後", "speaker": hero_name, "portrait": origin, "body": str(choice.response), "location": question.location}
	if index == 5:
		var familiar: Dictionary = FAMILIARS.get(origin, FAMILIARS.herbalist)
		result.speaker = familiar.name
		result.portrait = familiar.portrait
		var endings = {"herbalist": "陶半夏將乾布放在一旁：『明天想學什麼，都先把手擦乾。你的手不只會抓藥，慢慢試。』", "courier": "周望山將空信袋掛好：『明天的行程不用現在交給我。這一次，讓你自己的名字寫在最前面。』", "performer": "蕭小滿捲好最後一條紅綢：『明天怎麼走還沒寫。先睡一覺，這回我不替你把結局唱完。』"}
		result.body += "\n\n" + str(endings.get(origin, endings.herbalist))
	return result

static func _base_attributes(state: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	for attribute in ATTRIBUTE_KEYS: values[attribute] = BASE
	for index in range(6):
		var selected = int(state.answers[index])
		if selected >= 0: values[QUESTIONS[index].choices[selected].attribute] += 1
	return values

static func _attributes(state: Dictionary) -> Dictionary:
	var values = _base_attributes(state)
	for adjustment in state.adjustments:
		values[adjustment.from] -= 1
		values[adjustment.to] += 1
	return values

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}
