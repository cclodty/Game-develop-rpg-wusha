import {CARDS,INNERS,ENEMIES,TYPES,defaultConfig} from '../battle/catalog.mjs';
import {createBattle,current,living,cardValues,applyAction,chooseAI,restoreBattle} from '../battle/model.mjs';

// Slay-the-Spire style presentation over the basic-v1 rules in battle/. The model is reused as-is.
const W=1440,H=900,KEY='jianghu-combat-spire-v1',SPEED=new URLSearchParams(location.search).has('fast')?.15:1;
const CW=176,CH=246,REST_Y=774,HOVER_Y=734,HAND_TOP=650,PLAY_LINE=540,AIM={x:W/2,y:640},DRAW_AT={x:66,y:842},DISCARD_AT={x:1374,y:842};
const ATLAS='../assets/generated/characters-illustrated.png',GAL='../assets/generated/gal/';
const UNITS={
  du:{src:ATLAS,box:[305,546,510,997],h:282,x:146,y:528},
  huai:{src:ATLAS,box:[40,54,256,514],h:292,x:318,y:542},
  hero:{src:'../assets/generated/battle-back-hero.png',box:[25,39,1024,1479],h:282,x:524,y:556,anchor:.44},
  flurry:{src:ATLAS,box:[287,1019,508,1485],h:300,flip:true},
  armored:{src:ATLAS,box:[544,1021,749,1486],h:304,flip:true},
  charging:{src:ATLAS,box:[793,1021,995,1486],h:300},
  counter:{src:ATLAS,box:[796,51,982,515],h:300},
};
const FACES={
  hero:{src:GAL+'hero-player.png',c:[245,190],r:112},du:{src:GAL+'du.png',c:[290,212],r:112},huai:{src:GAL+'huai.png',c:[218,212],r:112},
  flurry:{src:ATLAS,c:[396,1066],r:46},armored:{src:ATLAS,c:[646,1072],r:46},charging:{src:ATLAS,c:[898,1082],r:46},counter:{src:ATLAS,c:[890,98],r:46},
};
const TONE={hero:'#3e5d93',huai:'#3d7d5d',du:'#5a6f86'};
const ICON={
  atk:'<svg viewBox="0 0 40 40"><path d="M9 31 31 9" stroke="#2a0d08" stroke-width="9" stroke-linecap="round"/><path d="M9 31 31 9" stroke="#f3dccf" stroke-width="5" stroke-linecap="round"/><path d="M6 25l9 9" stroke="#2a0d08" stroke-width="7" stroke-linecap="round"/><path d="M6 25l9 9" stroke="#c8513d" stroke-width="3.5" stroke-linecap="round"/></svg>',
  blk:'<svg viewBox="0 0 40 40"><path d="M20 4 34 9v10c0 9-7 15-14 18C13 34 6 28 6 19V9z" fill="#5f8fbf" stroke="#10263b" stroke-width="2.5"/><path d="M20 9l9 3v7c0 6-4 10-9 12z" fill="#a8cbe9" opacity=".75"/></svg>',
  chg:'<svg viewBox="0 0 40 40"><path d="M20 3c6 8 12 13 12 21a12 12 0 0 1-24 0c0-6 4-9 6-14 1 6 4 8 7 8 0-5-1-9-1-15z" fill="#e7a743" stroke="#4a2a06" stroke-width="2.2"/><path d="M20 20c3 3 5 5 5 8a5 5 0 0 1-10 0c0-3 2-5 5-8z" fill="#fff0b8"/></svg>',
  ctr:'<svg viewBox="0 0 40 40"><g stroke-linecap="round"><path d="M8 32 32 8M32 32 8 8" stroke="#1c1029" stroke-width="9"/><path d="M8 32 32 8M32 32 8 8" stroke="#d9c8f2" stroke-width="4.5"/></g></svg>',
};
const $=s=>document.querySelector(s);
const h=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const wait=ms=>new Promise(r=>setTimeout(r,ms*SPEED));
const art=(actor,id)=>`../assets/cards/basic/${actor}/${id}.webp`;
const needsTarget=id=>!!(CARDS[id].damage||CARDS[id].strip);
const randomSeed=()=>1+Math.floor(Math.random()*4294967294);
const stage=$('#stage'),viewport=$('#viewport');

stage.innerHTML=`<div class="backdrop"></div><div class="field" id="field"></div><div class="fx" id="fx"></div>
<header class="topbar"><div class="brand">江湖未遠<small>尖塔式交手 · 試作</small></div><div class="order" id="order"></div>
<nav><button data-act="deck">牌組</button><button data-act="log">紀錄</button><button data-act="rules">玩法</button><button data-act="retreat">撤退</button></nav></header>
<div class="hud"><div class="orb" id="orb" data-tip="真氣：出牌所需。每次自身行動恢復 3 點，結束時清空。"><div class="ring"></div><div class="core"><b id="qi">0</b><span>/3</span></div><div class="label" id="orb-name"></div></div>
<button class="pile draw" data-act="pile:draw" data-tip="抽牌堆：點擊查看（不顯示順序）"><span class="stack"></span><span class="n" id="draw-n">0</span></button>
<button class="pile discard" data-act="pile:discard" data-tip="棄牌堆：抽牌堆用完時洗回"><span class="stack"></span><span class="n" id="discard-n">0</span></button>
<button class="pile exhaust" data-act="pile:exhaust" data-tip="除外：本場不再使用"><span class="stack"></span><span class="n" id="exhaust-n">0</span></button>
<button class="end-turn" id="end" data-act="end">結束回合</button></div>
<div class="hand" id="hand"></div>
<svg class="arrow" id="arrow" viewBox="0 0 ${W} ${H}"><path class="under"/><path class="line"/><path class="head"/></svg>
<div class="banner" id="banner"></div><div class="keywords" id="keywords"></div><div class="tip" id="tip"></div>
<div class="overlay" id="overlay"></div><div class="toast" id="toast"></div>`;
const field=$('#field'),fx=$('#fx'),handLayer=$('#hand'),overlay=$('#overlay'),arrow=$('#arrow'),tip=$('#tip'),keywords=$('#keywords');

