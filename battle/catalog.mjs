export const RULES = 'basic-v1';
export const TYPES = {attack:'攻擊',guard:'防護',skill:'技巧'};
export const CARDS = {
  strike:{id:'strike',family:'basic-strike',tier:0,group:'basic',name:'平擊',cost:1,type:'attack',damage:6,description:'造成 6 傷害。'},
  guard:{id:'guard',family:'basic-guard',tier:0,group:'basic',name:'守勢',cost:1,type:'guard',block:5,description:'獲得 5 防護。'},
  break:{id:'break',family:'basic-break',tier:0,group:'basic',name:'破架',cost:1,type:'attack',strip:6,damage:4,description:'先移除最多 6 防護，再造成 4 傷害。'},
  observe:{id:'observe',family:'basic-observe',tier:0,group:'basic',name:'審勢',cost:1,type:'skill',draw:2,description:'抽 2 張牌。'},
  step:{id:'step',family:'basic-step',tier:0,group:'basic',name:'掠步',cost:1,type:'skill',block:3,cycle:1,description:'獲得 3 防護；可棄另一張牌，再抽 1 張。'},
  breath:{id:'breath',family:'basic-breath',tier:0,group:'basic',name:'調息',cost:0,type:'skill',energy:1,exhaust:true,description:'獲得 1 真氣，本場除外。'},
};
export const ACTORS = {
  hero:{name:'陳天佑',hp:68,speed:6,inner:'guiyuan',color:'indigo'},
  huai:{name:'宋懷晴',hp:66,speed:8,inner:'xingyun',color:'jade'},
  du:{name:'杜蘅',hp:76,speed:5,inner:'shouzhong',color:'slate'},
};
export const INNERS = {
  none:{name:'不主修',description:'不增加屬性或被動。'},
  shouzhong:{name:'守中訣',hp:6,description:'氣血上限 +6。每次自身行動，首張防護牌額外獲得 2 防護。'},
  xingyun:{name:'行雲訣',speed:1,description:'速度 +1。每次自身行動，首次實際棄牌後額外抽 1 張。'},
  guiyuan:{name:'歸元功',power:1,description:'力道 +1。結束時消耗 1 剩餘真氣，下次自身行動多抽 1 張。'},
};
export const ITEMS = {
  wrist:{name:'護腕',slot:'wrist',power:1,description:'力道 +1'},
  coat:{name:'護衣',slot:'body',guardPower:1,description:'護勁 +1'},
};
export const ENEMIES = {
  flurry:{name:'快刀陪練',hp:80,speed:7,description:'連擊：多段攻擊，考驗防護分配。',pattern:[{kind:'attack',damage:4,hits:3},{kind:'attack',damage:10,hits:1},{kind:'guard',block:8}]},
  armored:{name:'持盾陪練',hp:100,speed:7,description:'重甲：厚重防護，破架更有效。',pattern:[{kind:'guard',block:16},{kind:'attack',damage:14,hits:1},{kind:'attack',damage:7,hits:2}]},
  charging:{name:'蓄勁陪練',hp:90,speed:4,description:'蓄勢：先準備，再重擊。',pattern:[{kind:'charge',block:5},{kind:'attack',damage:24,hits:1},{kind:'attack',damage:10,hits:1}]},
  counter:{name:'拆招陪練',hp:90,speed:7,description:'反制：擺架時第一次直接攻擊會受反擊。',pattern:[{kind:'counter',block:8,counter:5},{kind:'attack',damage:12,hits:1},{kind:'guard',block:12}]},
};
export const STARTER = [...Array(5).fill('strike'),...Array(5).fill('guard'),'break','break','observe','step','breath'];
export function validateDeck(deck, catalog=CARDS) {
  if(!Array.isArray(deck)||deck.length<15||deck.length>25) return '每副牌需要 15–25 張。';
  const families={};
  for(const id of deck){
    const card=Object.hasOwn(catalog,id)&&catalog[id];
    if(!card) return '含有尚未學會的招式。';
    const limit=card.group==='basic'?5:2;
    const family=card.family||id;
    const entry=families[family]??={count:0,limit};entry.count++;entry.limit=Math.min(entry.limit,limit);
    if(entry.count>entry.limit) return `同源招式「${card.name}」合計最多 ${entry.limit} 張。`;
  }
  return '';
}
export function defaultConfig(){return {seed:1729,enemy:'flurry',enemyCount:1,actors:Object.fromEntries(Object.entries(ACTORS).map(([id,a])=>[id,{deck:[...STARTER],inner:a.inner,items:[],auto:id!=='hero'}]))};}
export function statsFor(id,loadout){
  const base=ACTORS[id],inner=INNERS[loadout.inner];
  const stats={maxHp:base.hp,power:0,guardPower:0,speed:base.speed};
  for(const bonus of [inner,...loadout.items.map(i=>ITEMS[i])]){
    stats.maxHp+=bonus.hp||0;stats.power+=bonus.power||0;stats.guardPower+=bonus.guardPower||0;stats.speed+=bonus.speed||0;
  }
  return stats;
}
export function validateConfig(config){
  if(!config||!Number.isInteger(config.seed)||config.seed<1||config.seed>4294967295) throw Error('種子須為 1–4294967295 的整數。');
  if(!Object.hasOwn(ENEMIES,config.enemy)||![1,2].includes(config.enemyCount)) throw Error('對手配置無效。');
  for(const id of Object.keys(ACTORS)){
    const a=config.actors?.[id];if(!a||!Object.hasOwn(INNERS,a.inner)||typeof a.auto!=='boolean')throw Error('人物配置無效。');
    const error=validateDeck(a.deck);if(error)throw Error(`${ACTORS[id].name}：${error}`);
    if(!Array.isArray(a.items)||new Set(a.items).size!==a.items.length||a.items.length>2||a.items.some(i=>!Object.hasOwn(ITEMS,i)))throw Error('裝備配置無效。');
    if(new Set(a.items.map(i=>ITEMS[i].slot)).size!==a.items.length)throw Error('同一部位只能裝備一件。');
  }
  return config;
}
