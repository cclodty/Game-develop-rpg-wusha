const {test}=require('node:test');
const assert=require('node:assert/strict');
const F=require('../chapter/model.js');
const C=require('../chapter/catalog.js');

function settled(){const g=F.Game.fresh('試行者');g.begin('E01','settle');g.begin('E02','join');return g;}
function search(g){for(let i=0;i<3;i++)g.search(i);g.finishSearch();}
function autoBattle(g){let n=0;while(g.s.battle.status==='active'&&n++<2000)F.aiStep(g.s.battle);assert(n<2000);return g.s.battle.status;}
function trained(){const g=settled();g.begin('E03','practice');g.retreat();return g;}

test('three possible departures preserve actual evidence and exposure',()=>{
 const clear=settled();clear.begin('E05','talk');clear.begin('E07','ledger');clear.begin('E10','law');search(clear);clear.begin('E13','finish');assert.equal(clear.s.result,'clear');
 const doubt=settled();doubt.begin('E07','ledger');doubt.begin('E13','finish');assert.equal(doubt.s.result,'doubt');assert(!doubt.s.clues.includes('record'));
 const exposed=settled();exposed.begin('E05','carry');exposed.begin('E07','ledger');exposed.begin('E10','fight');exposed.retreat();exposed.begin('E12','recover');exposed.begin('E13','finish');assert.equal(exposed.s.result,'exposed');assert(!exposed.s.clues.includes('record'));assert.equal(exposed.s.events.E10,'lost');
});
test('deadline is evaluated on completion; exact boundary succeeds',()=>{
 const g=settled();g.s.spent=7;assert.equal(g.reason('E06','path'),'');g.begin('E06','path');search(g);assert.equal(g.s.spent,9);assert.equal(g.s.events.E06,'done');assert(g.s.clues.includes('seal'));
 const late=settled();late.s.spent=8;assert(late.reason('E06','path'));assert.throws(()=>late.begin('E06','path'));assert.equal(late.s.spent,8);
});
test('calendar expires optional opportunities without awarding their evidence',()=>{
 const g=settled();for(let i=0;i<10;i++)g.rest();assert.equal(g.s.events.E06,'expired');assert.equal(g.s.events.E08,'expired');g.begin('E12','recover');assert.deepEqual(g.s.clues,['copy']);g.begin('E13','finish');assert.equal(g.s.result,'doubt');
});
test('zero funds, no footwork and no companions still have a social path',()=>{
 const g=settled();g.s.money=0;g.team('huai',false);g.team('du',false);assert(g.reason('E07','ledger'));g.begin('E05','talk');g.begin('E07','ledger');assert(g.reason('E10','stealth'));g.begin('E10','law');search(g);g.begin('E13','finish');assert.equal(g.s.result,'clear');assert.deepEqual(g.s.team,['hero']);
});
test('cost and reward settle once, including a round trip during search',()=>{
 const g=settled();g.begin('E05','talk');const before=g.s.spent;g.begin('E06','path');g.search(0);g.search(1);const restored=new F.Game(F.copy(g.s));restored.search(2);restored.finishSearch();assert.equal(restored.s.spent,before+2);assert.equal(restored.s.clues.filter(x=>x==='seal').length,1);assert.throws(()=>restored.finishSearch());assert.throws(()=>restored.begin('E06','path'));
});
test('ledger fee cannot be charged twice after successful completion',()=>{const g=settled();g.begin('E07','ledger');assert.equal(g.s.money,10);assert.throws(()=>g.begin('E07','ledger'));assert.equal(g.s.money,10);});
test('failure carries costs and a real loss of evidence, with free recovery',()=>{
 const g=settled();g.begin('E07','ledger');const start=g.s.spent;g.begin('E10','fight');g.s.battle.status='lost';g.resolveBattle();assert.equal(g.s.spent,start+2);assert.equal(g.s.money,0);assert(g.s.wound);assert(g.s.flags.recordLost);assert(g.s.flags.exposed);assert(g.reason('E10','fight'));g.rest();assert(!g.s.wound);g.begin('E12','recover');assert(g.s.flags.lead);
});
test('Huai can leave, returns by calendar and never manufactures a main clue',()=>{
 const g=settled();g.sendHuai();assert(!g.s.team.includes('huai'));assert.throws(()=>g.team('huai',true));g.rest();assert(g.s.awayUntil);g.rest();assert.equal(g.s.awayUntil,0);assert.equal(g.s.clues.length,0);g.team('huai',true);assert(g.s.team.includes('huai'));
});
test('meeting Huai spends one slot, and chapter closure waits for her',()=>{
 const g=settled();g.begin('E07','ledger');g.sendHuai();assert(g.reason('E13','finish'));const before=g.s.spent;g.meetHuai();assert.equal(g.s.spent,before+1);g.begin('E13','finish');assert.equal(g.s.result,'doubt');
});
test('research guarantees progress and caches best per martial art and layer',()=>{
 const g=trained();g.startStudy('foot');g.s.pending.order=[0,1,2,3];g.submitStudy();assert.equal(g.s.best['foot:1'],4);assert.equal(g.s.studies.foot.progress,6);
 g.startStudy('foot',true);g.s.pending.order=[1,2,3,0];g.submitStudy();assert.equal(g.s.best['foot:1'],4);assert.equal(g.s.studies.foot.level,1);assert(g.s.actors.hero.learned.includes('cloud_step'));
 assert.equal(g.startStudy('foot'),'puzzle');assert.equal(g.s.pending.level,2);assert(!Object.hasOwn(g.s.best,'sword:1'));const restore=new F.Game(F.copy(g.s));assert.deepEqual(restore.s.pending.order,g.s.pending.order);
});
test('automatic study reuses record, spends time and does not open a puzzle',()=>{
 const g=trained();g.startStudy('sword');g.s.pending.order=[0,1,2,3];g.submitStudy();const t=g.s.spent;assert.equal(g.startStudy('sword'),'auto');assert.equal(g.s.spent,t+1);assert.equal(g.s.pending,null);assert.equal(g.s.studies.sword.level,1);assert(!g.s.actors.hero.deck.includes('opening_thrust'));
});
test('all martial layers have a finite route to their unlock and do not change the deck',()=>{
 const g=trained();for(const skill of ['sword','foot','inner']){for(let n=0;n<20&&g.s.studies[skill].level<2;n++){if(g.startStudy(skill)==='puzzle'){g.s.pending.order.sort((a,b)=>a-b);g.submitStudy();}}assert.equal(g.s.studies[skill].level,2);}
 g.changeInner('hero','xingyun');g.changeInner('hero','shouzhong');assert(g.s.actors.hero.learned.includes('sword_qi'));assert(g.s.actors.hero.learned.includes('hidden_needle'));assert(!g.s.actors.hero.deck.includes('sword_qi'));
});
test('party core and copy limits apply to every deck editor mutation',()=>{
 const g=settled();assert.throws(()=>g.changeCard('du',0,'breath'));assert.throws(()=>g.changeCard('hero',5,'strike'));assert.throws(()=>g.changeCard('hero',0,'sword_qi'));g.changeCard('du',9,'probing_stone');assert.equal(g.s.actors.du.deck[9],'probing_stone');g.begin('E03','practice');assert.throws(()=>g.changeCard('du',9,'breath'));
});
test('every encounter terminates with three actors using legal current hand actions',()=>{
 for(const id of ['E03','E05','E09','E10']){const g=settled();if(id==='E10')g.begin('E07','ledger');g.begin(id,id==='E03'?'practice':'fight');assert.equal(g.s.battle.current,id==='E09'?'enemy0':'huai');assert.equal(autoBattle(g),'won',id);assert(g.s.battle.round>1);g.resolveBattle();if(g.s.pending?.stage==='search')search(g);assert.equal(g.s.events[id],'done');}
});
test('all actor hands preserve card counts across turns, cycles, reshuffles and save restoration',()=>{
 const g=settled();g.begin('E09','fight');let b=g.s.battle;for(let n=0;n<300&&b.status==='active';n++){
  for(const a of b.actors.filter(a=>a.side==='ally')){const piles=[...a.hand,...a.draw,...a.discard,...a.exhaust];if(b.choice?.actor===a.id)piles.push(b.choice.card);assert.equal(piles.length,10);assert(a.momentum<=3&&a.gained<=2);}
  const restored=new F.Game(F.copy({...g.s,battle:b}));assert.deepEqual(restored.s.battle,b);F.aiStep(b);
 }
});
test('a single card cannot pay for itself using effects that resolve later',()=>{
 const g=settled();g.begin('E03','practice');const b=g.s.battle,a=F.actor(b);a.hand=['opening_thrust'];a.qi=1;a.momentum=0;const before=F.copy(b);assert.throws(()=>F.play(b,0,'enemy0',true));assert.deepEqual(b,before);
});
test('healing spends actor qi and the one shared battle medicine allowance',()=>{
 const g=settled();g.begin('E03','practice');const b=g.s.battle,a=F.actor(b),hero=F.actor(b,'hero');hero.hp-=30;const qi=a.qi;F.medicine(b,'hero');assert.equal(a.qi,qi-1);assert.equal(hero.hp,hero.maxHp-6);assert.throws(()=>F.medicine(b,'hero'));
});
test('delayed damage belongs to its actor and targets a stable enemy identity',()=>{
 const g=settled();g.begin('E03','practice');const b=g.s.battle,a=F.actor(b);a.hand=['hidden_needle'];a.qi=3;F.play(b,0,'enemy0');assert.deepEqual(a.delayed,[{target:'enemy0',damage:7}]);const hp=F.actor(b,'enemy0').hp;F.endTurn(b);while(b.current!==a.id&&b.status==='active'){const next=F.actor(b);if(next.side==='enemy')F.enemyAct(b);else F.endTurn(b);}assert.equal(F.actor(b,'enemy0').hp,hp-7);assert.equal(a.delayed.length,0);
});
test('mismatched pending battle and corrupt save cannot replace a healthy state',()=>{
 const g=settled(),s=F.copy(g.s);s.actors.hero.deck=['not-a-card'];assert.throws(()=>new F.Game(s));const date=F.copy(g.s);date.spent=-1;assert.throws(()=>new F.Game(date));g.begin('E03','practice');const missing=F.copy(g.s);missing.battle=null;assert.throws(()=>new F.Game(missing));assert(F.validateState(g.s));
});
test('independent state snapshots remain deterministic through automated action',()=>{
 const g=settled();g.begin('E07','ledger');g.begin('E10','fight');
 for(let i=0;i<7;i++)F.aiStep(g.s.battle);
 const restored=new F.Game(F.copy(g.s));
 for(let i=0;i<12;i++){if(g.s.battle.status==='active')F.aiStep(g.s.battle);if(restored.s.battle.status==='active')F.aiStep(restored.s.battle);}
 assert.deepEqual(g.s.battle,restored.s.battle);
});