let scale=1,state=null,disp={},view='hero',acting='',hand=[],piles={draw:0,discard:0,exhaust:0},busy=false,modal='',timer=null,limbo=null;
let hover=-1,pick=null,aimed=null,pointer={x:W/2,y:H/2},choiceSel=-1,setup={enemy:'flurry',count:1,auto:false};

function fit(){scale=Math.min(innerWidth/W,innerHeight/H);viewport.style.width=`${W*scale}px`;viewport.style.height=`${H*scale}px`;stage.style.transform=`scale(${scale})`;}
function toStage(e){const r=stage.getBoundingClientRect();return {x:(e.clientX-r.left)/scale,y:(e.clientY-r.top)/scale};}
function toast(text){const t=$('#toast');t.textContent=text;t.classList.add('show');clearTimeout(toast.timer);toast.timer=setTimeout(()=>t.classList.remove('show'),3600);}
const find=id=>state.actors.find(a=>a.id===id);
const unitEl=id=>field.querySelector(`[data-id="${id}"]`);
const look=a=>UNITS[a.side==='ally'?a.id:a.mode];
function spot(a){if(a.side==='ally')return UNITS[a.id];const foes=state.actors.filter(x=>x.side==='enemy'),i=foes.indexOf(a);return foes.length===1?{x:1146,y:550}:[{x:1028,y:536},{x:1268,y:562}][i];}
function center(id){const a=find(id),p=spot(a);return {x:p.x,y:p.y-look(a).h*.55};}
function crop({src,box:[x0,y0,x1,y1]},height){const k=height/(y1-y0);return `width:${Math.round((x1-x0)*k)}px;height:${height}px;background:url('${src}') ${-x0*k}px ${-y0*k}px/${1024*k}px ${1536*k}px no-repeat`;}
function portrait(key,size){const f=FACES[key],k=size/(f.r*2);return `width:${size}px;height:${size}px;background:url('${f.src}') ${-(f.c[0]-f.r)*k}px ${-(f.c[1]-f.r)*k}px/${1024*k}px ${1536*k}px no-repeat`;}
function canAct(){if(!state||state.status!=='active'||busy||modal||state.choice)return false;const a=current(state);return a.side==='ally'&&!a.auto;}

// ---------- battlefield ----------
function buildField(){field.innerHTML='';
  for(const a of state.actors){const p=spot(a),u=look(a),el=document.createElement('div');
    el.className=`unit ${a.side}`;el.dataset.id=a.id;el.style.cssText=`left:${p.x}px;top:${p.y}px;z-index:${p.y};--h:${u.h}px`;
    el.innerHTML=`<div class="ring"></div><div class="mover"><div class="idle" style="animation-delay:${-(p.x%9)/3}s"><div class="sprite${u.flip?' flip':''}" style="${crop(u,u.h)};translate:${-(u.anchor||.5)*100}% 0"></div></div></div>${a.side==='enemy'?'<div class="intent"></div>':'<div class="marker"></div>'}<div class="plate"><div class="name">${h(a.name)}</div><div class="bar"><div class="block"></div><div class="hp"><i></i><span></span></div></div><div class="buffs"></div></div>`;
    field.append(el);}
}
function incoming(id){return living(state,'enemy').filter(e=>e.intent?.kind==='attack'&&e.intent.target===id).reduce((n,e)=>n+e.intent.damage*e.intent.hits,0);}
function intentTip(a){const p=a.intent,t=find(p.target)?.name||'我方';
  return {attack:`攻擊：對${t}造成 ${p.damage} 傷害${p.hits>1?`，共 ${p.hits} 段`:''}。`,guard:`防守：獲得 ${p.block} 防護。`,charge:`蓄勢：獲得 ${p.block} 防護，下次行動重擊。`,counter:`擺架：獲得 ${p.block} 防護；${a.counterUsed?'反制已用過。':`第一次被直接攻擊時反制 ${p.counter} 傷害。`}`}[p.kind];}
function intentHTML(a){const p=a.intent,parts=[];
  if(p.kind==='attack')parts.push(`<span class="ic atk">${ICON.atk}<b>${p.damage}${p.hits>1?`×${p.hits}`:''}</b></span>`);
  if(p.kind==='charge')parts.push(`<span class="ic chg">${ICON.chg}</span>`);
  if(p.kind==='counter')parts.push(`<span class="ic ctr${a.counterUsed?' spent':''}">${ICON.ctr}<b>${p.counter}</b></span>`);
  if(p.block)parts.push(`<span class="ic blk">${ICON.blk}<b>${p.block}</b></span>`);
  return `<div class="icons" data-tip="${h(intentTip(a))}">${parts.join('')}</div>${p.kind==='attack'?`<small>→ ${h(find(p.target)?.name)}</small>`:''}`;}
const chip=(cls,glyph,n,text)=>`<span class="buff ${cls}" data-tip="${h(text)}"><b>${glyph}</b>${n===''?'':`<i>${n}</i>`}</span>`;
function buffs(a){if(a.side!=='ally')return '';const out=[],n=incoming(a.id);
  if(n)out.push(chip('threat','危',n,`敵方意圖：本輪將對${a.name}造成共 ${n} 傷害（未計防護）。`));
  if(a.power)out.push(chip('power','力',a.power,`力道 ${a.power}：每張直接攻擊牌傷害 +${a.power}。`));
  if(a.guardPower)out.push(chip('guard','護',a.guardPower,`護勁 ${a.guardPower}：每張防護牌防護 +${a.guardPower}。`));
  if(a.inner!=='none'){const i=INNERS[a.inner],used=a.inner==='shouzhong'?a.firstGuardUsed:a.inner==='xingyun'&&a.cycleRewardUsed;out.push(chip(`inner${used&&acting===a.id?' used':''}`,i.name[0],'',`${i.name}：${i.description}`));}
  if(a.bonusDraw)out.push(chip('draw','抽','+1','歸元功：下次自身行動多抽 1 張。'));
  return out.join('');}
