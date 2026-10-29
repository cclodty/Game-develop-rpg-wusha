import {CARDS,ACTORS,INNERS,ITEMS,ENEMIES,TYPES,STARTER,defaultConfig,validateDeck,validateConfig,statsFor} from './catalog.mjs';
import {createBattle,current,living,cardValues,applyAction,previewAction,aiStep,restoreBattle} from './model.mjs';
const KEY='jianghu-combat-lab-v1',app=document.querySelector('#app');
const h=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const btn=(label,action,primary=false,disabled=false)=>`<button data-action="${action}" class="${primary?'primary':''}" ${disabled?'disabled':''}>${label}</button>`;
let config=defaultConfig(),battle=null,tab='hero',selected=-1,target='enemy0',cycleSelection=[],paused=false,modal='',timer=null,storageError='',noticeTimer=null;
function portrait(id){return `<span class="portrait ${id}" aria-hidden="true"><img src="../assets/generated/gal/${id==='hero'?'hero-player':id}.png" alt=""></span>`;}
function art(actor,id){return `../assets/cards/basic/${actor}/${id}.webp`;}
function scale(){const n=Math.min(innerWidth/1440,innerHeight/900);document.querySelector('#viewport').style.cssText=`width:${1440*n}px;height:${900*n}px`;app.style.transform=`scale(${n})`;}
function toast(text){const t=document.querySelector('#toast');t.textContent=text;t.style.display='block';clearTimeout(noticeTimer);noticeTimer=setTimeout(()=>t.style.display='none',4200);}
function envelope(){return {version:1,config,battle,view:{tab,selected,target,cycleSelection,paused}};}
function save(){try{localStorage.setItem(KEY,JSON.stringify(envelope()));}catch{toast('無法寫入瀏覽器；請匯出存檔備份。');}}
function restore(data){if(!data||data.version!==1)throw Error('不是本版試牌存檔。');
  const restored=data.battle?restoreBattle(data.battle):null;
  if(restored){if(JSON.stringify(restored.config)!==JSON.stringify(data.config))throw Error('開戰配置與存檔不符。');}
  else validateConfig(data.config);
  config=data.config;battle=restored;tab=Object.hasOwn(ACTORS,data.view?.tab)?data.view.tab:'hero';selected=Number.isInteger(data.view?.selected)?data.view.selected:-1;target=data.view?.target||'enemy0';
  cycleSelection=Array.isArray(data.view?.cycleSelection)?data.view.cycleSelection.filter(i=>Number.isInteger(i)&&i>=0&&i<(battle?current(battle).hand?.length||0:0)).slice(0,1):[];
  paused=!!data.view?.paused;
}
try{const raw=localStorage.getItem(KEY);if(raw)restore(JSON.parse(raw));}catch(e){storageError=`讀取失敗：${e.message} 原存檔保留；可先匯出原檔備份，或開始新的試牌。`;battle=null;config=defaultConfig();}
function header(){const order=battle?[...battle.order.slice(battle.index),...battle.order.slice(0,battle.index)].map(id=>battle.actors.find(a=>a.id===id)).filter(a=>a.hp>0).map(a=>`${a.name} ${a.speed}`).join(' → '):'';return `<header class="panel row between"><div><h1>江湖未遠 <small>／ 基本牌試牌場</small></h1><p class="muted">${battle?`行動次序：${h(order)}`:"三人獨立牌組 · 抽五張、回合末全棄 · 獨立於劇情保存"}</p></div><div class="row"><a href="../web/">回到劇情</a>${btn('交手規則','rules')}${btn('存讀與備份','saves')}</div></header>`;}
function cardText(c){const out=[];if(c.strip)out.push(`先移除 ${c.strip} 防護`);if(c.damage)out.push(`${c.damage} 傷害`);if(c.block)out.push(`${c.block} 防護`);if(c.draw)out.push(`抽 ${c.draw} 張`);if(c.cycle)out.push('可棄 1 抽 1');if(c.energy)out.push(`真氣 +${c.energy}`);if(c.exhaust)out.push('本場除外');return out.join('；');}
function options(data,value){return Object.entries(data).map(([id,a])=>`<option value="${id}" ${id===value?'selected':''}>${h(a.name)}</option>`).join('');}
function setup(){const a=config.actors[tab],stats=statsFor(tab,a),error=validateDeck(a.deck);
  return `<section class="setup"><div class="row between setup-title"><div><h2>先配招，再看同一副牌如何交手</h2><p class="muted">三人各 15–25 張，基本牌同名最多五張。內功、配裝與牌組在開戰後鎖定。</p></div><div class="roster-tabs row">${Object.entries(ACTORS).map(([id,x])=>btn(x.name,`tab:${id}`,tab===id)).join('')}</div></div><div class="loadout"><aside class="panel loadout-side">${portrait(tab)}<h3>${h(ACTORS[tab].name)}</h3><p class="stats">氣血 ${stats.maxHp}　速度 ${stats.speed}<br>力道 +${stats.power}　護勁 +${stats.guardPower}</p><label>主修內功<select id="inner">${options(INNERS,a.inner)}</select></label><p class="inner-help">${h(INNERS[a.inner].description)}</p><div class="row">${Object.entries(ITEMS).map(([id,x])=>`<label><input type="checkbox" data-item="${id}" ${a.items.includes(id)?'checked':''}>${x.name} +1${id==='wrist'?'力道':'護勁'}</label>`).join('')}</div></aside><div class="panel"><div class="row between"><h3>出戰 ${a.deck.length} 張</h3>${btn('恢復十五張起步牌','starter')}</div><div class="deck-scroll"><div class="deck-grid">${Object.entries(CARDS).map(([id,c])=>{const count=a.deck.filter(x=>x===id).length;return `<article class="deck-card"><img src="${art(tab,id)}" alt="${ACTORS[tab].name}・${c.name}" loading="lazy"><div class="deck-info"><div class="row between"><h3>${c.name}</h3><small>${c.cost} 真氣／${TYPES[c.type]}</small></div><p>${h(cardText({...c,damage:c.damage?c.damage+stats.power:0,block:c.block?c.block+stats.guardPower:0}))}</p><div class="row">${btn('－',`remove:${id}`,false,count===0)}<span class="deck-count">${count} 張</span>${btn('＋',`add:${id}`,false,count>=5||a.deck.length>=25)}</div></div></article>`;}).join('')}</div></div><p class="deck-validation ${error?'invalid':'ready'}">${h(error||'配置可用；學會新招式後，仍由你決定替換哪些牌。')}</p></div></div><div class="settings-bar"><div class="panel"><label>對手 <select id="enemy">${options(ENEMIES,config.enemy)}</select></label><label>人數 <select id="enemy-count"><option value="1" ${config.enemyCount===1?'selected':''}>一人</option><option value="2" ${config.enemyCount===2?'selected':''}>兩人</option></select></label><p class="description">${h(ENEMIES[config.enemy].description)}</p></div><div class="panel"><label>隨機種子 <input id="seed" type="number" min="1" max="4294967295" value="${config.seed}"></label><p class="description">相同配置和種子可重現起手。重試不重新抽種子。</p></div><div class="panel"><div class="row">${Object.entries(ACTORS).map(([id,x])=>`<label><input type="checkbox" data-auto="${id}" ${config.actors[id].auto?'checked':''}>${x.name}自動</label>`).join('')}</div><p class="description">自動出牌只看當前手牌與公開意圖，交手中可暫停接管。</p></div></div><div class="setup-foot"><p class="muted">${h(storageError||'基本牌 v1 · 內功只有一個核心被動；裝備只增加屬性。')}</p>${btn(storageError?'開始新試牌':'開始交手','start',true)}</div></section>`;
}
function intentText(a){const p=a.intent,t=battle.actors.find(x=>x.id===p.target);return `${p.kind==='attack'?`${p.damage} × ${p.hits} 傷害 → ${t?.name||'我方'}`:p.kind==='charge'?'蓄勢，下次準備重擊':p.kind==='counter'?`擺架：首次直接攻擊反制 ${p.counter}`:`獲得 ${p.block} 防護`}${p.kind==='counter'?`；防護 ${p.block}`:''}`;}
function fighter(a){if(a.side==='enemy')return `<article role="button" tabindex="0" aria-label="選擇目標 ${a.name}" data-action="target:${a.id}" class="fighter enemy ${a.hp<=0?'dead':''} ${target===a.id?'targeted':''} ${current(battle).id===a.id?'current':''}"><div class="enemy-symbol">${{flurry:'連',armored:'盾',charging:'蓄',counter:'返'}[a.mode]}</div><h3>${h(a.name)}</h3><div class="hp"><span style="width:${a.hp/a.maxHp*100}%"></span></div><div class="numbers">氣血 ${a.hp}/${a.maxHp}　防護 ${a.block}</div><p class="intent">${a.hp>0?h(intentText(a)):'無力再戰'}</p></article>`;
  return `<article class="fighter ${a.hp<=0?'dead':''} ${current(battle).id===a.id?'current':''}">${portrait(a.id)}<h3>${h(a.name)}</h3><div class="hp"><span style="width:${a.hp/a.maxHp*100}%"></span></div><div class="numbers">氣血 ${a.hp}/${a.maxHp}　防護 ${a.block}<br>真氣 ${a.qi}　力道 ${a.power}　護勁 ${a.guardPower}</div>${btn(a.auto?'自行出牌・接管':'手動・委託',`control:${a.id}`,false,a.hp<=0)}</article>`;
}
function combat(){const a=current(battle),manual=a.side==='ally',choice=battle.choice;
  if(!living(battle,'enemy').some(a=>a.id===target))target=living(battle,'enemy')[0]?.id||'enemy0';
  if(selected>= (a.hand?.length||0))selected=-1;
  let preview='',canPlay=false;
  if(manual&&selected>=0&&!choice){try{const p=previewAction(battle,{type:'play',index:selected,target});preview=p.events.join(' ');canPlay=true;}catch(e){preview=e.message;}}
  return `<section class="scene panel"><div class="fighter-row">${battle.actors.filter(a=>a.side==='ally').map(fighter).join('')}</div><div class="fighter-row">${battle.actors.filter(a=>a.side==='enemy').map(fighter).join('')}</div></section><div class="battle-head"><h2>第 ${battle.round} 輪 · ${h(a.name)}${choice?'／請選擇換出的牌':manual?`／真氣 ${a.qi}`:'／敵方行動'}</h2><div class="row">${btn(paused?'繼續自動':'暫停自動','pause')}${btn('牌堆與紀錄','piles')}${btn('撤退','retreat')}</div></div><div class="hand" aria-label="目前手牌">${manual?a.hand.map((id,i)=>{const c=cardValues(battle,i);return `<button class="card ${c.type} ${selected===i?'selected':''} ${cycleSelection.includes(i)?'choice-selected':''}" data-action="card:${i}" aria-label="${c.name} 第${i+1}張"><div class="card-top"><span>${c.name}</span><span class="card-cost">${c.cost}</span></div><img src="${art(a.id,id)}" alt="${a.name}・${c.name}"><div class="card-effect">${h(cardText(c))}</div><div class="card-owner">${TYPES[c.type]} · ${a.name}${choice?(cycleSelection.includes(i)?' · 準備換出':' · 點選換出'):''}</div></button>`;}).join(''):'<p class="panel">敵人會依上方意圖行動。可暫停檢視紀錄。</p>'}</div><div class="actions">${choice?`${btn(`換出所選 ${cycleSelection.length} 張`,'cycle',true,cycleSelection.length===0)}${btn('不換牌，完成掠步','cycle-skip')}<p class="preview">已支付費用及取得防護；此時可存檔，完成選擇後才繼續。</p>`:`${btn('施展選取的牌','play',true,!manual||!canPlay)}${btn('結束自身行動','end',false,!manual)}<p class="preview">${h(preview||'點選手牌及目標，查看實際效果後施展。')}</p>`}</div><div class="bottom"><span>手牌上限十張 · 防護於自身下次行動清除 · 無勢／運勁／預設留牌</span><span>${h(battle.log.at(-1)||'')}</span></div>`;
}
function dialog(){let title='',body='',footer=btn('返回','close');
  if(modal==='rules'){title='基本牌交手規則';body=`<div class="rules-grid"><section><h3>自己的回合</h3><p>恢復 3 真氣，抽 5 張。結束時全棄，真氣不累積；手牌上限 10 張，滿手就停止抽取。</p><p>抽牌堆空了才洗入棄牌。施展中的牌不會抽回自己；調息本場除外。</p><p>掠步可以不換牌。有實際棄牌才抽等量；行雲訣每次自身行動只回報一次。</p></section><section><h3>屬性與意圖</h3><p>力道加在每張直接攻擊牌一次；護勁加在每張防護牌一次。破防數量不受力道影響。</p><p>敵人段數和目標公開，速度決定行動順序。直接攻擊擺架敵人會受一次反制。</p><p>這裡不消耗劇情日數，也不發劇情獎勵。牌組和配裝開戰後鎖定。</p></section></div>`;}
  if(modal==='saves'){title='保存與備份';body=`<p>試牌場使用自己的存檔，不讀寫劇情進度。每次操作自動保存；換牌中途與選牌狀態也可續接。</p><p>匯入會取代此試牌場進度，劇情存檔不受影響。固定使用同一網址與瀏覽器；本機與公開站需匯出／匯入搬移。</p>${storageError?`<p class="invalid">${h(storageError)}</p>`:''}<div class="row" style="margin-top:20px">${btn('立即保存','save')}${btn('匯出試牌備份','export')}${btn('匯入試牌備份','import')}</div>`;}
  if(modal==='piles'){const a=current(battle);title='牌堆與交手紀錄';body=`${a.side==='ally'?['hand','draw','discard','exhaust'].map(k=>`<h3>${{hand:'手牌',draw:'抽牌堆（不顯示順序）',discard:'棄牌堆',exhaust:'本場除外'}[k]} ${a[k].length}</h3><div class="pile-list">${Object.entries(a[k].reduce((o,id)=>(o[id]=(o[id]||0)+1,o),{})).sort().map(([id,n])=>`<span class="tag">${CARDS[id].name} × ${n}</span>`).join('')||'<small>空</small>'}</div>`).join('<br>'):''}<h3 style="margin-top:18px">紀錄</h3>${battle.log.map(t=>`<p>${h(t)}</p>`).join('')}`;}
  if(modal==='retreat'){title='結束這次試牌？';body='<p>保留本次統計，回到準備後可用同一配置和種子重試。</p>';footer=btn('返回','close')+btn('確認撤退','retreat-confirm',true);}
  if(modal==='reset'){title='回到準備？';body='<p>本次交手已結束，保留牌組、內功、裝備與種子，再次開始會重新洗牌。</p>';footer=btn('返回','close')+btn('回到準備','reset-confirm',true);}
  if(modal==='result'){title={won:'切磋勝出',lost:'此次落敗',retreated:'收招退場'}[battle.status];const m=battle.metrics;body=`<p>基本牌 v1 · ${ENEMIES[config.enemy].name} · 種子 ${config.seed}</p><div class="result-stats">${[['交手輪數',battle.round],['出牌',m.cardsPlayed],['造成傷害',m.damageDealt],['承受傷害',m.damageTaken],['實際棄換',m.discarded],['本場除外',m.exhausted]].map(([label,value])=>`<div class="panel"><strong>${value}</strong>${label}</div>`).join('')}</div><p>這是規則與配招驗證；一次勝出不代表已完成平衡。</p>`;footer=btn('查看紀錄','result-log')+btn('同配置重試','retry',true)+btn('回到配招','reset-confirm');}
  return `<div class="overlay"><section class="dialog panel" role="dialog" aria-label="${title}"><h2>${title}</h2>${body}<footer>${footer}</footer></section></div>`;
}
function schedule(){clearTimeout(timer);if(!battle||battle.status!=='active'||paused||modal)return;const a=current(battle);if(a.side==='enemy'||a.auto)timer=setTimeout(()=>{try{battle=aiStep(battle);selected=-1;cycleSelection=[];save();render();}catch(e){paused=true;toast(e.message);render();}},650);}
function render(){clearTimeout(timer);if(battle&&battle.status!=='active'&&!modal)modal='result';app.innerHTML=header()+(battle?combat():setup())+(modal?dialog():'');scale();schedule();}
function act(command){battle=applyAction(battle,command);selected=-1;cycleSelection=[];save();render();}
app.addEventListener('click',e=>{const button=e.target.closest('[data-action]');if(!button||button.disabled)return;const [action,arg]=button.dataset.action.split(':');try{
  if(['rules','saves','piles','retreat','reset'].includes(action)){modal=action;render();return;}
  if(action==='close'){modal='';render();return;}
  if(action==='tab'){tab=arg;render();return;}
  if(action==='starter'){config.actors[tab].deck=[...STARTER];if(!storageError)save();render();return;}
  if(action==='add'){config.actors[tab].deck.push(arg);try{validateConfig(config);if(!storageError)save();}catch{}render();return;}
  if(action==='remove'){const d=config.actors[tab].deck,i=d.lastIndexOf(arg);if(i>=0)d.splice(i,1);try{validateConfig(config);if(!storageError)save();}catch{}render();return;}
  if(action==='start'){validateConfig(config);battle=createBattle(config);storageError='';selected=-1;cycleSelection=[];paused=false;save();render();return;}
  if(action==='target'){if(!battle.actors.find(a=>a.id===arg)?.hp)return;target=arg;save();render();return;}
  if(action==='card'){if(current(battle).auto)paused=true;const i=Number(arg);if(battle.choice){cycleSelection=cycleSelection.includes(i)?[]:[i];}else selected=i;save();render();return;}
  if(action==='play'){act({type:'play',index:selected,target});return;}
  if(action==='cycle'||action==='cycle-skip'){act({type:'cycle',indices:action==='cycle'?cycleSelection:[]});return;}
  if(action==='end'){act({type:'end'});return;}
  if(action==='control'){const a=battle.actors.find(a=>a.id===arg);act({type:'control',actor:arg,auto:!a.auto});return;}
  if(action==='pause'){paused=!paused;save();render();return;}
  if(action==='retreat-confirm'){modal='';act({type:'retreat'});return;}
  if(action==='reset-confirm'){battle=null;modal='';selected=-1;cycleSelection=[];save();render();return;}
  if(action==='retry'){battle=createBattle(config);modal='';paused=false;selected=-1;cycleSelection=[];save();render();return;}
  if(action==='result-log'){modal='piles';render();return;}
  if(action==='save'){if(storageError&&!battle)throw Error('請先備份原檔，或開始新的試牌。');save();toast('試牌進度已保存。');return;}
  if(action==='export'){const raw=storageError?localStorage.getItem(KEY):JSON.stringify(envelope(),null,2);const link=document.createElement('a'),url=URL.createObjectURL(new Blob([raw||'{}'],{type:'application/json'}));link.href=url;link.download='江湖未遠-試牌場-v1.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);return;}
  if(action==='import'){document.querySelector('#import-save').click();return;}
}catch(e){toast(e.message);}});
app.addEventListener('change',e=>{const el=e.target;if(battle)return;try{
  if(el.id==='inner')config.actors[tab].inner=el.value;
  if(el.dataset.item){const a=config.actors[tab];a.items=el.checked?[...a.items,el.dataset.item]:a.items.filter(i=>i!==el.dataset.item);}
  if(el.dataset.auto)config.actors[el.dataset.auto].auto=el.checked;
  if(el.id==='enemy')config.enemy=el.value;
  if(el.id==='enemy-count')config.enemyCount=Number(el.value);
  if(el.id==='seed')config.seed=Number(el.value);
  try{validateConfig(config);if(!storageError)save();}catch{}render();
}catch(e){toast(e.message);}});
document.querySelector('#import-save').addEventListener('change',async e=>{const file=e.target.files[0];if(!file)return;try{const data=JSON.parse(await file.text());restore(data);storageError='';modal='';save();render();toast('試牌進度已載入。');}catch(error){toast(`匯入失敗，原進度保留：${error.message}`);}e.target.value='';});
app.addEventListener('keydown',e=>{const target=e.target;if(e.key==='Enter'&&target.matches('[role="button"][data-action]'))target.click();});
window.addEventListener('resize',scale);window.addEventListener('beforeunload',()=>{if(!storageError)try{validateConfig(config);save();}catch{}});
render();
