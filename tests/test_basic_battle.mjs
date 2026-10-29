import {test} from 'node:test';
import assert from 'node:assert/strict';
import {CARDS,ACTORS,ENEMIES,STARTER,defaultConfig,validateDeck,validateConfig,statsFor} from '../battle/catalog.mjs';
import {createBattle,current,cardValues,applyAction,previewAction,aiStep,restoreBattle,validateBattle} from '../battle/model.mjs';
const copy=x=>JSON.parse(JSON.stringify(x));
function fixture(inner='none',items=[]){const c=defaultConfig();for(const a of Object.values(c.actors)){a.inner='none';a.auto=false;}c.actors.huai.inner=inner;c.actors.huai.items=items;return createBattle(c);}
function hand(s,ids){s=copy(s);const a=current(s),all=[...a.hand,...a.draw,...a.discard,...a.exhaust];for(const id of ids){const i=all.indexOf(id);assert(i>=0,id);all.splice(i,1);}a.hand=[...ids];a.draw=all;a.discard=[];a.exhaust=[];return validateBattle(s);}
function untilOwn(s,id=current(s).id){let n=0;do{s=applyAction(s,{type:current(s).side==='enemy'?'enemy':'end'});assert(++n<20);}while(current(s).id!==id);return s;}
function run(c,limit=1200){let s=createBattle(c),n=0;while(s.status==='active'&&n++<limit)s=aiStep(s);assert(n<limit,'finite legal fight');validateBattle(s);return s;}