function paintUnit(a){const el=unitEl(a.id),d=disp[a.id];if(!el)return;
  el.classList.toggle('dead',d.hp<=0);el.classList.toggle('guarded',d.block>0);el.classList.toggle('current',acting===a.id);
  el.querySelector('.hp i').style.width=`${d.hp/a.maxHp*100}%`;el.querySelector('.hp span').textContent=`${d.hp}/${a.maxHp}`;
  el.querySelector('.block').textContent=d.block||'';
  el.querySelector('.plate').dataset.tip=`${a.name}　氣血 ${d.hp}/${a.maxHp}　防護 ${d.block}　速度 ${a.speed}`;
  el.querySelector('.buffs').innerHTML=buffs(a);
  if(a.side==='enemy'){const box=el.querySelector('.intent'),html=d.hp>0?intentHTML(a):'';if(box.innerHTML!==html){box.innerHTML=html;box.classList.remove('fresh');void box.offsetWidth;box.classList.add('fresh');}}
}
function paintOrder(){const s=state,list=[...s.order.slice(s.index),...s.order.slice(0,s.index)].map(find).filter(a=>disp[a.id]?.hp>0);
  $('#order').innerHTML=`<span class="round">第 ${s.round} 輪</span>`+list.map((a,i)=>`<span class="chip ${a.side}${a.id===acting?' now':''}" style="${portrait(a.side==='ally'?a.id:a.mode,a.id===acting?44:36)}" data-tip="${h(a.name)} · 速度 ${a.speed}"></span>`).join('<i>›</i>');}
function paintPiles(){$('#draw-n').textContent=piles.draw;$('#discard-n').textContent=piles.discard;$('#exhaust-n').textContent=piles.exhaust;$('.pile.exhaust').classList.toggle('empty',!piles.exhaust);}
function paintHud(){if(!state)return;const a=find(view),mine=state.status==='active'&&acting===view,orb=$('#orb');
  orb.style.setProperty('--tone',TONE[view]);orb.classList.toggle('idle',!mine);$('#qi').textContent=mine?disp[view].qi:0;$('#orb-name').textContent=`${a.name} · ${INNERS[a.inner].name}`;
  paintPiles();const end=$('#end'),ok=canAct(),cur=state.status==='active'&&current(state);end.disabled=!ok;
  end.textContent=cur?.side==='enemy'?'敵方行動':cur?.auto?'同伴出手':'結束回合';
  end.classList.toggle('glow',ok&&!hand.some(c=>c.el.classList.contains('playable')));paintOrder();}
function sync(){disp=Object.fromEntries(state.actors.map(a=>[a.id,{hp:a.hp,block:a.block,qi:a.qi||0}]));
  const cur=current(state);acting=state.status==='active'?cur.id:'';if(cur.side==='ally')view=cur.id;
  const a=find(view);piles={draw:a.draw.length,discard:a.discard.length,exhaust:a.exhaust.length};
  stage.classList.remove('empty');state.actors.forEach(paintUnit);refreshFaces();layoutHand();paintHud();}

// ---------- cards ----------
function baseValues(owner,id){const a=find(owner),c=CARDS[id];return {...c,damage:c.damage?c.damage+a.power:0,block:c.block?c.block+a.guardPower:0};}
function effectText(id,v){const c=CARDS[id],n=(val,base)=>`<b class="${val>base?'up':val<base?'down':''}">${val}</b>`;
  return [c.strip&&`移除目標至多 <b>${c.strip}</b> 防護`,c.damage&&`造成 ${n(v.damage,c.damage)} 傷害`,c.block&&`獲得 ${n(v.block,c.block)} 防護`,c.draw&&`抽 <b>${c.draw}</b> 張牌`,c.cycle&&'可棄 1 張手牌，再抽 1 張',c.energy&&`獲得 <b>${c.energy}</b> 真氣`,c.exhaust&&'<em>除外</em>'].filter(Boolean).map(x=>x+'。').join('<br>');}
function cardInner(owner,id,v=baseValues(owner,id)){const c=CARDS[id];
  return `<div class="face"><div class="title">${c.name}</div><div class="art"><img src="${art(owner,id)}" alt="" draggable="false"></div><div class="type">${TYPES[c.type]}</div><div class="text"><span>${effectText(id,v)}</span></div></div><div class="cost">${v.cost}</div>`;}
const miniCard=(owner,id)=>`<span class="mini"><span class="card ${CARDS[id].type}">${cardInner(owner,id)}</span></span>`;
function makeCard(id){const el=document.createElement('div');el.className=`card ${CARDS[id].type}`;el.innerHTML=cardInner(view,id);handLayer.append(el);return {id,el};}
function refreshFaces(){const cur=state.status==='active'&&current(state),live=cur&&cur.id===view&&cur.side==='ally',act=canAct();
  hand.forEach((c,i)=>{const v=live&&cur.hand[i]===c.id?cardValues(state,i):baseValues(view,c.id);c.el.querySelector('.text span').innerHTML=effectText(c.id,v);c.el.querySelector('.cost').textContent=v.cost;
    c.el.classList.toggle('playable',act&&v.cost<=cur.qi);c.el.classList.toggle('broke',!!live&&v.cost>cur.qi);});}
function slots(n){const gap=n>1?Math.min(CW*.84,860/(n-1)):0,step=Math.min(4,26/n);
  return Array.from({length:n},(_,i)=>{const o=i-(n-1)/2;return {x:W/2+o*gap,y:REST_Y+o*o*2.4,r:o*step};});}
