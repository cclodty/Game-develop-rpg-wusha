(function (root) {
  'use strict';
  const C = typeof module !== 'undefined' ? require('./catalog.js') : root.WuxiaCatalog;
  const T = typeof module !== 'undefined' ? require('./content.js') : root.FerryContent;
  const copy = x => JSON.parse(JSON.stringify(x));
  const basic = ['strike','strike','guard','guard','breath','observe','pushing_palm','pushing_palm','gather_momentum','gather_momentum'];
  const partyDefs = {
    hero:{name:'陳天佑',hp:68,speed:6,inner:'guiyuan',deck:basic,learned:['strike','guard','breath','observe','probing_stone','pushing_palm','gather_momentum']},
    huai:{name:'宋懷晴',hp:66,speed:8,inner:'xingyun',deck:['strike','strike','guard','guard','opening_thrust','opening_thrust','cloud_step','cloud_step','breath','sword_qi'],learned:['strike','guard','opening_thrust','cloud_step','breath','sword_qi','observe']},
    du:{name:'杜蘅',hp:76,speed:5,inner:'shouzhong',deck:['guard','guard','yielding_palm','yielding_palm','pushing_palm','pushing_palm','gather_momentum','observe','hidden_needle','breath'],learned:['guard','yielding_palm','pushing_palm','gather_momentum','observe','hidden_needle','breath','probing_stone']}
  };
  function assert(ok, message) { if (!ok) throw new Error(message); }
  function rng(holder) { let n=holder.rng|0; n ^= n<<13; n ^= n>>>17; n ^= n<<5; holder.rng=n>>>0 || 1; return holder.rng/4294967296; }
  function shuffle(a,h) { for(let i=a.length-1;i>0;i--){const j=Math.floor(rng(h)*(i+1));[a[i],a[j]]=[a[j],a[i]];} return a; }
  function newState(name='陳天佑') {
    const actors={}; Object.entries(partyDefs).forEach(([id,a])=>actors[id]={...copy(a),auto:id!=='hero',style:'balanced',core:a.deck.slice(0,7)});
    actors.hero.name=String(name).trim().slice(0,16)||'陳天佑';
    return {version:1,chapter:'ferry',spent:0,area:'haven',selected:'E01',actors,team:['hero','huai'],awayUntil:0,money:30,medicine:3,wound:false,flags:{},events:{E00:'done'},studies:{sword:{level:0,progress:0},foot:{level:0,progress:0},inner:{level:0,progress:0}},best:{},clues:[],log:[{date:'D1 早',text:'抵達落腳鎮。先去客舍與杜蘅碰面。'}],pending:null,battle:null,last:null,result:null,seed:18643,seen:[],sound:false};
  }
  function date(spent) {return `D${Math.floor(spent/3)+1} ${['早','午','晚'][spent%3]}`;}
  function counts(deck) { const out={};deck.forEach(x=>out[x]=(out[x]||0)+1);return out; }
  function validateState(s) {
    assert(s && s.version===1 && s.chapter==='ferry','這不是〈渡口餘波〉的存檔。');
    assert(Number.isInteger(s.spent)&&s.spent>=0&&s.spent<100000,'存檔日期不正確。');
    assert(Object.hasOwn(T.areas,s.area)&&Object.hasOwn(T.events,s.selected),'存檔地點不正確。');
    for(const key of ['money','medicine','seed','awayUntil']) assert(Number.isFinite(s[key])&&s[key]>=0,'存檔資源不正確。');
    assert(s.actors&&s.flags&&s.events&&s.studies&&s.best&&Array.isArray(s.clues)&&Array.isArray(s.log),'存檔內容不完整。');
    assert(Array.isArray(s.team)&&s.team.includes('hero')&&s.team.length<=3&&new Set(s.team).size===s.team.length&&s.team.every(x=>partyDefs[x]),'隊伍資料不正確。');
    for(const id of Object.keys(partyDefs)) {
      const a=s.actors[id]; assert(a&&typeof a.name==='string'&&a.name.length<=30&&C.inners[a.inner],'角色資料不正確。');
      assert(Array.isArray(a.learned)&&a.learned.every(x=>C.cards[x]),'武學資料不正確。');
      assert(Array.isArray(a.deck)&&a.deck.length===10&&a.deck.every(x=>a.learned.includes(x))&&Object.values(counts(a.deck)).every(n=>n<=2),'牌組資料不正確。');
      assert(Array.isArray(a.core)&&a.core.length===7&&a.core.every(x=>C.cards[x]),'同伴核心配置不正確。');
      assert(['balanced','attack','guard'].includes(a.style),'同伴策略不正確。');
    }
    for(const id of Object.keys(T.studies)) {const st=s.studies[id];assert(st&&Number.isInteger(st.level)&&st.level>=0&&st.level<=2&&Number.isFinite(st.progress)&&st.progress>=0,'研習資料不正確。');}
    for(const [key,value] of Object.entries(s.best)) assert(/^(sword|foot|inner):[12]$/.test(key)&&Number.isInteger(value)&&value>=0&&value<=4,'研習成績不正確。');
    assert(s.clues.every(x=>T.clues[x]),'證據資料不正確。');
    if(s.pending){
      const p=s.pending; assert(['event','study'].includes(p.type)&&Number.isInteger(p.cost)&&p.cost>=0&&p.cost<=2,'進行中的活動不正確。');
      if(p.type==='event') assert(T.events[p.id]&&T.events[p.id].choices.some(c=>c[0]===p.method)&&['battle','search'].includes(p.stage),'事件狀態不正確。');
      else assert(T.studies[p.skill]&&[1,2].includes(p.level)&&Array.isArray(p.order)&&new Set(p.order).size===p.order.length&&p.order.every(x=>Number.isInteger(x)&&x>=0&&x<p.order.length)&&p.order.length===p.level+3,'推演資料不正確。');
    }
    if(s.battle){validateBattle(s.battle);assert(s.pending&&s.pending.stage==='battle','戰鬥沒有對應活動。');}
    else assert(!s.pending||s.pending.stage!=='battle','進行中的戰鬥資料缺失。');
    return copy(s);
  }
  class Game {
    constructor(s) {this.s=s?validateState(s):newState();}
    static fresh(name) {return new Game(newState(name));}
    note(text) {this.s.log.push({date:date(this.s.spent),text});this.s.log=this.s.log.slice(-120);}
    clue(id) {if(!this.s.clues.includes(id))this.s.clues.push(id);}
    advance(n) {
      const s=this.s;s.spent+=n;
      for(const id of ['E06','E08']) if(s.spent>=T.events[id].deadline&&!['done','expired'].includes(s.events[id])) {s.events[id]='expired';this.note(id==='E06'?'潮水覆過舊棧道，原始現場已無法勘查。':'走方郎中按期離開渡口，這次未能再見。');}
      if(s.awayUntil&&s.spent>=s.awayUntil){s.awayUntil=0;this.note('懷晴已回客舍，可以再次邀請同行。');}
    }
    reason(id,method) {
      const s=this.s,e=T.events[id];if(!e)return '沒有這個事件。';
      if(s.pending)return '先完成或撤回目前的活動。';
      if(!e.choices.some(c=>c[0]===method))return '沒有這個做法。';
      if(id!=='E01'&&!s.flags.settled)return '先在客舍安頓。';
      if(s.events[id]==='done'&&!['E03','E04','E11'].includes(id))return '這件事已經完成。';
      if(s.events[id]==='expired'||(e.deadline&&s.spent+e.cost>e.deadline))return '已無法在期限前完成。';
      if(['E09','E10'].includes(id)&&s.events[id]==='lost')return '原件已被帶走，請循其他線索調查。';
      if(id==='E02'&&s.flags.party)return '同行安排已完成，可在隊伍頁調整。';
      if(id==='E06'&&method==='boat'&&!s.flags.trust)return '需要先取得船工信任。';
      if(id==='E07'&&!s.flags.trust&&s.money<20)return '查抄費20文，或先幫船工取得信任。';
      if(id==='E10'&&!s.clues.includes('ledger'))return '先查閱渡口帳簿。';
      if(id==='E10'&&method==='law'&&!s.flags.trust)return '需要船工引薦。';
      if(id==='E10'&&method==='stealth'&&s.studies.foot.level<1)return '需要渡水身法第一層。';
      if(id==='E12'&&s.events.E06!=='expired'&&!s.flags.recordLost)return '目前仍有原始線索可以追查。';
      if(id==='E11'&&!s.clues.length&&!s.wound)return '先帶回一項發現或經歷，再與懷晴商量。';
      if(['E11','E13'].includes(id)&&s.awayUntil>s.spent)return `懷晴分頭辦事，預計 ${date(s.awayUntil)} 回客舍。`;
      if(id==='E13'&&!s.flags.lead)return '先取得可靠的下游去向。';
      return '';
    }
    begin(id,method) {
      assert(!this.reason(id,method),this.reason(id,method));const s=this.s,e=T.events[id];
      if(id==='E07'&&!s.flags.trust)s.money-=20;
      s.pending={type:'event',id,method,cost:e.cost,stage:'story',found:[]};s.events[id]='active';
      if(id==='E10'&&method==='fight')s.flags.exposed=true;
      if(method==='fight'||id==='E03') {
        s.pending.stage='battle';s.seed=(s.seed+104729)>>>0;s.battle=createBattle(s,id);return 'battle';
      }
      if(e.search){s.pending.stage='search';return 'search';}
      this.finish(true);return 'complete';
    }
    search(index) {
      const p=this.s.pending;assert(p&&p.stage==='search','現在沒有勘查活動。');
      const clues=T.events[p.id].search;assert(Number.isInteger(index)&&index>=0&&index<clues.length,'沒有這個位置。');
      if(!p.found.includes(index))p.found.push(index);
    }
    finishSearch() {const p=this.s.pending;assert(p&&p.stage==='search'&&p.found.length===T.events[p.id].search.length,'還有現場需要查看。');this.finish(true);}
    finish(won,retreat=false) {
      const s=this.s,p=s.pending;assert(p&&p.type==='event','沒有進行中的事件。');
      const id=p.id;const success=won||id==='E03';s.battle=null;
      s.events[id]=success?'done':(['E09','E10'].includes(id)?'lost':'failed');
      if(success) {
        switch(id) {
          case 'E01':s.flags.settled=true;s.wound=false;break;
          case 'E02':s.flags.party=true;s.team=['hero','huai','du'];break;
          case 'E03':s.flags.training=true;break;
          case 'E04':s.money+=24;s.medicine+=1;break;
          case 'E05':s.flags.trust=true;s.money+=12;break;
          case 'E06':this.clue('seal');s.flags.footNote=true;s.studies.foot.progress+=2;break;
          case 'E07':this.clue('ledger');s.flags.lead=true;break;
          case 'E08':this.clue('doctor');s.flags.insight=true;s.medicine+=1;break;
          case 'E09':this.clue('roster');s.money+=20;break;
          case 'E10':this.clue('record');s.flags.lead=true;break;
          case 'E11':s.flags.reflected=true;break;
          case 'E12':this.clue('copy');s.flags.lead=true;break;
          case 'E13':s.result=s.flags.exposed?'exposed':(s.clues.includes('ledger')&&s.clues.includes('record')?'clear':'doubt');break;
        }
      } else {
        if(id==='E10')s.flags.recordLost=true;
        if(!retreat){s.wound=true;s.money=Math.max(0,s.money-20);}
      }
      s.pending=null;this.advance(p.cost);
      let message=success?`完成「${T.events[id].name}」。`:`${retreat?'撤離':'落敗'}「${T.events[id].name}」，保留已用時辰${retreat?'':'，受傷並損失至多20文'}。`;
      if(!success&&id==='E10')message+='守方轉移紀錄，可改查交運副簿。';
      this.note(message);s.last={id,success,retreat,message};
      return message;
    }
    resolveBattle() {
      const b=this.s.battle;assert(b&&b.status!=='active','戰鬥還沒結束。');
      if(b.status==='won'&&T.events[this.s.pending.id].search){this.s.battle=null;this.s.pending.stage='search';return 'search';}
      this.finish(b.status==='won',b.status==='retreat');return 'complete';
    }
    retreat() {assert(this.s.battle,'現在沒有戰鬥。');this.s.battle.status='retreat';return this.resolveBattle();}
    rest() {assert(!this.s.pending,'先完成目前活動。');assert(this.s.flags.settled,'先在客舍安頓。');this.advance(1);this.s.wound=false;this.note('在客舍休養一時段，傷勢已恢復。');}
    team(id,include) {
      const s=this.s;assert(!s.pending,'出行中不能調整同行安排。');assert(s.flags.party,'先與同伴約定同行。');assert(id==='huai'||id==='du','主角不能離隊。');
      assert(id!=='huai'||s.awayUntil<=s.spent,'懷晴仍在外辦事。');
      s.team=s.team.filter(x=>x!==id);if(include)s.team.push(id);
    }
    sendHuai() {assert(this.s.flags.party&&!this.s.pending&&!this.s.awayUntil,'目前無法分頭行動。');this.s.team=this.s.team.filter(x=>x!=='huai');this.s.awayUntil=this.s.spent+2;this.note(`懷晴前往附近核問消息，${date(this.s.awayUntil)} 回客舍；不會代替你完成取證。`);}
    meetHuai() {assert(!this.s.pending&&this.s.awayUntil>this.s.spent,'懷晴已在客舍。');this.advance(1);this.s.awayUntil=0;if(!this.s.team.includes('huai'))this.s.team.push('huai');this.note('沿約定的路與懷晴會合，一同回到客舍。');}
    changeCard(actor,slot,card) {
      assert(!this.s.pending,'活動途中不能換牌。');const a=this.s.actors[actor];assert(a&&a.learned.includes(card),'未學會這項招式。');assert(Number.isInteger(slot)&&slot>=0&&slot<10&&(actor==='hero'||slot>=7),'同伴核心七張招式不能更換。');
      const next=a.deck.slice();next[slot]=card;assert(Object.values(counts(next)).every(n=>n<=2),'同名招式最多兩張。');a.deck=next;
    }
    changeInner(id,inner) {assert(!this.s.pending&&id==='hero','同伴保留自己的主修內功。');assert(inner==='guiyuan'||(inner==='xingyun'&&this.s.studies.foot.level>=2)||(inner==='shouzhong'&&this.s.studies.inner.level>=2),'尚未學會這門內功。');this.s.actors[id].inner=inner;}
    startStudy(skill,replay=false) {
      const s=this.s;assert(!s.pending&&s.flags.training,'先完成院中試招，並結束目前活動。');assert(T.studies[skill],'沒有這門武學。');const st=s.studies[skill];assert(st.level<2,'本章已掌握此武學兩層。');
      const level=st.level+1,key=`${skill}:${level}`;s.pending={type:'study',skill,level,cost:1,order:shuffle(Array.from({length:level+3},(_,i)=>i),{rng:s.seed+level+skill.length})};
      if(Object.hasOwn(s.best,key)&&!replay){this.completeStudy(s.best[key],true);return 'auto';}return 'puzzle';
    }
    moveStudy(index) {const p=this.s.pending;assert(p&&p.type==='study'&&index>=0&&index<p.order.length,'沒有這步推演。');const j=(index+1)%p.order.length;[p.order[index],p.order[j]]=[p.order[j],p.order[index]];}
    submitStudy() {const p=this.s.pending;assert(p&&p.type==='study','沒有進行中的研習。');let correct=0;for(let i=0;i<p.order.length;i++)if(p.order[i]===i)correct++;return this.completeStudy(Math.round(correct/p.order.length*4));}
    completeStudy(score,automatic=false) {
      const s=this.s,p=s.pending;assert(p&&p.type==='study','沒有進行中的研習。');const key=`${p.skill}:${p.level}`,st=s.studies[p.skill];
      s.best[key]=Math.max(s.best[key]||0,score);const gained=2+score;st.progress+=gained;let upgraded=false;
      const threshold=p.level===1?8:10;
      if(st.progress>=threshold){st.progress-=threshold;st.level++;upgraded=true;const unlock=T.studies[p.skill].unlock[p.level-1];if(C.cards[unlock]&&!s.actors.hero.learned.includes(unlock))s.actors.hero.learned.push(unlock);if(p.skill==='foot'&&st.level===2)s.flags.xingyun=true;}
      s.pending=null;this.advance(1);const message=`${T.studies[p.skill].name}第${p.level}層：${automatic?'沿用最佳':'本次'} ${score}/4，獲得 ${gained} 進度${upgraded?'，已升層！':'。'} 最佳成績已保存。`;this.note(message);s.last={study:true,message};return message;
    }
    cancelStudy() {assert(this.s.pending?.type==='study','沒有進行中的研習。');return this.completeStudy(0);}
  }

  // Separate party actors share only the battlefield. Every hand, qi and momentum pool is private.
  function createBattle(s,event) {
    const spec={E03:[[100,7,'木劍陪練','practice']],E05:[[42,7,'攔路刀客','flurry'],[38,4,'攔路壯漢','charging']],E09:[[72,9,'草棚刀手','flurry'],[80,4,'蓄勁伏哨','charging']],E10:[[80,7,'河倉守衛','counter'],[72,4,'持盾守衛','armored']]}[event];
    const b={version:1,event,rng:s.seed,round:1,turn:0,queue:[],index:0,current:'',status:'active',actors:[],log:[],choice:null,medicine:s.medicine,medicineUsed:false,known:!!s.flags.insight||s.studies.inner.level>0,roster:s.clues.includes('roster')};
    for(const id of s.team){const a=s.actors[id];b.actors.push({id,name:a.name,side:'ally',hp:Math.max(1,a.hp-(id==='hero'&&s.wound?12:0)),maxHp:a.hp,speed:a.speed,inner:a.inner,auto:a.auto,style:a.style,qi:0,momentum:0,block:0,hand:[],draw:shuffle(a.deck.slice(),b),discard:[],exhaust:[],delayed:[],retaliation:0,retaliated:false,gained:0,paidType:'',innerGain:false,innerDraw:false,firstAttack:false,firstBlock:false,retain:-1,turns:0});}
    spec.forEach(([hp,speed,name,mode],i)=>b.actors.push({id:`enemy${i}`,name,side:'enemy',hp,maxHp:hp,speed,mode,block:0,turns:0,counterUsed:false,intent:null}));
    for(const e of b.actors.filter(a=>a.side==='enemy'))planEnemy(b,e);
    b.queue=b.actors.slice().sort((a,c)=>c.speed-a.speed||a.id.localeCompare(c.id)).map(a=>a.id);b.current=b.queue[0];startTurn(b);return b;
  }
  function actor(b,id=b.current){return b.actors.find(a=>a.id===id);}
  function living(b,side){return b.actors.filter(a=>a.side===side&&a.hp>0);}
  function log(b,text){b.log.push(text);b.log=b.log.slice(-70);}
  function gain(a,n){const v=Math.min(n,3-a.momentum,2-a.gained);if(v>0){a.momentum+=v;a.gained+=v;}}
  function draw(b,a,n){for(let i=0;i<n;i++){if(!a.draw.length){if(!a.discard.length)break;a.draw=shuffle(a.discard.splice(0),b);}a.hand.push(a.draw.pop());}}
  function settle(b){if(!living(b,'enemy').length)b.status='won';else if(!living(b,'ally').length)b.status='lost';}
  function hit(b,from,to,amount,react=true){if(!to||to.hp<=0)return;const absorbed=Math.min(to.block||0,amount);to.block=(to.block||0)-absorbed;const dealt=Math.max(0,amount-absorbed);to.hp=Math.max(0,to.hp-dealt);log(b,`${from.name} → ${to.name}：${dealt}傷害${absorbed?`／擋下${absorbed}`:''}`);
    if(react&&to.side==='ally'&&to.hp>0&&absorbed>0){if(to.inner==='shouzhong'&&!to.innerGain){gain(to,1);to.innerGain=true;}if(to.retaliation&&!to.retaliated&&from.hp>0){to.retaliated=true;hit(b,to,from,to.retaliation,false);}}
    settle(b);
  }
  function planEnemy(b,e){const allies=living(b,'ally');if(!allies.length)return;const target=allies[Math.floor(rng(b)*allies.length)].id;const n=e.turns%3;
    const patterns={practice:[['attack',9,1,0],['guard',0,1,10],['attack',14,1,0]],flurry:[['attack',5,2,0],['attack',8,1,0],['guard',0,1,8]],charging:[['charge',0,1,6],['attack',21,1,0],['attack',10,1,0]],counter:[['counter',9,1,8],['attack',13,1,0],['guard',0,1,14]],armored:[['guard',0,1,16],['attack',15,1,0],['attack',8,2,0]]};
    const [kind,damage,hits,block]=patterns[e.mode][n];e.intent={kind,damage,hits,block,target,counter:kind==='counter'?5:0};e.counterUsed=false;
  }
  function startTurn(b){const a=actor(b);if(!a||a.hp<=0){advanceTurn(b);return;}a.turns++;b.turn++;
    if(b.turn>240){b.status='retreat';log(b,'雙方久戰未決，隊伍先行撤出。');return;}
    if(a.side==='ally'){a.block=0;a.qi=3;a.gained=0;a.innerGain=false;a.innerDraw=false;a.paidType='';a.firstAttack=false;a.firstBlock=false;a.retaliation=0;a.retaliated=false;a.retain=-1;
      const delayed=a.delayed.splice(0);for(const d of delayed)hit(b,a,actor(b,d.target),d.damage,false);
      draw(b,a,Math.max(0,5-a.hand.length));log(b,`${a.name}行動：恢復3真氣，補至5張。`);
    } else {a.block=0;log(b,`${a.name}準備行動。`);}
  }
  function advanceTurn(b){settle(b);if(b.status!=='active')return;let count=0;do{b.index++;if(b.index>=b.queue.length){b.index=0;b.round++;}b.current=b.queue[b.index];count++;}while(actor(b).hp<=0&&count<=b.queue.length);startTurn(b);}
  function cardInfo(id,boost=false){const c=copy(C.cards[id]);assert(c,'未知招式。');c.id=id;c.momentumCost=boost?(c.boost?.cost||0):0;if(boost){assert(c.boost,'沒有運勁版本。');for(const [k,v]of Object.entries(c.boost)){if(k==='cost')continue;if(k==='damage_bonus')c.damage=(c.damage||0)+v;else if(k==='draw')c.draw=(c.draw||0)+v;else c[k]=v;}}return c;}
  function canPlay(b,index,targetId,boost=false){const a=actor(b);if(b.status!=='active'||!a||a.side!=='ally'||b.choice)return false;const id=a.hand[index];if(!id||!C.cards[id]||(boost&&!C.cards[id].boost))return false;const c=cardInfo(id,boost);const target=actor(b,targetId);if(a.qi<c.cost||a.momentum<c.momentumCost)return false;if((c.damage||c.strip_block||c.delayed_damage)&&(!target||target.side!=='enemy'||target.hp<=0))return false;return true;}
  function play(b,index,targetId,boost=false){assert(canPlay(b,index,targetId,boost),'真氣、勢或目標不符合這張牌的條件。');const a=actor(b),id=a.hand[index],c=cardInfo(id,boost),target=actor(b,targetId);a.hand.splice(index,1);a.qi-=c.cost;a.momentum-=c.momentumCost;if(a.retain===index)a.retain=-1;else if(a.retain>index)a.retain--;
    log(b,`${a.name}施展${c.name}${boost?'・運勁':''}。`);
    if(c.strip_block&&target)target.block=Math.max(0,target.block-c.strip_block);
    if(c.damage){let bonus=a.firstAttack?0:2;a.firstAttack=true;if(a.block>0)bonus+=c.guard_bonus||0;if(a.inner==='guiyuan'&&c.momentumCost===3)bonus+=8;hit(b,a,target,c.damage+bonus,false);}
    if(c.block){a.block+=c.block+(a.firstBlock?0:2);a.firstBlock=true;}
    if(c.retaliation)a.retaliation=Math.max(a.retaliation,c.retaliation);
    if(c.delayed_damage&&target?.hp>0)a.delayed.push({target:target.id,damage:c.delayed_damage});
    if(c.energy)a.qi=Math.min(20,a.qi+c.energy);if(c.momentum_gain)gain(a,c.momentum_gain);if(c.draw)draw(b,a,c.draw);
    if(c.cycle_limit&&b.status==='active'){b.choice={actor:a.id,card:id,boost,target:targetId,max:c.cycle_limit};return;}
    finishCard(b,a,c,target);
  }
  function finishCard(b,a,c,target){if(a.inner==='xingyun'&&c.cost>0){if(a.paidType&&a.paidType!==c.type&&!a.innerGain){gain(a,1);a.innerGain=true;}a.paidType=c.type;}
    if(a.inner==='shouzhong'&&c.momentumCost)a.block+=2*c.momentumCost;
    if(a.inner==='xingyun'&&c.momentumCost&&!a.innerDraw){draw(b,a,1);a.innerDraw=true;}
    if(c.type==='attack'&&target?.hp>0&&target.intent?.counter&&!target.counterUsed){target.counterUsed=true;hit(b,target,a,target.intent.counter,false);}
    (c.exhaust?a.exhaust:a.discard).push(c.id);settle(b);if(a.hp<=0&&b.status==='active')advanceTurn(b);
  }
  function resolveChoice(b,indices){const q=b.choice;assert(q,'沒有換牌選擇。');const a=actor(b,q.actor);assert(Array.isArray(indices)&&new Set(indices).size===indices.length&&indices.length<=q.max&&indices.every(i=>Number.isInteger(i)&&i>=0&&i<a.hand.length),'換牌選擇不正確。');indices.slice().sort((x,y)=>y-x).forEach(i=>a.discard.push(a.hand.splice(i,1)));a.retain=-1;draw(b,a,indices.length);b.choice=null;finishCard(b,a,cardInfo(q.card,q.boost),actor(b,q.target));}
  function endTurn(b,retain=-1){const a=actor(b);assert(b.status==='active'&&a.side==='ally'&&!b.choice,'現在不能結束回合。');assert(Number.isInteger(retain)&&retain>=-1&&retain<a.hand.length,'保留位置不正確。');const kept=retain>=0?[a.hand[retain]]:[];a.hand.forEach((c,i)=>{if(i!==retain)a.discard.push(c);});a.hand=kept;if(a.inner==='guiyuan'&&a.qi>0){a.qi--;gain(a,1);}advanceTurn(b);}
  function enemyAct(b){const e=actor(b);assert(b.status==='active'&&e.side==='enemy','現在不是敵方行動。');const p=e.intent;let target=actor(b,p.target);if(!target||target.hp<=0)target=living(b,'ally')[0];e.block+=p.block;for(let i=0;i<p.hits&&b.status==='active'&&e.hp>0;i++)if(p.damage)hit(b,e,target,p.damage);if(e.hp>0)planEnemy(b,e);advanceTurn(b);}
  function medicine(b,targetId){const a=actor(b),t=actor(b,targetId);assert(b.status==='active'&&a.side==='ally'&&!b.choice&&a.qi>=1&&b.medicine>0&&!b.medicineUsed&&t?.side==='ally'&&t.hp>0&&t.hp<t.maxHp,'不能在此時用藥。');a.qi--;b.medicine--;b.medicineUsed=true;t.hp=Math.min(t.maxHp,t.hp+24);log(b,`${a.name}為${t.name}用藥，恢復24氣血。`);}
  function aiStep(b){const a=actor(b);if(b.choice){resolveChoice(b,[]);return;}if(a.side==='enemy'){enemyAct(b);return;}
    const enemies=living(b,'enemy');if(!enemies.length){settle(b);return;}const target=enemies.slice().sort((x,y)=>x.hp-y.hp)[0];let best=null,bestScore=-1;
    a.hand.forEach((id,i)=>{for(const boost of [false,true]){if(!canPlay(b,i,target.id,boost))continue;const c=cardInfo(id,boost);let score=(c.damage||0)+(c.delayed_damage||0)*.8+(c.strip_block?Math.min(target.block,c.strip_block):0)+(c.energy||0)*7+(c.draw||0)*2+(c.momentum_gain||0)*4+(c.retaliation||0)*.6;
      const guardWeight=a.style==='guard'?1.6:a.style==='attack'?.55:1.0;score+=(c.block||0)*(a.block>=14?.1:guardWeight);if(c.damage&&a.style==='attack')score+=3;if(c.damage&&target.hp<=c.damage+2)score+=10;if(boost)score-=c.momentumCost*.7;
      if(score>bestScore){bestScore=score;best={i,boost};}}});
    if(best&&bestScore>.1)play(b,best.i,target.id,best.boost);else endTurn(b,a.hand.findIndex(id=>id==='sword_qi'));
  }
  function validateBattle(b){assert(b&&b.version===1&&['active','won','lost','retreat'].includes(b.status)&&Array.isArray(b.actors)&&b.actors.length>=2&&b.actors.length<=5,'戰鬥存檔不正確。');assert(['E03','E05','E09','E10'].includes(b.event)&&Number.isInteger(b.rng)&&Number.isInteger(b.turn)&&Number.isInteger(b.index)&&Array.isArray(b.queue),'戰鬥順序不正確。');
    assert(b.queue.length===b.actors.length&&new Set(b.queue).size===b.queue.length&&b.queue.every(id=>b.actors.some(a=>a.id===id))&&b.queue[b.index]===b.current,'戰鬥行動順序不完整。');
    for(const a of b.actors){assert(['ally','enemy'].includes(a.side)&&Number.isFinite(a.hp)&&a.hp>=0&&Number.isFinite(a.maxHp)&&a.maxHp>0&&a.hp<=a.maxHp&&Number.isFinite(a.block),'戰鬥氣血不正確。');if(a.side==='ally'){assert(partyDefs[a.id]&&C.inners[a.inner]&&Number.isFinite(a.qi)&&Number.isFinite(a.momentum)&&a.momentum>=0&&a.momentum<=3,'戰鬥角色不正確。');for(const pile of ['hand','draw','discard','exhaust'])assert(Array.isArray(a[pile])&&a[pile].every(id=>C.cards[id]),'手牌資料不正確。');assert(Array.isArray(a.delayed),'延遲招式資料不正確。');}else assert(a.intent&&['attack','guard','charge','counter'].includes(a.intent.kind)&&Number.isFinite(a.intent.damage),'敵人意圖不正確。');}
    if(b.choice)assert(actor(b,b.choice.actor)&&C.cards[b.choice.card]&&b.choice.max>=0,'換牌存檔不正確。');
  }
  const api={Game,newState,date,copy,partyDefs,validateState,createBattle,actor,living,cardInfo,canPlay,play,resolveChoice,endTurn,enemyAct,medicine,aiStep,validateBattle};root.Ferry=api;if(typeof module!=='undefined')module.exports=api;
})(globalThis);