test('six basic definitions and starting fifteen; 15/20/25 legal, bounds and family caps reject',()=>{
 assert.equal(Object.keys(CARDS).length,6);assert.equal(STARTER.length,15);
 for(const length of [15,20,25]){const d=Array.from({length},(_,i)=>Object.keys(CARDS)[i%6]);assert.equal(validateDeck(d),'');}
 for(const n of [14,26])assert(validateDeck(Array.from({length:n},(_,i)=>Object.keys(CARDS)[i%6])));
 assert(validateDeck([...STARTER.slice(0,14),'strike']));
 const catalog={...CARDS,a:{id:'a',family:'martial-one',group:'martial',name:'變招甲'},b:{id:'b',family:'martial-one',group:'martial',name:'變招乙'}};
 assert.equal(validateDeck([...STARTER.slice(0,13),'a','b'],catalog),'');
 assert(validateDeck([...STARTER.slice(0,12),'a','a','b'],catalog));
});
test('configuration rejects invalid seeds, duplicate equipment and locked identities',()=>{
 for(const seed of [0,1.5,4294967296]){const c=defaultConfig();c.seed=seed;assert.throws(()=>createBattle(c));}
 const c=defaultConfig();c.actors.hero.items=['wrist','wrist'];assert.throws(()=>validateConfig(c));
 assert.deepEqual(statsFor('du',{inner:'shouzhong',items:['wrist','coat']}),{maxHp:82,power:1,guardPower:1,speed:5});
 assert.deepEqual(createBattle(defaultConfig()).order,['huai','enemy0','hero','du']);
});
test('pay then strike; rejected action and preview leave all state and RNG unchanged',()=>{
 let s=hand(fixture(),['strike','guard','break','observe','step']);s.actors.find(a=>a.id==='enemy0').block=3;
 const before=JSON.stringify(s),p=previewAction(s,{type:'play',index:0,target:'enemy0'});
 assert.equal(JSON.stringify(s),before);assert.equal(p.changes.find(a=>a.id==='enemy0').hp,-3);
 const after=applyAction(s,{type:'play',index:0,target:'enemy0'});assert.equal(current(after).qi,2);assert.equal(after.actors.find(a=>a.id==='enemy0').block,0);
 assert(!JSON.stringify(p).includes('drawPile'));assert.throws(()=>applyAction(s,{type:'play',index:0,target:'hero'}));assert.equal(JSON.stringify(s),before);
 s=copy(s);current(s).qi=0;assert.throws(()=>applyAction(s,{type:'play',index:0,target:'enemy0'}));
});
test('power applies once; strip stays six; block bonus applies once per card',()=>{
 let s=hand(fixture('guiyuan',['wrist','coat']),['break','guard','strike','observe','step']);const e=s.actors.find(a=>a.id==='enemy0');e.block=10;
 assert.equal(cardValues(s,0).damage,6);assert.equal(cardValues(s,0).strip,6);assert.equal(cardValues(s,1).block,6);
 s=applyAction(s,{type:'play',index:0,target:'enemy0'});assert.equal(s.actors.find(a=>a.id==='enemy0').hp,78);
 s=applyAction(s,{type:'play',index:0});assert.equal(current(s).block,6);
});
test('shouzhong first actual block card only, resets on next own action',()=>{
 let s=hand(fixture('shouzhong'),['guard','guard','step','strike','observe']);
 assert.equal(cardValues(s,0).block,7);s=applyAction(s,{type:'play',index:0});assert.equal(cardValues(s,0).block,5);
 s=applyAction(s,{type:'play',index:0});assert.equal(current(s).block,12);
 s=untilOwn(s);assert.equal(current(s).block,0);assert.equal(current(s).firstGuardUsed,false);
});
test('paid step keeps played card outside piles until cycle; JSON restore exactly once',()=>{
 let s=hand(fixture('xingyun'),['step','guard','strike','observe','breath']);
 s=applyAction(s,{type:'play',index:0});assert.equal(current(s).qi,2);assert.equal(current(s).block,3);assert.equal(s.inPlay.card,'step');
 assert.throws(()=>applyAction(s,{type:'end'}));assert.throws(()=>applyAction(s,{type:'play',index:0}));
 const original=copy(s),restored=restoreBattle(JSON.stringify(s));assert.deepEqual(restored,s);
 const resolved=applyAction(restored,{type:'cycle',indices:[0]});assert.equal(current(resolved).hand.length,5);assert(current(resolved).cycleRewardUsed);
 assert.equal(current(resolved).discard.filter(x=>x==='step').length,1);assert.equal(resolved.metrics.cardsPlayed,1);assert.equal(resolved.metrics.discarded,1);
 assert.throws(()=>applyAction(resolved,{type:'cycle',indices:[]}));assert.deepEqual(s,original);
 const skipped=applyAction(s,{type:'cycle',indices:[]});assert.equal(current(skipped).hand.length,4);assert(!current(skipped).cycleRewardUsed);
 assert.throws(()=>applyAction(s,{type:'cycle',indices:[0,1]}));assert.throws(()=>applyAction(s,{type:'cycle',indices:[99]}));
});
test('xingyun extra draw cannot trigger repeatedly in same turn',()=>{
 const c=defaultConfig();for(const a of Object.values(c.actors))a.inner='none';c.actors.huai.inner='xingyun';c.actors.huai.deck=[...STARTER];c.actors.huai.deck[0]='step';
 let s=hand(createBattle(c),['step','step','guard','strike','breath']);
 s=applyAction(s,{type:'play',index:0});s=applyAction(s,{type:'cycle',indices:[]});assert(!current(s).cycleRewardUsed);
 s=applyAction(s,{type:'play',index:0});s=applyAction(s,{type:'cycle',indices:[0]});assert(current(s).cycleRewardUsed);
 assert.equal(s.lastEvents.filter(e=>e.type==='inner').length,1);
});
test('ten-card cap stops draw without consuming excess cards or drawing in-play observe',()=>{
 let s=hand(fixture(),['observe','strike','strike','strike','strike','strike','guard','guard','guard','guard']);
 const before=current(s).draw.length;s=applyAction(s,{type:'play',index:0});assert.equal(current(s).hand.length,10);assert.equal(current(s).draw.length,before-1);
 s=hand(fixture(),['observe']);const a=current(s);a.discard=a.draw.splice(0);a.draw=[];
 s=applyAction(s,{type:'play',index:0});assert(!current(s).hand.includes('observe'));assert(current(s).discard.includes('observe'));
});
test('breath increases qi, exhausts once and never washes back; all unplayed hand discarded',()=>{
 let s=hand(fixture(),['breath','guard','strike','observe','step']);s=applyAction(s,{type:'play',index:0});assert.equal(current(s).qi,4);assert.deepEqual(current(s).exhaust,['breath']);
 const id=current(s).id;s=applyAction(s,{type:'end'});const a=s.actors.find(a=>a.id===id);assert.equal(a.qi,0);assert.equal(a.hand.length,0);assert.equal(a.discard.length,4);
 for(let i=0;i<5;i++){s=untilOwn(s,id);assert(!current(s).hand.includes('breath'));assert.equal(current(s).hand.length,5);s=applyAction(s,{type:'end'});}
});
test('guiyuan consumes spare qi and draws six next own turn, no card retained',()=>{
 let s=hand(fixture('guiyuan'),['guard','strike','break','observe','step']);const id=current(s).id;
 s=applyAction(s,{type:'end'});const a=s.actors.find(a=>a.id===id);assert.equal(a.bonusDraw,1);assert.equal(a.qi,0);assert.equal(a.hand.length,0);assert.equal(s.metrics.qiSpent,1);
 while(current(s).id!==id)s=applyAction(s,{type:current(s).side==='enemy'?'enemy':'end'});
 assert.equal(current(s).hand.length,6);assert.equal(current(s).bonusDraw,0);assert.equal(current(s).qi,3);
});
test('intent stays latched; counter fires once, respects shield and death, and dead actors are skipped',()=>{
 const c=defaultConfig();c.enemy='counter';for(const a of Object.values(c.actors))a.inner='none';let s=hand(createBattle(c),['strike','strike','guard','observe','step']);
 const intent=copy(s.actors.find(a=>a.id==='enemy0').intent);current(s).block=3;
 s=applyAction(s,{type:'play',index:0,target:'enemy0'});assert.equal(current(s).hp,64);assert.equal(s.metrics.damageTaken,2);
 assert.deepEqual(s.actors.find(a=>a.id==='enemy0').intent,intent);
 const hp=current(s).hp;s=applyAction(s,{type:'play',index:0,target:'enemy0'});assert.equal(current(s).hp,hp);
 let kill=hand(createBattle(c),['strike']);kill.actors.find(a=>a.id==='enemy0').hp=1;kill=applyAction(kill,{type:'play',index:0,target:'enemy0'});assert.equal(kill.status,'won');assert.equal(kill.metrics.damageTaken,0);
 let dead=hand(createBattle(c),['strike']);current(dead).hp=1;const fallen=current(dead).id;dead=applyAction(dead,{type:'play',index:0,target:'enemy0'});assert.equal(dead.actors.find(a=>a.id===fallen).hp,0);assert.notEqual(current(dead).id,fallen);
});
test('all snapshots roundtrip; corruption and cross-version saves are rejected',()=>{
 const s=fixture();assert.deepEqual(restoreBattle(JSON.stringify(s)),s);
 for(const mutate of [x=>x.version=2,x=>x.rng=0,x=>current(x).power=99,x=>current(x).hand.push('strike'),x=>x.status='won',x=>x.actors.at(-1).intent.damage=999,x=>x.order.reverse(),x=>x.inPlay={actor:'huai',card:'step'}]){
  const bad=copy(s);mutate(bad);assert.throws(()=>restoreBattle(bad));
 }
 assert.throws(()=>restoreBattle('{broken'));
});
test('AI uses legal action path; 72 starter/loadout/seed/enemy fights terminate and survive JSON checkpoints',()=>{
 const results=[];
 for(const enemy of Object.keys(ENEMIES))for(const seed of [7,42,2026])for(const inner of ['shouzhong','xingyun','guiyuan'])for(const enemyCount of [1,2]){
  const c=defaultConfig();c.enemy=enemy;c.seed=seed;c.enemyCount=enemyCount;c.actors.hero.inner=inner;
  let s=createBattle(c),n=0;while(s.status==='active'&&n++<1200){const before=JSON.stringify(s),next=aiStep(s);assert.equal(JSON.stringify(s),before);s=next;if(n%11===0)s=restoreBattle(JSON.stringify(s));}
  assert(n<1200);assert.equal(s.status,'won',`${enemy}/${seed}/${inner}/${enemyCount}`);results.push({enemy,seed,inner,enemyCount,rounds:s.round,cards:s.metrics.cardsPlayed,damage:s.metrics.damageTaken});
 }
 console.log('LEGAL MATRIX',JSON.stringify(results));
});
test('20/25-card decks, all-auto and control changes preserve order; retreat conserves paid cycle',()=>{
 for(const size of [20,25]){const c=defaultConfig();for(const a of Object.values(c.actors))a.deck=Array.from({length:size},(_,i)=>Object.keys(CARDS)[i%6]);assert.equal(run(c).status,'won');}
 let s=fixture();const order=[...s.order];s=applyAction(s,{type:'control',actor:'hero',auto:true});assert.deepEqual(s.order,order);assert(s.actors.find(a=>a.id==='hero').auto);
 s=hand(s,['step','strike']);s=applyAction(s,{type:'play',index:0});s=applyAction(s,{type:'retreat'});assert.equal(s.status,'retreated');assert.equal(s.inPlay,null);restoreBattle(JSON.stringify(s));
});