function place(el,x,y,r=0,k=1,z){el.style.transform=`translate(${x-CW/2}px,${y-CH/2}px) rotate(${r}deg) scale(${k})`;if(z!=null)el.style.zIndex=z;}
function layoutHand(){const s=slots(hand.length);
  hand.forEach((c,i)=>{if(pick?.card===c)return;let {x,y,r}=s[i],k=1,z=10+i;
    if(hover>=0){const d=i-hover;if(!d){y=HOVER_Y;r=0;k=1.32;z=60;}else x+=Math.sign(d)*[0,66,30,12][Math.min(3,Math.abs(d))];}
    place(c.el,x,y,r,k,z);});}
function nearest(p){if(p.y<HAND_TOP||!hand.length)return -1;let best=-1,dist=Infinity;slots(hand.length).forEach((q,i)=>{const d=Math.abs(p.x-q.x);if(d<dist){dist=d;best=i;}});return dist<CW*.55?best:-1;}
function handAt(p){if(pick||busy||modal||!hand.length)return -1;
  if(hover>=0&&hover<hand.length){const x=slots(hand.length)[hover].x;if(Math.abs(p.x-x)<CW*.66&&p.y>HOVER_Y-CH*.66)return hover;}
  return nearest(p);}
function enemyAt(p){return living(state,'enemy').find(a=>{const s=spot(a),u=look(a);return Math.abs(p.x-s.x)<95&&p.y>s.y-u.h-50&&p.y<s.y+60;});}
function showKeywords(){if(hover<0||pick||busy){keywords.classList.remove('show');return;}
  const c=CARDS[hand[hover].id],a=find(view),list=[];
  if(c.block)list.push(['防護','抵擋傷害；於自身下次行動開始時清除。']);
  if(c.strip)list.push(['破架','先移除目標防護，再造成傷害。力道不增加移除量。']);
  if(c.draw)list.push(['抽牌','手牌上限 10 張；抽牌堆空了才洗入棄牌。']);
  if(c.cycle)list.push(['棄換','施展後可選一張手牌棄掉，再抽 1 張；可略過。']);
  if(c.energy)list.push(['真氣','出牌所需；每次自身行動恢復 3 點，結束時清空。']);
  if(c.exhaust)list.push(['除外','施展後移出，本場交手不再回到牌堆。']);
  if(c.damage&&a.power)list.push(['力道',`每張直接攻擊牌 +${a.power} 傷害。`]);
  if(c.block&&a.inner==='shouzhong')list.push(['守中訣',a.firstGuardUsed?'本次行動已觸發。':'本次行動首張防護牌，再加 2 防護。']);
  if(c.cycle&&a.inner==='xingyun')list.push(['行雲訣',a.cycleRewardUsed?'本次行動已觸發。':'本次行動首次實際棄牌，額外抽 1 張。']);
  const foe=c.type==='attack'&&living(state,'enemy').find(e=>e.intent?.counter&&!e.counterUsed);if(foe)list.push(['反制',`${foe.name}擺架中：第一次直接攻擊會受到 ${foe.intent.counter} 傷害。`]);
  if(!list.length){keywords.classList.remove('show');return;}
  const x=slots(hand.length)[hover].x,right=x+CW*.66+12;keywords.style.left=`${right+250>W?x-CW*.66-262:right}px`;keywords.style.top=`${HOVER_Y-CH*.66}px`;
  keywords.innerHTML=list.map(([k,v])=>`<div><b>${k}</b>${v}</div>`).join('');keywords.classList.add('show');}

// ---------- picking, dragging, aiming ----------
function setAim(id){aimed=id;for(const el of field.querySelectorAll('.unit.enemy'))el.classList.toggle('aimed',el.dataset.id===id);}
function drawArrow(sx,sy,ex,ey,hot){const cx=sx+(ex-sx)*.15,cy=ey+(sy-ey)*.25,a=Math.atan2(ey-cy,ex-cx),d=`M${sx} ${sy}Q${cx} ${cy} ${ex} ${ey}`,p=(r,t)=>`${ex+Math.cos(a+t)*r} ${ey+Math.sin(a+t)*r}`;
  arrow.querySelector('.under').setAttribute('d',d);arrow.querySelector('.line').setAttribute('d',d);arrow.querySelector('.head').setAttribute('d',`M${p(14,0)}L${p(22,2.5)}L${p(6,Math.PI)}L${p(22,-2.5)}Z`);
  arrow.classList.add('show');arrow.classList.toggle('hot',hot);}
function startPick(i,mode){const c=hand[i];hover=-1;keywords.classList.remove('show');tip.classList.remove('show');
  pick={index:i,card:c,mode,start:{...pointer},moved:false,target:needsTarget(c.id),keyboard:false};c.el.classList.add('held');layoutHand();track();}
function track(){const p=pointer,c=pick.card;
  if(pick.mode==='drag'&&!pick.moved&&Math.hypot(p.x-pick.start.x,p.y-pick.start.y)>10)pick.moved=true;
  const up=p.y<PLAY_LINE,aiming=pick.target&&(pick.mode==='select'||pick.moved&&up),follow=pick.mode==='drag'&&pick.moved&&!aiming;
  c.el.classList.toggle('dragging',follow);
  if(follow)place(c.el,p.x,p.y,0,1.06,90);else if(pick.mode==='select'||aiming)place(c.el,AIM.x,AIM.y,0,1.06,90);else place(c.el,slots(hand.length)[pick.index].x,HOVER_Y,0,1.32,90);
  c.el.classList.toggle('ready',!pick.target&&(pick.keyboard||up&&(follow||pick.mode==='select')));
  if(aiming){const t=pick.keyboard?find(aimed):enemyAt(p);setAim(t?.id||null);const e=pick.keyboard&&t?center(t.id):p;drawArrow(AIM.x,AIM.y-CH*.55,e.x,e.y,!!t);}
  else{arrow.classList.remove('show');setAim(null);}}
