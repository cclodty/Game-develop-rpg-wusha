import {RULES,CARDS,ACTORS,ENEMIES,validateConfig,statsFor} from './catalog.mjs';
const copy=x=>JSON.parse(JSON.stringify(x));
const assert=(ok,message)=>{if(!ok)throw Error(message);};
const integer=(v,min,max)=>Number.isInteger(v)&&v>=min&&v<=max;
export const current=s=>s.actors.find(a=>a.id===s.order[s.index]);
export const living=(s,side)=>s.actors.filter(a=>a.side===side&&a.hp>0);
const counts=p=>{const out={};for(const id of p)out[id]=(out[id]||0)+1;return out;};
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
function random(s){let n=s.rng|0;n^=n<<13;n^=n>>>17;n^=n<<5;s.rng=n>>>0||1;return s.rng/4294967296;}
function shuffle(s,p){for(let i=p.length-1;i>0;i--){const j=Math.floor(random(s)*(i+1));[p[i],p[j]]=[p[j],p[i]];}return p;}
function event(s,type,text,extra={}){s.lastEvents.push({type,text,...extra});s.log.push(text);s.log=s.log.slice(-100);}
function draw(s,a,n){let actual=0;for(let i=0;i<n&&a.hand.length<10;i++){
  if(!a.draw.length){if(!a.discard.length)break;a.draw=shuffle(s,a.discard.splice(0));event(s,'shuffle',`${a.name}洗入棄牌。`);}
  a.hand.push(a.draw.pop());actual++;
}return actual;}
function settle(s){if(!living(s,'enemy').length)s.status='won';else if(!living(s,'ally').length)s.status='lost';}
function hit(s,from,to,amount){if(!to||to.hp<=0||s.status!=='active')return;
  const blocked=Math.min(amount,to.block),lost=Math.min(to.hp,amount-blocked);to.block-=blocked;to.hp-=lost;
  s.metrics[from.side==='ally'?'damageDealt':'damageTaken']+=lost;
  event(s,'hit',`${from.name} → ${to.name}：${lost} 傷害${blocked?`，防護吸收 ${blocked}`:''}`,{from:from.id,target:to.id,damage:lost,blocked});
  if(!to.hp)event(s,'defeat',`${to.name}無力再戰。`,{target:to.id});settle(s);
}
function planEnemy(s,a){const spec=ENEMIES[a.mode],p=spec.pattern[a.turns%spec.pattern.length];a.intentStep=a.turns;
  const allies=living(s,'ally');a.intent={kind:p.kind,damage:p.damage||0,hits:p.hits||0,block:p.block||0,counter:p.counter||0,target:allies[Math.floor(random(s)*allies.length)]?.id||''};a.counterUsed=false;
}
function startTurn(s){const a=current(s);a.turns++;s.turn++;a.block=0;
  if(a.side==='ally'){
    a.qi=3;a.firstGuardUsed=false;a.cycleRewardUsed=false;
    const n=5+a.bonusDraw;a.bonusDraw=0;const actual=draw(s,a,n);
    event(s,'turn',`${a.name}行動：恢復 3 真氣，抽 ${actual} 張。`);
  }else event(s,'turn',`${a.name}依公開意圖行動。`);
}
function advance(s){settle(s);if(s.status!=='active')return;
  for(let i=0;i<s.order.length;i++){s.index++;if(s.index===s.order.length){s.index=0;s.round++;}if(current(s).hp>0){startTurn(s);return;}}
  throw Error('沒有可行動的人物。');
}
export function createBattle(config){validateConfig(config);const s={version:1,rules:RULES,config:copy(config),rng:config.seed,status:'active',round:1,turn:0,index:0,order:[],actors:[],choice:null,inPlay:null,lastEvents:[],log:[],metrics:{cardsPlayed:0,damageTaken:0,damageDealt:0,qiSpent:0,discarded:0,exhausted:0,aiActions:0}};
  for(const [id,base]of Object.entries(ACTORS)){
    const loadout=config.actors[id],stats=statsFor(id,loadout);
    s.actors.push({id,name:base.name,side:'ally',...stats,hp:stats.maxHp,inner:loadout.inner,auto:loadout.auto,qi:0,block:0,hand:[],draw:shuffle(s,[...loadout.deck]),discard:[],exhaust:[],firstGuardUsed:false,cycleRewardUsed:false,bonusDraw:0,turns:0});
  }
  const spec=ENEMIES[config.enemy];for(let i=0;i<config.enemyCount;i++)s.actors.push({id:`enemy${i}`,name:spec.name+(config.enemyCount>1?`・${i+1}`:''),side:'enemy',mode:config.enemy,maxHp:spec.hp,hp:spec.hp,speed:spec.speed,block:0,turns:0,counterUsed:false,intent:null});
  for(const a of living(s,'enemy'))planEnemy(s,a);
  s.order=[...s.actors].sort((a,b)=>b.speed-a.speed||a.id.localeCompare(b.id)).map(a=>a.id);startTurn(s);return validateBattle(s);
}
export function cardValues(s,index){const a=current(s),c=CARDS[a.hand[index]];assert(a.side==='ally'&&c,'沒有這張手牌。');
  return {...c,damage:c.damage?c.damage+a.power:0,block:c.block?c.block+a.guardPower+(a.inner==='shouzhong'&&!a.firstGuardUsed?2:0):0};
}
function finishCard(s){const p=s.inPlay,a=s.actors.find(a=>a.id===p.actor),c=CARDS[p.card];
  (c.exhaust?a.exhaust:a.discard).push(c.id);if(c.exhaust)s.metrics.exhausted++;
  s.inPlay=null;s.choice=null;
  const target=s.actors.find(t=>t.id===p.target);
  if(s.status==='active'&&c.type==='attack'&&target?.hp>0&&target.intent?.counter&&!target.counterUsed){target.counterUsed=true;event(s,'counter',`${target.name}反制這次攻擊。`);hit(s,target,a,target.intent.counter);}
  if(s.status==='active'&&a.hp<=0)advance(s);
}
function play(s,index,targetId){const a=current(s);assert(a.side==='ally'&&!s.choice&&integer(index,0,a.hand.length-1),'現在不能出這張牌。');
  const c=cardValues(s,index),target=s.actors.find(t=>t.id===targetId);
  assert(a.qi>=c.cost,'真氣不足。');if(c.damage||c.strip)assert(target?.side==='enemy'&&target.hp>0,'請選擇仍在場的對手。');
  a.hand.splice(index,1);a.qi-=c.cost;s.metrics.qiSpent+=c.cost;s.metrics.cardsPlayed++;
  s.inPlay={actor:a.id,card:c.id,target:target?.id||null};event(s,'play',`${a.name}施展${c.name}。`,{actor:a.id,card:c.id});
  if(c.strip){const n=Math.min(target.block,c.strip);target.block-=n;event(s,'strip',`移除 ${target.name} ${n} 防護。`);}
  if(c.damage)hit(s,a,target,c.damage);
  if(c.block){a.block+=c.block;a.firstGuardUsed=true;event(s,'guard',`${a.name}獲得 ${c.block} 防護。`);}
  if(c.energy){a.qi+=c.energy;event(s,'qi',`${a.name}獲得 ${c.energy} 真氣。`);}
  if(c.draw){const n=draw(s,a,c.draw);event(s,'draw',`${a.name}抽 ${n} 張牌。`);}
  if(c.cycle&&s.status==='active'){s.choice={actor:a.id,max:c.cycle};return;}
  finishCard(s);
}
function cycle(s,indices){const a=current(s);assert(s.choice&&s.choice.actor===a.id,'沒有待完成的換牌。');
  assert(Array.isArray(indices)&&indices.length<=s.choice.max&&new Set(indices).size===indices.length&&indices.every(i=>integer(i,0,a.hand.length-1)),'換牌選擇無效。');
  for(const i of [...indices].sort((a,b)=>b-a))a.discard.push(a.hand.splice(i,1)[0]);
  s.metrics.discarded+=indices.length;const n=draw(s,a,indices.length);
  event(s,'cycle',`${a.name}棄 ${indices.length} 張、抽 ${n} 張。`);
  if(indices.length&&a.inner==='xingyun'&&!a.cycleRewardUsed){a.cycleRewardUsed=true;const extra=draw(s,a,1);event(s,'inner',`行雲訣：額外抽 ${extra} 張。`);}
  finishCard(s);
}
function end(s){const a=current(s);assert(a.side==='ally'&&!s.choice,'先完成目前的換牌。');
  if(a.inner==='guiyuan'&&a.qi>0){a.qi--;s.metrics.qiSpent++;a.bonusDraw=1;event(s,'inner','歸元功：消耗 1 剩餘真氣，下次多抽 1 張。');}
  a.discard.push(...a.hand.splice(0));a.qi=0;event(s,'end',`${a.name}結束行動，棄掉全部手牌。`);advance(s);
}
function enemy(s){const a=current(s);assert(a.side==='enemy'&&!s.choice,'現在不是敵方行動。');const p=a.intent;
  let target=s.actors.find(t=>t.id===p.target);if(!target||target.hp<=0){target=living(s,'ally')[0];p.target=target?.id||'';event(s,'retarget',`${a.name}轉向${target?.name||'場上對手'}。`);}
  a.block+=p.block;if(p.block)event(s,'guard',`${a.name}獲得 ${p.block} 防護。`);
  if(p.kind==='charge')event(s,'charge',`${a.name}正在蓄勢。`);
  for(let i=0;i<p.hits&&target?.hp>0&&s.status==='active';i++)hit(s,a,target,p.damage);
  if(s.status==='active'){planEnemy(s,a);advance(s);}
}
export function applyAction(state,command){assert(state.status==='active','交手已結束。');const s=copy(state);s.lastEvents=[];
  switch(command.type){
    case 'play':play(s,command.index,command.target);break;
    case 'cycle':cycle(s,command.indices);break;
    case 'end':end(s);break;
    case 'enemy':enemy(s);break;
    case 'control':{const a=s.actors.find(a=>a.id===command.actor);assert(a?.side==='ally'&&typeof command.auto==='boolean','接管對象無效。');a.auto=command.auto;event(s,'control',`${a.name}${a.auto?'自行出牌':'由你接管'}。`);break;}
    case 'retreat':if(s.inPlay){const a=current(s),c=CARDS[s.inPlay.card];(c.exhaust?a.exhaust:a.discard).push(c.id);s.choice=null;s.inPlay=null;}s.status='retreated';event(s,'retreat','本次試牌已撤出。');break;
    default:throw Error('未知操作。');
  }
  return validateBattle(s);
}
export function previewAction(s,command){const next=applyAction(s,command);return {events:next.lastEvents.map(e=>e.text),changes:next.actors.map(a=>{const old=s.actors.find(x=>x.id===a.id);return {id:a.id,hp:a.hp-old.hp,block:a.block-old.block,qi:a.side==='ally'?a.qi-old.qi:0,hand:a.side==='ally'?a.hand.length-old.hand.length:0};}),choice:!!next.choice,status:next.status};}
export function chooseAI(s){const a=current(s);if(a.side==='enemy')return {type:'enemy'};
  if(s.choice){const index=a.hand.findIndex(id=>CARDS[id].cost>a.qi);return {type:'cycle',indices:index<0?[]:[index]};}
  const enemies=living(s,'enemy'),target=[...enemies].sort((x,y)=>x.hp-y.hp)[0];
  const incoming=enemies.reduce((n,e)=>n+(e.intent.target===a.id?e.intent.damage*e.intent.hits:0),0);
  let best=null,score=-Infinity;
  a.hand.forEach((id,index)=>{const c=cardValues(s,index);if(c.cost>a.qi)return;
    let value=(c.damage||0)+Math.min(target?.block||0,c.strip||0)+(c.energy||0)*(a.qi<3?8:3);
    value+=Math.min(c.block||0,Math.max(0,incoming-a.block))*1.4;
    if(c.draw)value+=a.hand.length<7&&a.qi>=2?5:-10;
    if(c.cycle)value+=a.hand.some(id=>CARDS[id].cost>a.qi-1)?2:0;
    if(c.type==='attack'&&target?.intent.counter&&!target.counterUsed)value-=target.intent.counter;
    if(value>score){score=value;best={type:'play',index,target:target?.id};}
  });
  return best&&score>0?best:{type:'end'};
}
export function aiStep(s){const next=applyAction(s,chooseAI(s));next.metrics.aiActions++;return next;}
export function validateBattle(s){
  assert(s&&s.version===1&&s.rules===RULES&&['active','won','lost','retreated'].includes(s.status),'不是本版試牌存檔。');validateConfig(s.config);
  assert(integer(s.rng,1,4294967295)&&integer(s.round,1,1000000)&&integer(s.turn,1,10000000),'隨機或回合狀態損壞。');
  assert(Array.isArray(s.actors)&&s.actors.length===3+s.config.enemyCount&&new Set(s.actors.map(a=>a.id)).size===s.actors.length,'人物資料損壞。');
  const expectedOrder=[...s.actors].sort((a,b)=>b.speed-a.speed||a.id.localeCompare(b.id)).map(a=>a.id);
  assert(same(expectedOrder,s.order)&&integer(s.index,0,s.order.length-1),'行動順序損壞。');
  for(const a of s.actors){
    assert(integer(a.hp,0,a.maxHp)&&integer(a.block,0,100000)&&integer(a.turns,0,1000000),'氣血或防護損壞。');
    if(Object.hasOwn(ACTORS,a.id)){
      const expected=statsFor(a.id,s.config.actors[a.id]);assert(a.side==='ally'&&a.name===ACTORS[a.id].name&&Object.entries(expected).every(([k,v])=>a[k]===v)&&a.inner===s.config.actors[a.id].inner,'人物屬性或內功已改動。');
      assert(integer(a.qi,0,30)&&integer(a.bonusDraw,0,1)&&typeof a.auto==='boolean'&&typeof a.firstGuardUsed==='boolean'&&typeof a.cycleRewardUsed==='boolean','真氣或內功旗標損壞。');
      let pile=[];for(const key of ['hand','draw','discard','exhaust']){assert(Array.isArray(a[key])&&a[key].length<=25&&a[key].every(id=>Object.hasOwn(CARDS,id)),'牌堆含有無效招式。');pile.push(...a[key]);}
      assert(a.hand.length<=10&&a.exhaust.every(id=>CARDS[id].exhaust),'手牌或除外堆損壞。');
      if(s.inPlay?.actor===a.id)pile.push(s.inPlay.card);
      assert(same(Object.entries(counts(pile)).sort(),Object.entries(counts(s.config.actors[a.id].deck)).sort()),'牌堆不守恆。');
    }else{
      const i=Number(a.id.slice(5)),spec=ENEMIES[s.config.enemy];assert(a.id===`enemy${i}`&&integer(i,0,s.config.enemyCount-1)&&a.side==='enemy'&&a.mode===s.config.enemy&&a.maxHp===spec.hp&&a.speed===spec.speed,'對手身分損壞。');
      assert(integer(a.intentStep,0,a.turns)&&a.turns-a.intentStep<=1,'對手行動旗標損壞。');
      const p=a.intent,pattern=spec.pattern[a.intentStep%spec.pattern.length];assert(p&&['damage','hits','block','counter'].every(k=>p[k]===(pattern[k]||0))&&p.kind===pattern.kind&&Object.hasOwn(ACTORS,p.target)&&typeof a.counterUsed==='boolean','公開意圖損壞。');
    }
  }
  if(s.choice){assert(s.status==='active'&&s.inPlay&&s.inPlay.actor===current(s).id&&s.choice.actor===current(s).id&&s.choice.max===1&&s.inPlay.card==='step','換牌中間狀態損壞。');}
  else assert(s.inPlay===null,'殘留未完成的招式。');
  if(s.status==='active')assert(current(s).hp>0&&living(s,'ally').length&&living(s,'enemy').length,'勝負未正確結算。');
  if(s.status==='won')assert(living(s,'enemy').length===0&&living(s,'ally').length>0,'勝出狀態無效。');
  if(s.status==='lost')assert(living(s,'ally').length===0,'落敗狀態無效。');
  for(const key of ['cardsPlayed','damageTaken','damageDealt','qiSpent','discarded','exhausted','aiActions'])assert(integer(s.metrics?.[key],0,100000000),'交手記錄損壞。');
  assert(Array.isArray(s.log)&&s.log.length<=100&&s.log.every(x=>typeof x==='string'&&x.length<500)&&Array.isArray(s.lastEvents)&&s.lastEvents.length<=100,'演出記錄損壞。');return s;
}
export function restoreBattle(value){return validateBattle(copy(typeof value==='string'?JSON.parse(value):value));}