function dropPick(){if(!pick)return;pick.card.el.classList.remove('held','dragging','ready');pick=null;arrow.classList.remove('show');setAim(null);}
function cancelPick(){if(!pick)return;dropPick();layoutHand();}
function release(){const {index,target,keyboard}=pick,p=pointer;
  if(target){const t=keyboard?find(aimed):enemyAt(p);return t?.hp>0?play(index,t.id):cancelPick();}
  return keyboard||p.y<PLAY_LINE?play(index):cancelPick();}
function play(index,target){dropPick();dispatch({type:'play',index,target});}
function keyboardPick(i){cancelPick();startPick(i,'select');pick.keyboard=true;if(pick.target)setAim(aimed&&find(aimed)?.hp>0?aimed:living(state,'enemy')[0].id);track();}

stage.addEventListener('pointermove',e=>{pointer=toStage(e);if(pick){pick.keyboard=false;track();return;}
  const i=handAt(pointer);if(i!==hover){hover=i;layoutHand();showKeywords();}stage.classList.toggle('pointing',hover>=0);
  const foe=state&&!busy&&!modal&&enemyAt(pointer);for(const el of field.querySelectorAll('.unit.ally'))el.classList.toggle('threatened',!!foe&&foe.intent?.kind==='attack'&&foe.intent.target===el.dataset.id);});
stage.addEventListener('pointerdown',e=>{if(e.target.closest('button,a,input,label,.overlay,.topbar'))return;pointer=toStage(e);
  if(e.button===2){cancelPick();return;}
  if(pick?.mode==='select'){const i=nearest(pointer);if(i===pick.index)return cancelPick();if(i>=0){cancelPick();if(canAct())startPick(i,'drag');return;}
    if(pick.target&&!enemyAt(pointer)||!pick.target&&pointer.y>=PLAY_LINE)return cancelPick();return release();}
  if(!canAct())return;const i=handAt(pointer);if(i>=0)startPick(i,'drag');});
addEventListener('pointerup',e=>{if(pick?.mode!=='drag')return;pointer=toStage(e);if(!pick.moved){pick.mode='select';track();return;}release();});
addEventListener('pointercancel',cancelPick);
stage.addEventListener('contextmenu',e=>{e.preventDefault();cancelPick();});
addEventListener('keydown',e=>{
  if(modal){if(e.key==='Escape'&&!['setup','result','choice'].includes(modal))closeModal();
    if(modal==='choice'&&e.key==='Enter')overlay.querySelector(choiceSel<0?'[data-act="cycle-skip"]':'[data-act="cycle"]').click();
    if(modal==='choice'&&/^[0-9]$/.test(e.key)){const i=(Number(e.key)+9)%10;if(i<current(state).hand.length){choiceSel=choiceSel===i?-1:i;renderChoice();}}return;}
  if(/^[0-9]$/.test(e.key)&&canAct()){const i=(Number(e.key)+9)%10;if(i<hand.length)keyboardPick(i);}
  else if((e.key==='Enter'||e.key===' ')&&pick){e.preventDefault();pick.keyboard=true;release();}
  else if(['Tab','ArrowLeft','ArrowRight'].includes(e.key)&&pick?.target){e.preventDefault();const foes=living(state,'enemy'),i=foes.findIndex(a=>a.id===aimed);setAim(foes[(i+(e.key==='ArrowLeft'?foes.length-1:1))%foes.length].id);pick.keyboard=true;track();}
  else if(e.key==='Escape')cancelPick();
  else if((e.key==='e'||e.key==='E')&&canAct()){cancelPick();dispatch({type:'end'});}});

// ---------- effects ----------
function pop(id,text,cls){const c=center(id),e=document.createElement('div');e.className=`pop ${cls}`;e.textContent=text;
  e.style.left=`${c.x+Math.random()*44-22}px`;e.style.top=`${c.y+Math.random()*24-12-(cls==='block'?40:0)}px`;fx.append(e);setTimeout(()=>e.remove(),1100);}
function bubble(id,text){const a=find(id),p=spot(a),b=document.createElement('div');b.className='bubble';b.textContent=text;b.style.left=`${p.x}px`;b.style.top=`${p.y-look(a).h-26}px`;fx.append(b);setTimeout(()=>b.remove(),1700);}
function slash(id,side){const c=center(id),e=document.createElement('div');e.className=`slash ${side}`;e.style.left=`${c.x}px`;e.style.top=`${c.y}px`;fx.append(e);setTimeout(()=>e.remove(),420);}
function ward(id){const c=center(id),e=document.createElement('div');e.className='ward';e.innerHTML=ICON.blk;e.style.left=`${c.x}px`;e.style.top=`${c.y}px`;fx.append(e);setTimeout(()=>e.remove(),700);}
const move=(id,frames,ms)=>unitEl(id)?.querySelector('.mover').animate(frames,{duration:ms*SPEED,easing:'ease-out'});
async function hit(ev){const from=find(ev.from),to=find(ev.target),dir=Math.sign(spot(to).x-spot(from).x);
  move(from.id,[{transform:'none'},{transform:`translateX(${dir*48}px)`,offset:.35},{transform:'none'}],340);await wait(110);
  const d=disp[to.id];d.block-=ev.blocked;d.hp-=ev.damage;slash(to.id,from.side);
  if(ev.damage)pop(to.id,String(ev.damage),'dmg');if(ev.blocked)pop(to.id,`擋 ${ev.blocked}`,'block');
  move(to.id,[{transform:'none'},{transform:'translateX(-10px)'},{transform:'translateX(8px)'},{transform:'translateX(-4px)'},{transform:'none'}],260);
  if(ev.damage>=10)field.animate([{transform:'none'},{transform:'translate(5px,-3px)'},{transform:'translate(-4px,3px)'},{transform:'none'}],{duration:220*SPEED});
  paintUnit(to);await wait(250);}
async function effects(next,ctx){
  for(const ev of next.lastEvents)switch(ev.type){
    case 'strip':{const d=disp[ctx.target],n=Math.min(d.block,ctx.values.strip);d.block-=n;paintUnit(find(ctx.target));pop(ctx.target,n?`破架 −${n}`:'破架','info');await wait(240);break;}
    case 'hit':await hit(ev);break;
    case 'guard':disp[ctx.actor].block+=ctx.values.block;paintUnit(find(ctx.actor));ward(ctx.actor);pop(ctx.actor,`+${ctx.values.block}`,'block');await wait(280);break;
    case 'qi':disp[ctx.actor].qi+=ctx.values.energy;pop(ctx.actor,`真氣 +${ctx.values.energy}`,'qi');paintHud();await wait(220);break;
    case 'counter':pop(ctx.target,'反制！','info');await wait(260);break;
    case 'charge':pop(ctx.actor,'蓄勢','info');await wait(320);break;
    case 'retarget':pop(ctx.actor,'轉向','info');await wait(200);break;
    case 'inner':pop(ctx.actor,ev.text.split('：')[0],'qi');await wait(320);break;
    case 'defeat':disp[ev.target].hp=0;paintUnit(find(ev.target));await wait(420);break;
  }}
function fly(el,x,y,r,k,ms=320){el.style.transition=`transform ${ms*SPEED}ms cubic-bezier(.45,.05,.55,.95),opacity ${ms*SPEED}ms`;place(el,x,y,r,k);}
function toDiscard(c){fly(c.el,DISCARD_AT.x,DISCARD_AT.y,40,.16);setTimeout(()=>{c.el.remove();piles.discard++;paintPiles();},320*SPEED);}
async function retire(c){if(CARDS[c.id].exhaust){c.el.classList.add('burn');piles.exhaust++;paintPiles();await wait(460);c.el.remove();}else{toDiscard(c);await wait(330);}}
async function discardHand(){const list=hand;hand=[];list.forEach((c,i)=>setTimeout(()=>toDiscard(c),i*45*SPEED));await wait(list.length*45+340);}
async function shuffle(){const n=Math.min(piles.discard,8);
  for(let i=0;i<n;i++){const b=document.createElement('div');b.className='card-back';handLayer.append(b);
    b.animate([{transform:`translate(${DISCARD_AT.x-CW/2}px,${DISCARD_AT.y-CH/2}px) scale(.18)`},{transform:`translate(${W/2-CW/2}px,${560-CH/2}px) rotate(${180+i*20}deg) scale(.3)`},{transform:`translate(${DRAW_AT.x-CW/2}px,${DRAW_AT.y-CH/2}px) rotate(360deg) scale(.18)`}],{duration:520*SPEED,delay:i*40*SPEED,easing:'ease-in-out',fill:'both'}).finished.then(()=>b.remove());}
  piles.draw+=piles.discard;piles.discard=0;await wait(520+n*40);paintPiles();}
async function drawCards(ids){
  for(const id of ids){if(piles.draw<=0&&piles.discard>0)await shuffle();piles.draw=Math.max(0,piles.draw-1);paintPiles();
    const c=makeCard(id);c.el.style.transition='none';place(c.el,DRAW_AT.x,DRAW_AT.y,-30,.16,5);c.el.getBoundingClientRect();
    c.el.style.transition=`transform ${340*SPEED}ms cubic-bezier(.2,.7,.3,1)`;hand.push(c);layoutHand();await wait(100);}
  await wait(260);for(const c of hand)c.el.style.transition='';}
async function cast(c){c.el.classList.remove('held','dragging','ready');fly(c.el,W/2,420,0,.9,200);c.el.style.zIndex=95;await wait(220);}
function rebuild(){for(const c of hand)c.el.remove();hand=[];limbo?.el.remove();limbo=null;if(state.status!=='active')return;const a=current(state);if(a.side!=='ally')return;
  for(const id of a.hand){const c=makeCard(id);c.el.style.transition='none';hand.push(c);}layoutHand();requestAnimationFrame(()=>hand.forEach(c=>c.el.style.transition=''));}
async function banner(a){const b=$('#banner'),ally=a.side==='ally';
  b.className=`banner show ${ally?'ally':'foe'}`;b.innerHTML=`<b>${h(a.name)} · ${ally?'出手':'行動'}</b><small>第 ${state.round} 輪 · ${ally?`${INNERS[a.inner].name} · 真氣 ${a.qi} · 抽 ${a.hand.length} 張`:h(intentTip(a))}</small>`;
  await wait(ally?640:600);b.classList.remove('show');await wait(140);}
async function turnover(prev,next){if(next.turn===prev.turn)return;
  if(hand.length)await discardHand();if(next.status!=='active')return;
  const a=current(next);acting=a.id;disp[a.id].block=a.block;disp[a.id].qi=a.qi||0;
  if(a.side==='ally'){view=a.id;const pa=prev.actors.find(x=>x.id===a.id);piles={draw:pa.draw.length,discard:pa.discard.length,exhaust:pa.exhaust.length};}
  next.actors.forEach(paintUnit);paintHud();await banner(a);if(a.side==='ally')await drawCards(a.hand);}

// ---------- turn driver ----------
async function dispatch(command,ai=false){if(busy||!state||state.status!=='active')return;
  const prev=state,actor=current(prev);let next;
  try{next=applyAction(prev,command);}catch(e){bubble(actor.id,e.message);layoutHand();return;}
  if(ai)next.metrics.aiActions++;
  save(next);busy=true;clearTimeout(timer);hover=-1;keywords.classList.remove('show');refreshFaces();paintHud();
  const ctx={actor:actor.id};
  try{
    if(command.type==='play'){ctx.values=cardValues(prev,command.index);ctx.target=command.target;ctx.card=hand.splice(command.index,1)[0];disp[actor.id].qi-=ctx.values.cost;paintHud();layoutHand();await cast(ctx.card);}
    if(command.type==='enemy')ctx.values={block:actor.intent.block};
    if(command.type==='cycle'){const gone=command.indices.map(i=>hand[i]);hand=hand.filter(c=>!gone.includes(c));gone.forEach(toDiscard);layoutHand();if(gone.length)await wait(340);}
    if(command.type==='end')await discardHand();
    await effects(next,ctx);
    state=next;
    if(next.turn===prev.turn&&current(next).side==='ally'){const a=current(next),ids=hand.map(c=>c.id);
      if(ids.every((id,i)=>a.hand[i]===id))await drawCards(a.hand.slice(ids.length));}
    if(ctx.card){if(next.choice)limbo=ctx.card;else await retire(ctx.card);}
    if(command.type==='cycle'&&limbo){await retire(limbo);limbo=null;}
    await turnover(prev,next);
  }catch(e){console.error(e);}
  state=next;busy=false;save();
  const a=current(state);if(state.status!=='active'||a.side!=='ally'||hand.map(c=>c.id).join()!==a.hand.join())rebuild();
  sync();
  if(state.status!=='active'){await wait(600);showResult();return;}
  if(state.choice&&!a.auto)showChoice();else schedule();}
function schedule(){clearTimeout(timer);if(!state||state.status!=='active'||busy||modal)return;const a=current(state);
  if(a.side==='enemy')timer=setTimeout(()=>dispatch({type:'enemy'}),420*SPEED);
  else if(a.auto)timer=setTimeout(()=>dispatch(chooseAI(state),true),650*SPEED);}
function save(battle=state){try{localStorage.setItem(KEY,JSON.stringify({version:1,setup,battle}));}catch{toast('瀏覽器無法保存這場交手。');}}
function load(){let data=null;try{data=JSON.parse(localStorage.getItem(KEY)||'null');}catch{}
  if(data?.setup&&Object.hasOwn(ENEMIES,data.setup.enemy))setup={enemy:data.setup.enemy,count:data.setup.count===2?2:1,auto:!!data.setup.auto};
  if(!data?.battle)return null;try{const s=restoreBattle(data.battle);return s.status==='active'?s:null;}catch(e){toast(`上次的交手無法讀取（${e.message}），請重新開始。`);return null;}}
async function start(seed=randomSeed()){const cfg=defaultConfig();cfg.seed=seed;cfg.enemy=setup.enemy;cfg.enemyCount=setup.count;
  for(const [id,a] of Object.entries(cfg.actors))a.auto=setup.auto&&id!=='hero';
  closeModal(true);cancelPick();handLayer.innerHTML='';hand=[];limbo=null;fx.innerHTML='';
  state=createBattle(cfg);save();buildField();busy=true;sync();
  const a=current(state);if(a.side==='ally'){piles.draw=a.draw.length+a.hand.length;paintPiles();await banner(a);await drawCards(a.hand);}
  busy=false;sync();schedule();}

// ---------- overlays ----------
function open(name,html){modal=name;clearTimeout(timer);overlay.innerHTML=html;overlay.className=`overlay open is-${name}`;handLayer.classList.toggle('veiled',name==='choice');cancelPick();hover=-1;layoutHand();keywords.classList.remove('show');tip.classList.remove('show');paintHud();}
function closeModal(quiet=false){modal='';overlay.className='overlay';overlay.innerHTML='';handLayer.classList.remove('veiled');if(state){refreshFaces();paintHud();}if(!quiet)schedule();}
function showSetup(){const c=setup;
  open('setup',`<section class="sheet setup"><h2>江湖未遠 · 尖塔式交手 <small>試作</small></h2><p class="lead">沿用基本牌 v1 規則：陳天佑、宋懷晴、杜蘅各用自己的牌組，依速度輪流出手；每次自身行動恢復 3 真氣、抽 5 張，結束時全棄。把手牌拖上戰場出招，攻擊牌拖到對手身上。</p>
  <h3>挑一位陪練</h3><div class="foes">${Object.entries(ENEMIES).map(([id,e])=>`<button class="foe${c.enemy===id?' on':''}" data-act="foe:${id}"><span class="mug" style="${portrait(id,76)}"></span><b>${e.name}</b><small>氣血 ${e.hp} · 速度 ${e.speed}</small><span>${e.description}</span></button>`).join('')}</div>
  <div class="opts"><span class="seg">人數 ${[1,2].map(n=>`<button class="${c.count===n?'on':''}" data-act="count:${n}">${n===1?'一人':'兩人'}</button>`).join('')}</span><label><input type="checkbox" data-act="auto"${c.auto?' checked':''}> 宋懷晴、杜蘅自動出牌（只操作陳天佑）</label></div>
  <footer><a href="../battle/">原版試牌場</a><a href="../web/">回到劇情</a><span class="grow"></span><button class="primary" data-act="start">開始交手</button></footer></section>`);}
function showChoice(){choiceSel=-1;renderChoice();}
function renderChoice(){const a=current(state);
  open('choice',`<section class="choice"><h2>掠步 · 換牌</h2><p>選一張手牌棄掉，再抽 1 張；也可以不換。</p><div class="choice-row">${a.hand.map((id,i)=>`<button class="pickable${i===choiceSel?' on':''}" data-act="pickc:${i}">${miniCard(a.id,id)}</button>`).join('')}</div>
  <footer><button data-act="cycle-skip">不換牌</button><button class="primary" data-act="cycle"${choiceSel<0?' disabled':''}>棄掉並抽 1 張</button></footer></section>`);}
function showPile(kind){const a=find(view),ids=kind==='draw'?[...a.draw].sort():a[kind];
  open('pile',`<section class="sheet"><h2>${h(a.name)} · ${{draw:'抽牌堆',discard:'棄牌堆',exhaust:'除外'}[kind]}（${ids.length}）</h2>${kind==='draw'?'<p class="lead">抽牌順序不公開，以下依招式排列。</p>':''}<div class="mini-grid">${ids.map(id=>miniCard(a.id,id)).join('')||'<p>空</p>'}</div><footer><button class="primary" data-act="close">返回</button></footer></section>`);}
function showDeck(){open('pile',`<section class="sheet"><h2>三人牌組</h2>${state.actors.filter(a=>a.side==='ally').map(a=>`<h3>${h(a.name)} · ${INNERS[a.inner].name} · ${state.config.actors[a.id].deck.length} 張</h3><div class="mini-grid">${[...state.config.actors[a.id].deck].sort().map(id=>miniCard(a.id,id)).join('')}</div>`).join('')}<footer><button class="primary" data-act="close">返回</button></footer></section>`);}
function showLog(){open('pile',`<section class="sheet log"><h2>交手紀錄</h2>${[...state.log].reverse().map(t=>`<p>${h(t)}</p>`).join('')}<footer><button class="primary" data-act="close">返回</button></footer></section>`);}
function showRules(){open('pile',`<section class="sheet"><h2>玩法</h2><div class="cols"><div><h3>出牌</h3><p>滑過手牌放大查看。按住拖上戰場放手即施展；攻擊牌拖出後會出現箭頭，指向對手放手。</p><p>也可以點一下手牌，再點對手（或點戰場）施展。右鍵、Esc 或再點一次該牌取消。</p><p>鍵盤：1–0 選牌，Tab／方向鍵換目標，Enter 施展，E 結束回合。</p></div><div><h3>回合</h3><p>依速度輪流出手（上方次序列）。輪到我方人物時恢復 3 真氣、抽 5 張；結束時手牌全棄、真氣清空。</p><p>防護擋傷害，於自身下次行動開始時清除。對手頭上是公開意圖與目標；被瞄準的同伴腳下會亮紅圈。</p><p>抽牌堆用完時洗入棄牌堆；調息施展後除外。</p></div></div><footer><button class="primary" data-act="close">返回</button></footer></section>`);}
function showResult(){const s=state,m=s.metrics,title={won:'切磋勝出',lost:'此戰落敗',retreated:'收招退場'}[s.status];
  open('result',`<section class="sheet result ${s.status}"><h2>${title}</h2><p class="lead">${ENEMIES[s.config.enemy].name} × ${s.config.enemyCount} · 種子 ${s.config.seed}</p><div class="stats">${[['交手輪數',s.round],['出牌',m.cardsPlayed],['造成傷害',m.damageDealt],['承受傷害',m.damageTaken],['棄換',m.discarded],['除外',m.exhausted]].map(([l,v])=>`<div><b>${v}</b>${l}</div>`).join('')}</div>
  <footer><button data-act="setup">換個對手</button><button data-act="same">同種子重來</button><button class="primary" data-act="again">再戰一場</button></footer></section>`);}

stage.addEventListener('click',e=>{const b=e.target.closest('[data-act]');if(!b||b.disabled)return;const [act,arg]=b.dataset.act.split(':');
  if(act==='end'){if(canAct()){cancelPick();dispatch({type:'end'});}}
  else if(act==='pile'){if(state)showPile(arg);}
  else if(act==='deck'){if(state)showDeck();}
  else if(act==='log'){if(state)showLog();}
  else if(act==='rules')showRules();
  else if(act==='retreat'){if(state?.status==='active'&&!busy)open('pile',`<section class="sheet narrow"><h2>撤出這場交手？</h2><p class="lead">記錄本場統計後結束，可以再戰或換對手。</p><footer><button data-act="close">返回</button><button class="primary" data-act="retreat-yes">確認撤退</button></footer></section>`);}
  else if(act==='retreat-yes'){closeModal(true);clearTimeout(timer);state=applyAction(state,{type:'retreat'});save();rebuild();sync();showResult();}
  else if(act==='close')closeModal();
  else if(act==='foe'){setup.enemy=arg;showSetup();}
  else if(act==='count'){setup.count=Number(arg);showSetup();}
  else if(act==='auto')setup.auto=b.checked;
  else if(act==='start'||act==='again')start();
  else if(act==='same'){setup={enemy:state.config.enemy,count:state.config.enemyCount,auto:state.config.actors.huai.auto};start(state.config.seed);}
  else if(act==='setup')showSetup();
  else if(act==='pickc'){const i=Number(arg);choiceSel=choiceSel===i?-1:i;renderChoice();}
  else if(act==='cycle'||act==='cycle-skip'){const indices=act==='cycle'&&choiceSel>=0?[choiceSel]:[];closeModal(true);dispatch({type:'cycle',indices});}});
stage.addEventListener('pointerover',e=>{const t=e.target.closest('[data-tip]');if(!t||pick){tip.classList.remove('show');return;}
  const r=t.getBoundingClientRect(),s=stage.getBoundingClientRect(),x=(r.left+r.width/2-s.left)/scale,below=(r.bottom-s.top)/scale+10,above=(r.top-s.top)/scale-10;
  tip.textContent=t.dataset.tip;tip.style.left=`${Math.min(W-180,Math.max(180,x))}px`;const up=below>H-120;tip.style.top=`${up?above:below}px`;tip.classList.toggle('up',up);tip.classList.add('show');});
stage.addEventListener('pointerout',e=>{if(e.target.closest('[data-tip]'))tip.classList.remove('show');});

fit();addEventListener('resize',fit);
state=load();
if(state){buildField();rebuild();sync();if(state.choice&&!current(state).auto)showChoice();else schedule();}
else showSetup();
