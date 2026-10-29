/* Native GAL presentation for the shared chapter model. Offline assets; independent saves. */
(() => {
  'use strict';
  const F=globalThis.Ferry,T=globalThis.FerryContent,C=globalThis.WuxiaCatalog,A=globalThis.FerryCardArt;
  const app=document.getElementById('app');
  const P=globalThis.GalPresentation;
  let reader=null,history=[],automatic=false,readTimer=null,previewTimer=null;
  let bagFilter='all',bagSelected='medicine',galleryCard='strike';
  let titleDraft='陳天佑',cropSerial=0;
  const preferenceKey='jianghu-gal-web-reading-v1';
  const defaults={speed:38,delay:1.8,reduced:false};
  let preferences={...defaults};
  try { const p=JSON.parse(localStorage.getItem(preferenceKey)); if(p){preferences={speed:[0,22,38,70].includes(p.speed)?p.speed:38,delay:Math.min(6,Math.max(1,Number(p.delay)||1.8)),reduced:!!p.reduced};} } catch {}
  function svgCrop(path,box,width,height,cls='') {
    const [x,y,w,h]=box.split(' ').map(Number),clip='crop-'+(++cropSerial);
    return `<svg class="${cls}" viewBox="${box}" preserveAspectRatio="xMidYMid meet" aria-hidden="true" focusable="false"><defs><clipPath id="${clip}"><rect x="${x}" y="${y}" width="${w}" height="${h}"/></clipPath></defs><image clip-path="url(#${clip})" href="${attr(path)}" width="${width}" height="${height}"/></svg>`;
  }
  function bust(id,expression=0,cls='') {
    const file=id==='hero'?'hero-player':id;
    return svgCrop(`../assets/generated/gal/${file}.png`,`${expression%2*512} ${Math.floor(expression/2)*768} 512 768`,1024,1536,`bust ${id} ${cls}`);
  }
  function itemArt(index,cls='') {
    const edges=[0,354,694,1024],row=Math.floor(index/4);
    return svgCrop('../assets/generated/gal/inventory-items.png',`${index%4*384} ${edges[row]} 384 ${edges[row+1]-edges[row]}`,1536,1024,'item-art '+cls);
  }
  function sceneBackground(area='haven') {
    const path=area==='haven'?'../assets/generated/gal/inn.png':`../chapter/assets/${T.areas[area]?.art||'village.png'}`;
    return `<div class="scene-background ${area}" style="background-image:url('${path}')" aria-hidden="true"></div>`;
  }
  function startReader(value) { reader={index:0,shown:0,speaker:'旁白',...value};automatic=false;rememberLine();persist();render(); }
  function openEvent(id) {const e=T.events[id];startReader({id,section:'intro',title:e.name,lines:e.intro});}
  function openStory(m) {modal=null;const id=game?.s.last?.id;startReader({id:T.events[id]?.name===m.title?id:null,section:'after',title:m.title,lines:m.lines,speaker:m.speaker});}
  function currentLine() {return reader?.lines[reader.index]||'';}
  function lineSpeaker() {return P.events[reader?.id]?.[reader?.section]?.[reader?.index]||reader?.speaker||'旁白';}
  function rememberLine() {
    if(!reader)return;
    const line={speaker:lineSpeaker(),text:currentLine(),title:reader.title};
    if(history.at(-1)?.text!==line.text)history.push(line);
    if(history.length>600)history=history.slice(-600);
  }
  function restoreUI(ui) {
    reader=null;history=[];automatic=false;
    const r=ui?.reader;
    if(r&&['intro','after'].includes(r.section)&&Array.isArray(r.lines)&&r.lines.length>0&&r.lines.length<100&&r.lines.every(x=>typeof x==='string'&&x.length<10000)&&Number.isInteger(r.index)&&r.index>=0&&r.index<r.lines.length) {
      reader={id:T.events[r.id]?r.id:null,section:r.section,title:String(r.title||'渡口紀事').slice(0,80),speaker:String(r.speaker||'旁白').slice(0,30),lines:r.lines,index:r.index,shown:Math.max(0,Math.min(r.lines[r.index].length,Number(r.shown)||0))};
    }
    if(Array.isArray(ui?.history))history=ui.history.filter(x=>typeof x?.text==='string'&&x.text.length<10000&&typeof x.speaker==='string').slice(-600).map(x=>({text:x.text,speaker:x.speaker.slice(0,30),title:String(x.title||'').slice(0,80)}));
  }
  function advanceReading() {
    if(!reader||modal)return;
    const text=currentLine();
    if(reader.shown<text.length){reader.shown=text.length;persist();render();return;}
    if(reader.index<reader.lines.length-1){reader.index++;reader.shown=0;rememberLine();persist();render();return;}
    if(reader.section==='intro')return; // Never choose on behalf of the player.
    reader=null;automatic=false;persist();render();
  }
  function readerMarkup() {
    const r=reader,text=currentLine(),meta=P.events[r.id]||{},finished=r.shown>=text.length;
    const hasChoices=r.section==='intro'&&r.index===r.lines.length-1;
    const e=T.events[r.id];
    const speaker=lineSpeaker();
    const choices=hasChoices?`<section class="vn-choices ${finished?'':'unrevealed'}" aria-label="對話選項"><h3>◇　請選擇回應　◇</h3>${e.choices.map(([method,label],i)=>{const reason=game.reason(r.id,method);return `<div>${btn(`<span class="choice-number">${i+1}</span><span>${h(label)}<small>${h(reason||(e.cost?`耗 ${e.cost} 時段　·　完成於 ${F.date(game.s.spent+e.cost)}`:'交談不耗時'))}</small></span>`,`event:${r.id}:${method}`,'vn-choice',!finished||!!reason)}</div>`;}).join('')}${btn('暫且離開，另作打算','reading-close','vn-leave',!finished)}</section>`:'';
    return `<div class="vn-heading">${h(r.title)} <span>${r.index+1} / ${r.lines.length}</span></div>${meta.companion?`${bust('hero',0,'left listener')}${bust(meta.companion,meta.expression||0,'right')}`:''}${choices}<section class="vn-panel paper"><div class="nameplate">${h(speaker)}</div><div class="vn-text" role="button" tabindex="0" data-action="advance" aria-label="${finished?'繼續閱讀':'顯示完整句子'}"><span id="revealed-text">${h(text.slice(0,r.shown))}</span><span class="reading-caret">${finished?'◇':'▏'}</span></div><footer class="vn-footer"><span>閱讀不耗時</span><div>${btn('回看','history','quiet')}${btn(automatic?'自動　開':'自動　關','auto-read','quiet')}${btn(({0:'即時',22:'慢',38:'適中',70:'快'})[preferences.speed]+'字速','cycle-speed','quiet')}${btn('設定','settings','quiet')}${!hasChoices?btn(finished?(r.index<r.lines.length-1?'繼續　▹':'回到場景　▹'):'顯示全文','advance','primary'):''}</div></footer></section>`;
  }
  function scheduleReading() {
    clearTimeout(readTimer);
    if(!reader||modal||document.hidden)return;
    const line=currentLine();
    if(preferences.speed===0&&reader.shown<line.length){reader.shown=line.length;persist();render();return;}
    if(reader.shown<line.length){
      readTimer=setTimeout(()=>{if(!reader||modal||document.hidden)return;reader.shown++;const el=document.getElementById('revealed-text');if(el)el.textContent=currentLine().slice(0,reader.shown);if(reader.shown>=currentLine().length){persist();render();}else scheduleReading();},1000/preferences.speed+(/[，。？！：；]/.test(line[reader.shown-1]||'')?180:0));
    }else if(automatic&&!(reader.section==='intro'&&reader.index===reader.lines.length-1)){
      readTimer=setTimeout(()=>advanceReading(),preferences.delay*1000);
    }
  }
  function frame(title,body,kind='',wide=true) {
    return `<div class="overlay" role="presentation"><section class="dialog paper ${wide?'wide':''} ${kind}" role="dialog" aria-modal="true" aria-labelledby="dialog-title"><header class="dialoghead"><div><span class="eyebrow">江湖未遠　／　渡口餘波</span><h2 id="dialog-title">${h(title)}</h2></div>${btn('返回','close')}</header><div class="dialogbody">${body}</div></section></div>`;
  }
  function inventoryItems() {
    const s=game.s;
    return [
      {id:'medicine',name:'傷藥',kind:'medicine',art:1,count:s.medicine,text:'交手時可為一位在場同伴恢復 24 氣血。每場限用一次，消耗 1 真氣。'},
      {id:'notebook',name:'隨身手札',kind:'key',art:2,count:1,text:'記下親眼所見，也記下尚未確定的事。此程的決定與所得，都留在這裡。'},
      {id:'coins',name:'銅錢',kind:'misc',art:3,count:s.money,text:'行路的盤纏。送藥短差可添些收入，查閱帳簿有時也需要付費。'},
      {id:'key',name:'銀匙',kind:'key',art:11,count:1,text:'裴守成託你保管的一枚待修銀匙。用途仍未明朗，暫且仔細收好。'},
      ...s.clues.map(id=>({id,name:T.clues[id],kind:'key',art:id==='seal'?4:2,count:1,text:'已取得的調查線索。打開手札，核對取得的經過與日期。'}))
    ];
  }
  function inventoryMarkup() {
    const items=inventoryItems(),filtered=items.filter(x=>bagFilter==='all'||x.kind===bagFilter);
    if(!filtered.some(x=>x.id===bagSelected))bagSelected=filtered[0]?.id;
    const selected=filtered.find(x=>x.id===bagSelected);
    return `<div class="overlay inventory-overlay"><section class="inventory" role="dialog" aria-modal="true" aria-labelledby="bag-title"><aside class="bag-left"><h2 id="bag-title" class="paper">行囊</h2><img class="satchel" src="../assets/generated/gal/inventory-bag.png" alt="攜帶書冊與行裝的旅人背包"><div class="bag-owner">${h(game.s.actors.hero.name)}的行囊</div><div class="nameplate purse">盤纏　${game.s.money} 文</div></aside><div class="bag-right paper"><header>${btn('返回','close')}</header><div class="bag-content"><section class="bag-items"><nav class="bag-tabs" aria-label="物品分類">${[['all','全部'],['medicine','藥物'],['key','要物'],['misc','雜物']].map(([id,label])=>btn(label,`bag-filter:${id}`,bagFilter===id?'primary':'')).join('')}</nav><div class="inventory-grid">${filtered.map(x=>btn(`${itemArt(x.art)}<span><span class="item-name">${h(x.name)}</span><em>${x.count}</em></span>`,`bag-select:${x.id}`,bagSelected===x.id?'selected':'')).join('')||'<p class="empty">此類尚無物品</p>'}</div><p class="bag-note">${filtered.length} 樣物件　／　此程隨身之物</p></section><section class="item-detail">${selected?`${itemArt(selected.art)}<h3>${h(selected.name)}</h3><p class="item-category">◇　${{medicine:'外用藥物',key:'隨身要物',misc:'行旅雜物'}[selected.kind]}　◇</p><p>${h(selected.text)}</p><div class="item-bottom"><p>持有　${selected.count}</p>${['notebook',...game.s.clues].includes(selected.id)?btn('翻閱手札','journal','primary'):btn(selected.id==='medicine'?'請於交手時用藥':'妥善收好','noop','',true)}</div>`:'<p class="empty">尚無可查看的物品</p>'}</section></div></div></section></div>`;
  }
  function customModal() {
    const kind=modal?.kind;
    if(kind==='inventory')return inventoryMarkup();
    if(kind==='settings')return frame('閱讀與演出',`<div class="settings-layout"><section class="reading-sample"><span class="eyebrow">文楷 · 試讀</span><h3>雨歇之後，再問前路。</h3><p id="sample-text"></p>${btn('重播試讀','replay-sample')}<small>點擊未播完的對話會先顯示全文，再次點擊才前進。</small></section><section class="settings-controls"><h3>文字播放速度</h3><div class="row">${[[22,'慢'],[38,'適中'],[70,'快'],[0,'即時全文']].map(([n,l])=>btn(l,`speed:${n}`,n===preferences.speed?'primary':'')).join('')}</div><label for="auto-delay">自動閱讀的句間停留　${preferences.delay.toFixed(1)} 秒</label><input id="auto-delay" type="range" min="1" max="6" step="0.2" value="${preferences.delay}"><p class="muted">遇到選項會停下，等你決定。</p>${btn(preferences.reduced?'減少動態：開':'減少動態：關','reduce-motion')}<p class="muted">這些設定只影響閱讀，不改變旅程日期、資源或選擇。</p></section></div>`,'settings');
    if(kind==='history')return frame('對話回看',`<div class="book-layout"><aside><span class="eyebrow">已讀片段</span><h3>一路所聞</h3><p>將說過的話，再讀一次。</p><img src="../assets/generated/gal/inventory-bag.png" alt=""></aside><div class="book-pages">${history.map(x=>`<article><small>${h(x.title)}　·　${h(x.speaker)}</small><p>${h(x.text)}</p></article>`).join('')||'<p class="empty">尚未開始閱讀。</p>'}</div></div>`,'history');
    if(kind==='journal')return frame('江湖手札',`<div class="book-layout"><aside><span class="eyebrow">此程線索</span><h3>見聞與所得</h3><div class="journal-clues">${game.s.clues.map(c=>`<p>◇ ${h(T.clues[c])}</p>`).join('')||'<p class="muted">尚無實物或證詞。<br>將親眼所見記下。</p>'}</div><div class="deadline">舊棧道 · D3 結束前<br>郎中 · D4 午前</div>${btn('回看已讀對話','history')}</aside><div class="book-pages">${game.s.log.slice().reverse().map(entry=>`<article><small>${h(entry.date)}</small><p>${h(entry.text)}</p></article>`).join('')}</div></div>`,'journal');
    if(kind==='gallery') {
      const ids=game.s.actors.hero.learned, c=F.cardInfo(galleryCard);
      return frame('招式圖鑑',`<div class="gallery-layout"><aside><span class="eyebrow">已學招式</span>${ids.map(id=>btn(h(C.cards[id].name),`gallery-card:${id}`,id===galleryCard?'primary':'')).join('')}</aside><div class="compare-cards">${['hero','huai'].map(actor=>`<article class="illustrated-card">${cardArt(actor,galleryCard,c.type)}<span>${h(game.s.actors[actor].name)}</span><h3>${h(c.name)}</h3><p>${h(desc(c))}</p>${c.boost?`<p class="gold">運勁 ${c.boost.cost} 勢<br>${h(desc(F.cardInfo(galleryCard,true)))}</p>`:''}<small>${A.resolve(actor,galleryCard)?'人物專屬牌面':'專屬插畫待補'}</small></article>`).join('')}</div></div>`,'gallery');
    }
    return null;
  }
  function savePreferences(){try{localStorage.setItem(preferenceKey,JSON.stringify(preferences));}catch{toast('無法保存閱讀設定；本次仍可使用。');}}
  function sampleReading() {
    clearTimeout(previewTimer);
    const el=document.getElementById('sample-text');if(!el)return;
    const text='雨停了，檐角的水仍一滴滴落在石槽裡。懷晴把劍放在伸手可及的地方，沒有催你起身。';let shown=0;
    const tick=()=>{if(!el.isConnected||document.hidden)return;shown=preferences.speed===0?text.length:shown+1;el.textContent=text.slice(0,shown);if(shown<text.length)previewTimer=setTimeout(tick,1000/preferences.speed);};tick();
  }
  function handlePresentation(kind,a,b) {
    if(kind==='settings'){openModal({kind:'settings'});return true;}
    if(kind==='speed'){preferences.speed=Number(a);savePreferences();render();return true;}
    if(kind==='reduce-motion'){preferences.reduced=!preferences.reduced;savePreferences();render();return true;}
    if(kind==='replay-sample'){sampleReading();return true;}
    if(kind==='cycle-speed'){const speeds=[22,38,70,0];preferences.speed=speeds[(speeds.indexOf(preferences.speed)+1)%4];savePreferences();render();return true;}
    if(kind==='advance'){advanceReading();return true;}
    if(kind==='auto-read'){automatic=!automatic;render();return true;}
    if(kind==='reading-close'){reader=null;automatic=false;persist();render();return true;}
    if(kind==='bag-filter'){bagFilter=a;render();return true;}
    if(kind==='bag-select'){bagSelected=a;render();return true;}
    if(kind==='gallery-card'){galleryCard=a;render();return true;}
    return false;
  }
  function applyUX() {
    document.documentElement.classList.toggle('reduced-motion',preferences.reduced);
    const overlay=document.querySelector('.overlay');if(overlay)document.getElementById('toast').classList.remove('show');app.classList.toggle('has-modal',!!overlay);const owner=document.querySelector('.bag-owner');if(owner)owner.style.fontSize=Math.min(27,Math.floor(280/(game.s.actors.hero.name.length+3)))+'px';
    for(const child of app.children)if(child!==overlay)child.inert=!!overlay;
    document.querySelectorAll('.deck-slot').forEach((el,i)=>{if(el.querySelector('svg,.card-art'))return;const id=game?.s.actors[teamTab].deck[i];if(id)el.insertAdjacentHTML('afterbegin',cardArt(teamTab,id,C.cards[id].type));});
    document.querySelectorAll('.study-box').forEach((el,i)=>{el.insertAdjacentHTML('afterbegin',cardArt('hero',['opening_thrust','cloud_step','breath'][i],'change'));});
    document.querySelectorAll('.inspect-object').forEach((el,i)=>{const edges=[0,560,985,1536];const art=game?.s.pending?.id==='E06'?svgCrop('../assets/generated/gal/investigation-clues.png',`${edges[i]} 200 ${edges[i+1]-edges[i]} 650`,1536,1024,'clue-art'):itemArt(2,'clue-art');el.insertAdjacentHTML('afterbegin',art);});
    if(modal?.kind==='puzzle'){const skill=game.s.pending.skill,ids={sword:['guard','opening_thrust','observe','strike'],foot:['observe','breath','cloud_step','guard'],inner:['observe','breath','gather_momentum','guard']}[skill];document.querySelectorAll('.breath-tile').forEach((el,i)=>{const token=game.s.pending.order[i];el.insertAdjacentHTML('afterbegin',cardArt('hero',ids[token]||'gather_momentum','change'));});}
    if(modal?.kind==='settings')sampleReading();
    clearTimeout(previewTimer && modal?.kind!=='settings'?previewTimer:null);
    updateMedicineControl();scaleViewport();
  }
  function updateMedicineControl(){const button=document.querySelector('[data-action="medicine"]'),select=document.getElementById('heal-target');if(!button||!select||!game?.s.battle)return;const b=game.s.battle,a=F.actor(b),t=F.actor(b,select.value);button.disabled=!!modal||b.status!=='active'||a.side!=='ally'||a.auto||!!b.choice||a.qi<1||b.medicine<1||b.medicineUsed||!t||t.hp<=0||t.hp>=t.maxHp;}
  function scaleViewport(){const scale=Math.min(innerWidth/1440,innerHeight/900);document.getElementById('viewport').style.cssText=`width:${1440*scale}px;height:${900*scale}px`;app.style.transform=`scale(${scale})`;}
  window.addEventListener('resize',scaleViewport);
  app.addEventListener('change',event=>{if(event.target.id==='heal-target')updateMedicineControl();if(event.target.id==='auto-delay'){preferences.delay=Number(event.target.value);savePreferences();render();document.getElementById('auto-delay')?.focus();}});

  const KEY='jianghu-gal-web-v1';
  let game=null,modal=null,modalPage=0,teamTab='hero',target='enemy0',selectedCard=0,cycleSelected=[],aiTimer=null,paused=false,toastTimer=null;
  let lastFocus=null;
  const h=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const attr=s=>h(s);
  const btn=(label,action,cls='',disabled=false,extra='')=>`<button data-action="${attr(action)}" class="${cls}" ${disabled?'disabled':''} ${extra}>${label}</button>`;
  const portrait=(id,name)=>`<div class="portrait ${id}" aria-hidden="true">${svgCrop('../assets/generated/gal/'+(id==='hero'?'hero-player':id)+'.png','100 70 310 310',1024,1536)}</div>`;
  function cardArt(actor,id,type) {
    const art=A.resolve(actor,id);
    if(!art)return `<span class="card-art card-art-neutral" data-art-actor="neutral" aria-hidden="true">${{attack:'攻',guard:'守',change:'變'}[type]||'招'}</span>`;
    return svgCrop('../chapter/'+art.url,art.viewBox,art.width,art.height,'card-art').replace('<svg ',`<svg data-art-actor="${attr(actor)}" data-art-card="${attr(id)}" `);
  }
  function toast(text){const el=document.getElementById('toast');el.textContent=text;el.classList.add('show');clearTimeout(toastTimer);toastTimer=setTimeout(()=>el.classList.remove('show'),4500);}
  function readSave(slot='auto'){try{const raw=localStorage.getItem(`${KEY}:${slot}`);if(!raw)return null;const parsed=JSON.parse(raw);return {state:F.validateState(parsed.state),savedAt:parsed.savedAt,ui:parsed.ui};}catch{return null;}}
  function persist(slot='auto',notify=false){if(!game)return;try{const key=`${KEY}:${slot}`;if(slot==='auto'){const prev=localStorage.getItem(key);if(prev)localStorage.setItem(`${KEY}:backup`,prev);}localStorage.setItem(key,JSON.stringify({state:game.s,savedAt:new Date().toISOString(),ui:{reader,history}}));if(notify)toast('已保存旅程。');}catch{toast('瀏覽器無法保存。請到存檔頁下載備份，避免進度遺失。');}}
  function openModal(m){
    clearTimeout(aiTimer); clearTimeout(readTimer);
    if(!game)titleDraft=document.getElementById('hero-name')?.value||titleDraft;
    if(m.kind==='story') { openStory(m); return; }
    lastFocus=document.activeElement?.dataset?.action||null;
    modal=m; modalPage=0; render();
    requestAnimationFrame(()=>document.querySelector('[role=dialog] button:not(:disabled),[role=dialog] input')?.focus());
  }

  function closeModal(){modal=null;render();if(lastFocus)document.querySelector(`[data-action="${CSS.escape(lastFocus)}"]`)?.focus();}

  function setArea(id){if(game.s.pending)return toast('請先完成目前活動。');if(!game.s.flags.settled&&id!=='haven')return toast('先去客舍安頓。');reader=null;game.s.area=id;game.s.selected=T.areas[id].points[0][0];persist();render();}
  function showTitle(){
    clearTimeout(aiTimer);clearTimeout(readTimer);game=null;modal=null;reader=null;automatic=false;
    const saved=readSave();
    app.innerHTML=`<main class="title-page"><div class="title-landscape"></div><section class="title-content paper"><div class="eyebrow">第一章 · 雨歇之後</div><h1>江湖未遠<small>渡口餘波</small></h1><p class="synopsis">一枚銀匙，一段未明的往事。<br>雨後的渡口，仍有一條路可以走。</p><label for="hero-name">這一程，如何稱呼你？</label><input id="hero-name" maxlength="16" value="${h(titleDraft)}" autocomplete="off">${btn('初到渡口　◇','new','primary')}${saved?btn(`續寫此程　·　${h(F.date(saved.state.spent))}`,'continue'):''}${btn('讀取手札','title-saves')}<a class="battle-entry" href="../battle/">基本牌 · 戰鬥試牌場 →</a>${btn('閱讀設定','settings','quiet')}<p class="meta">手繪視覺小說 · 區域探索 · 三人卡牌交手<br>試玩從逃亡後開始，正式創角問答另行製作。</p></section><p class="title-verse">雨過山色新<br>江湖未遠人未歸</p><div class="edition">渡口餘波　／　網頁試玩</div></main>`;
    applyUX();
  }

  function topbar(){const s=game.s;return `<header class="topbar"><div class="brand"><span class="seal">江<br>湖</span><div><h1>江湖未遠</h1><small>渡口餘波</small></div></div><div class="clock">${h(F.date(s.spent))}<span>　${['晨霧未散','日影漸移','暮色將至'][s.spent%3]}</span></div><nav class="toolbar" aria-label="旅程選單">${[['inventory','行囊'],['journal','手札'],['party','人物'],['study','研習'],['gallery','招式'],['saves','存讀'],['settings','設定']].map(([a,l])=>btn(l,a)).join('')}${btn('？','help','',false,'aria-label="操作說明"')}</nav></header>`;}

  function goal(){const s=game.s;if(s.result)return ['E13','本章已收束，可以留鎮探索'];if(!s.flags.settled)return ['E01','先在客舍安頓，與杜蘅碰面'];if(!s.flags.party)return ['E02','約定同行，熟悉三人的配合'];if(!s.flags.training)return ['E03','到院中試招，開放研習'];if(!s.flags.trust)return ['E05','替船工解難，打開人情路徑'];if(!s.flags.lead)return ['E07','查閱帳簿，確認船行去向'];if(!s.clues.includes('record')&&!s.flags.recordLost)return ['E10','前往河倉，核對茶院交接紀錄'];if(!s.result)return ['E13','與懷晴會合，整理下一站去向'];return ['E13','本章已收束，可以留鎮探索'];}



  function searchMarkup(){const p=game.s.pending,e=T.events[p.id];return `<article class="event-card"><span class="tag">現場勘查 · 時間已計入活動</span><h2>${h(e.name)}</h2><p class="muted">查看每一處痕跡，再整理能帶走的證據。閱讀與觀察不額外扣時。</p><div class="search-grid">${e.search.map(([name,desc],i)=>`<button class="inspect-object ${p.found.includes(i)?'found':''}" data-action="inspect:${i}"><strong>${p.found.includes(i)?'✓ ':'◇ '}${h(name)}</strong><p>${p.found.includes(i)?h(desc):'走近看看 →'}</p></button>`).join('')}</div>${btn('整理證物，結束勘查','finish-search','primary',p.found.length!==e.search.length)}<p class="muted" style="font-size:12px;margin-top:12px">${p.found.length} / ${e.search.length} 處已查看</p></article>`;}
  function exploration(){const s=game.s;return `${topbar()}<main class="journey ${reader?'reading':''}">${sceneBackground(s.area)}${reader?readerMarkup():`<div class="location-heading"><span class="eyebrow">此地 · ${h(T.areas[s.area].subtitle)}</span><h2>${h(T.areas[s.area].name)}</h2></div><nav class="locationtabs" aria-label="探索地點">${Object.entries(T.areas).map(([id,a])=>btn(h(a.name),`area:${id}`,s.area===id?'active':'',!!s.pending||!s.flags.settled&&id!=='haven')).join('')}</nav>${s.pending?.stage==='search'?searchMarkup():`<div class="scene-points">${T.areas[s.area].points.map(([id,x,y],i)=>`<button class="scene-point ${s.events[id]==='done'?'done':''}" data-action="point:${id}" style="left:${[12,48,32,72,15,66][i]}%;top:${[25,12,43,35,55,68][i]}%"><span>◇</span>${h(T.events[id].name)}<small>${s.events[id]==='done'?'已記入手札':s.events[id]==='expired'?'時機已過':T.events[id].kind}</small></button>`).join('')}</div>`}<aside class="journey-goal paper"><span class="eyebrow">此程所向</span><p>${h(goal()[1])}</p>${btn('查看眼前之事　→',`goto:${goal()[0]}`,'quiet')}</aside><footer class="journey-footer"><div>${h(s.actors.hero.name)}　·　盤纏 ${s.money} 文　·　傷藥 ${s.medicine}${s.wound?'　·　帶傷':''}</div><div>${s.flags.settled?btn('客舍休養','rest','',!!s.pending):''}${btn('旅程回看','history')}${s.result?btn('此程結果','outcome'):''}</div></footer>`}</main>`;}

  function desc(c){const parts=[];if(c.strip_block)parts.push(`移除${c.strip_block}防護`);if(c.damage)parts.push(`造成${c.damage}傷害`);if(c.guard_bonus)parts.push(`有防護再加${c.guard_bonus}`);if(c.block)parts.push(`獲得${c.block}防護`);if(c.draw)parts.push(`抽${c.draw}張`);if(c.cycle_limit)parts.push(`可換${c.cycle_limit}張牌`);if(c.energy)parts.push(`回復${c.energy}真氣`);if(c.momentum_gain)parts.push(`獲得${c.momentum_gain}勢`);if(c.delayed_damage)parts.push(`下次行動造成${c.delayed_damage}傷害`);if(c.retaliation)parts.push(`準備${c.retaliation}反擊`);if(c.exhaust)parts.push('本場除外');return parts.join('；');}
  function intent(e,b){const label={attack:'進攻',guard:'防守',charge:'蓄勢',counter:'反制'}[e.intent.kind];const known=b.known&&(b.event==='E05'||b.event==='E09')||b.event==='E03'||b.event==='E10'&&b.roster;if(!known)return `${label} · 細節未明<br><span class="muted">情報或研習可辨認</span>`;const t=F.actor(b,e.intent.target);return `${label}${e.intent.damage?` ${e.intent.damage}×${e.intent.hits} → ${h(t?.name||'我方')}`:''}${e.intent.block?` · 防護${e.intent.block}`:''}${e.intent.counter?` · 反制${e.intent.counter}`:''}`;}
  function fighter(a,b){return `<div class="fighter ${b.current===a.id?'current':''} ${a.side==='enemy'&&target===a.id?'target':''} ${a.hp<=0?'dead':''}" ${a.side==='enemy'&&a.hp>0?`role="button" tabindex="0" data-action="target:${a.id}" aria-label="選擇目標 ${attr(a.name)}"`:''}>${a.side==='ally'?portrait(a.id,a.name):`<div class="portrait" style="background:#ac7556;color:#fff3db">${a.mode==='practice'?'試':'敵'}</div>`}<h3>${h(a.name)}</h3><div class="hp-track"><span style="width:${a.hp/a.maxHp*100}%"></span></div><div class="numbers">氣血 ${a.hp}/${a.maxHp} · 防護 ${a.block}</div>${a.side==='ally'?`<div class="numbers">真氣 ${a.qi} · 勢 ${a.momentum}</div>${a.hp>0?btn(a.auto?'自行出牌 · 接管':'手動 · 委託出牌',`control:${a.id}`,'small'):''}`:`<div class="intent">${a.hp>0?intent(a,b):'已無力再戰'}</div>`}</div>`;}
  function battleMarkup(){const s=game.s,b=s.battle,a=F.actor(b);if(!F.living(b,'enemy').some(e=>e.id===target))target=F.living(b,'enemy')[0]?.id||'';if(selectedCard>=a.hand?.length)selectedCard=0;const c=a.side==='ally'&&a.hand[selectedCard]?F.cardInfo(a.hand[selectedCard]):null;
    const manual=b.status==='active'&&a.side==='ally'&&!a.auto&&!modal;const control=manual&&!b.choice;
    return `${topbar()}<main class="battle"><div class="turn-order"><span class="eyebrow">行動次序</span>${b.queue.filter(id=>F.actor(b,id).hp>0).map(id=>`<span class="turn-chip ${b.current===id?'now':''} ${F.actor(b,id).side==='enemy'?'foe':''}">${h(F.actor(b,id).name)} · ${F.actor(b,id).speed}</span>`).join('')}<span class="muted" style="font-size:12px">第 ${b.round} 輪</span></div><section class="battlefield"><div class="battle-head"><div><span class="eyebrow">${b.event==='E03'?'院中切磋':'江湖交手'}</span><h2>${h(T.events[b.event].name)}</h2></div><div class="row">${btn(paused?'繼續自動行動':'暫停自動行動','pause-ai','small')}${btn(b.event==='E03'?'收劍認輸':'撤退', 'ask-retreat','danger small',b.status!=='active')}</div></div><div class="fighters"><div class="party-fighters">${b.actors.filter(a=>a.side==='ally').map(a=>fighter(a,b)).join('')}</div><div class="vs">交鋒</div><div class="enemy-fighters">${b.actors.filter(a=>a.side==='enemy').map(a=>fighter(a,b)).join('')}</div></div></section>${b.status!=='active'?`<div class="outcome" style="margin-top:20px"><div class="eyebrow">此番交手</div><h2>${b.status==='won'?'已分勝負':b.status==='retreat'?'暫且收手':'尚有退路'}</h2><p>${b.status==='won'?'對方已無力阻攔。把眼前的事收好，再決定下一步。':b.event==='E03'?'這是切磋，認輸不會受傷，也不影響學武。':'同伴扶你離開。這次的時間已經用去；傷勢、財物與證據將依事件留下後果。'}</p>${btn('收束交手 →','battle-result','primary',false,'style="margin-top:18px"')}</div>`:`<div class="turn-heading"><h3>${h(a.name)}的回合 <span class="energy">${a.side==='ally'?`真氣 ${a.qi} ／ 勢 ${a.momentum}`:''}</span></h3><span class="new-turn">${paused?'自動行動已暫停':a.side==='enemy'?'對手即將出招':a.auto?'同伴自行安排出招':'選手牌 → 選目標 → 普通或運勁'}</span></div>${a.side==='ally'?`<div class="hand" aria-label="目前角色手牌">${a.hand.map((id,i)=>{const c=F.cardInfo(id);return `<button class="card ${i===selectedCard?'selected':''}" data-action="card:${i}" aria-label="${attr(c.name)}，${c.cost}真氣，${attr(desc(c))}"><span class="cost">${c.cost}</span><span class="type">${{attack:'攻',guard:'守',change:'變'}[c.type]}</span>${cardArt(a.id,id,c.type)}<span class="card-user">${h(a.name)}</span><h3>${h(c.name)}</h3><span class="desc">${h(desc(c))}</span>${c.boost?`<span class="boost">運勁 ${c.boost.cost}勢：${h(desc(F.cardInfo(id,true)))}</span>`:''}${a.retain===i?'<span class="retain">留至下回合</span>':''}</button>`;}).join('')||'<div class="empty">手牌已用盡，可以結束回合。</div>'}</div>${b.choice?`<div class="rules"><strong>掠影步 · 選擇換掉的牌</strong><div class="row" style="margin:10px 0">${a.hand.map((id,i)=>btn(`${cycleSelected.includes(i)?'✓ ':''}${h(C.cards[id].name)}`,`cycle:${i}`,cycleSelected.includes(i)?'primary small':'small')).join('')}</div>${btn(cycleSelected.length?`換掉 ${cycleSelected.length} 張`:'略過換牌','cycle-done','primary',!manual)}</div>`:`<div class="battle-actions">${btn(c?`普通施展 · ${c.cost}真氣`:'普通施展','play','primary',!control||!F.canPlay(b,selectedCard,target))}${btn(c?.boost?`運勁 · ${c.boost.cost}勢`:'無運勁版本','boost','',!control||!F.canPlay(b,selectedCard,target,true))}${btn(a.retain===selectedCard?'取消留牌':'保留此牌','retain','',!control||!c)}${btn('結束回合 →','end-turn','primary',!control)}<select id="heal-target" aria-label="用藥對象">${F.living(b,'ally').map(x=>`<option value="${x.id}" ${x.id===a.id?'selected':''}>${h(x.name)} ${x.hp}/${x.maxHp}</option>`).join('')}</select>${btn(`用藥 · 1真氣${b.medicineUsed?'（本場已用）':''}`,'medicine','',!control||a.qi<1||b.medicine<1||b.medicineUsed)}</div>`}`:'<div class="auto-banner">對手正在行動。可暫停查看資訊，也能先調整同伴是否由你接管。</div>'}<p class="battle-guide">每人回合恢復3真氣；勢最多3點、每個自己的回合週期最多取得2點。留牌占下回合一格。用藥每場一次。閱讀與思考不推進日期。</p>`}<section class="battle-log" aria-label="交手紀錄">${c?`<div class="selected-rules"><strong>${h(c.name)}</strong><p>${h(desc(c))}</p>${c.boost?`<p class="gold">運勁 ${c.boost.cost} 勢：${h(desc(F.cardInfo(c.id,true)))}</p>`:''}</div>`:''}${b.log.slice(-5).map(x=>`<p>${h(x)}</p>`).join('')}</section></main>`;
  }
  function modalMarkup(){if(!modal)return '';const custom=customModal();if(custom!==null)return custom;const s=game?.s;let title='',body='',wide=false,canClose=true;
    if(modal.kind==='confirm'){title=modal.title;body=`<p>${h(modal.text)}</p><div class="dialogfooter">${btn('再想一想','close')}${btn(h(modal.label||'確定'),modal.action,'primary')}</div>`;}
    if(modal.kind==='party'){title='同行與配招';wide=true;const a=s.actors[teamTab];body=`<div class="tab-row">${Object.entries(s.actors).map(([id,v])=>btn(h(v.name),`team-tab:${id}`,id===teamTab?'active':'')).join('')}</div><div class="row between"><div class="row">${portrait(teamTab,a.name)}<div><h3>${h(a.name)}</h3><p class="muted">氣血${a.hp} · 速度${a.speed} · ${h(C.inners[a.inner].name)}</p></div></div><div class="row">${teamTab!=='hero'?btn(s.team.includes(teamTab)?'暫時留守':'邀請同行',`team-toggle:${teamTab}`,'',!!s.pending||!s.flags.party||(teamTab==='huai'&&s.awayUntil>s.spent)):''}${btn(a.auto?'改為手動出牌':'預設自行出牌',`default-auto:${teamTab}`,'',!!s.pending)}</div></div><div class="stat" style="margin:15px 0">${h(C.inners[a.inner].description)}</div>${teamTab==='hero'?`<div class="row" style="margin-bottom:18px"><span>主修內功</span>${Object.entries(C.inners).map(([id,n])=>btn(h(n.name),`inner:${id}`,a.inner===id?'primary small':'small',!!s.pending||!(id==='guiyuan'||id==='xingyun'&&s.studies.foot.level>=2||id==='shouzhong'&&s.studies.inner.level>=2))).join('')}</div>`:`<div class="row" style="margin:12px 0"><span>自行出牌傾向</span>${[['balanced','均衡'],['attack','進取'],['guard','穩守']].map(([id,label])=>btn(label,`style:${teamTab}:${id}`,a.style===id?'primary small':'small',!!s.pending)).join('')}</div>`}<p class="muted" style="font-size:13px;margin-bottom:12px">固定十張，同名最多兩張。${teamTab==='hero'?'新學會的招式需自行換入。':'前七張保留人物核心風格，後三張可以調整。'}</p><div class="deck-grid">${a.deck.map((id,i)=>`<div class="deck-slot"><span class="muted">${String(i+1).padStart(2,'0')}</span>${teamTab!=='hero'&&i<7?`<span class="locked">${h(C.cards[id].name)} · 核心</span>`:`<select data-deck-actor="${teamTab}" data-deck-slot="${i}" aria-label="第${i+1}張招式" ${s.pending?'disabled':''}>${a.learned.map(card=>`<option value="${card}" ${card===id?'selected':''}>${h(C.cards[card].name)} · ${C.cards[card].cost}真氣</option>`).join('')}</select>`}</div>`).join('')}</div>${s.flags.party?`<div class="divider"></div><div class="row">${btn('與懷晴分頭辦事 · 2時段後回來','send-huai','',!!s.pending||s.awayUntil>s.spent)}${s.awayUntil>s.spent?btn('前去會合 · 1時段','meet','',!!s.pending):''}</div><p class="muted" style="font-size:12px;margin-top:8px">分開時你仍可調查；懷晴不會暗中代為完成主線。杜蘅在本區協助，離區時留鎮。</p>`:''}`;}
    if(modal.kind==='study'){title='研習武學';wide=true;body=`<p class="muted" style="margin-bottom:20px">每次研習耗一時段，保底獲得2進度；推演表現再加0–4進度。同一武學、同一層保存最佳成績，下一次自動套用。</p><div class="study-list">${Object.entries(T.studies).map(([id,v])=>{const st=s.studies[id],level=Math.min(2,st.level+1),best=s.best[`${id}:${level}`],max=level===1?8:10;return `<div class="study-box"><span class="eyebrow">已掌握 ${st.level} / 2 層</span><h3>${h(v.name)}</h3><p>${h(v.text)}</p><progress value="${st.level>=2?max:st.progress}" max="${max}"></progress><div class="muted" style="font-size:12px">${st.level>=2?'本章兩層已完成':`第${level}層進度 ${st.progress}/${max} · ${best===undefined?'尚未推演':`最佳${best}/4`}`}</div>${btn(st.level>=2?'本章已學成':best===undefined?'首次推演 · 1時段':'沿用最佳 · 1時段',`study-start:${id}`,'primary',st.level>=2||!!s.pending||!s.flags.training)}${best!==undefined&&st.level<2?btn('重玩，挑戰更好成績',`study-replay:${id}`,'',!!s.pending||!s.flags.training):''}<div class="muted" style="font-size:12px;margin-top:12px">一層：${h(C.cards[v.unlock[0]]?.name||C.inners[v.unlock[0]]?.name)}<br>二層：${h(C.cards[v.unlock[1]]?.name||C.inners[v.unlock[1]]?.name)}${id==='foot'?'、行雲訣':''}</div></div>`;}).join('')}</div>${!s.flags.training?'<p class="red" style="margin-top:18px">先在院中完成一次試招，即使認輸也能開始研習。</p>':''}`;}
    if(modal.kind==='puzzle'){const p=s.pending,v=T.studies[p.skill],tokens=[...v.tokens];if(p.level===2)tokens.splice(3,0,'轉勁');title=`${v.name} · 第${p.level}層`;canClose=false;body=`<p class="muted">將步驟排成連貫的運功順序。點一張牌，便與右側交換；最後一張會與第一張交換。沒有倒數。</p><div class="rules">${v.rules.map(x=>`<div>· ${h(x)}</div>`).join('')}${p.level===2?'<div>· 轉勁緊接第三步，收束動作仍放最後。</div>':''}</div><div class="breath-sequence">${p.order.map((n,i)=>`<button class="breath-tile" data-action="study-swap:${i}" aria-label="交換第${i+1}步 ${attr(tokens[n])}"><small>第 ${i+1} 步</small><span>${h(tokens[n])}</span><small>與右側交換 ⇄</small></button>`).join('')}</div><div class="dialogfooter">${btn('存讀檔','puzzle-saves')}${btn('收功，取得保底進度','study-cancel')}${btn('完成本次推演','study-submit','primary')}</div>`;}
    if(modal.kind==='saves'){wide=true;title='保存這段旅程';body=`<p class="muted" style="margin-bottom:18px">自動存檔不覆蓋三個手動欄位。檔案備份可以帶到另一個瀏覽器；載入會回到保存時的日期與選擇。縮圖為場景示意。</p><div class="save-grid">${['auto','1','2','3','backup'].map(slot=>{const saved=readSave(slot);let broken=false;try{broken=!!localStorage.getItem(`${KEY}:${slot}`)&&!saved;}catch{}return `<div class="save-slot"><strong>${{auto:'自動存檔',backup:'上一次自動備份'}[slot]||`手動欄位 ${slot}`}</strong><small>${saved?`${h(saved.state.actors.hero.name)} · ${h(F.date(saved.state.spent))}<br>${h(new Date(saved.savedAt).toLocaleString('zh-TW'))}`:broken?'存檔損壞，原檔保留':'尚未保存'}</small><div class="row">${!['auto','backup'].includes(slot)?btn('寫入',`save:${slot}`,'small',!game):''}${btn('載入',`load:${slot}`,'small',!saved)}</div></div>`;}).join('')}</div><div class="divider"></div><div class="row">${btn('下載存檔備份','export','primary',!game)}${btn('匯入存檔檔案','import')}${game?btn('保存並回標題','title','quiet'):''}</div>`;}
    if(modal.kind==='outcome'){title='渡口餘波 · 此程結果';const result=T.results[s.result];body=`<div class="outcome"><span class="eyebrow">這次帶走的江湖</span><h2>${h(result.name)}</h2><p>${h(result.text)}</p><div class="evidence-row">${s.clues.map(c=>`<span class="tag">${h(T.clues[c])}</span>`).join('')}</div></div><p class="muted" style="margin-top:18px">${h(F.date(s.spent))} · ${s.clues.length}份線索 · ${s.flags.exposed?'對方已提高警戒':'尚未留下武力曝光紀錄'}。下一區域尚未開放；本章可以繼續探索、修練，或讀檔體驗另一條路。</p><div class="dialogfooter">${btn('留在鎮上','close','primary')}${btn('下載此程存檔','export')}</div>`;}
    if(modal.kind==='help'){title='初行江湖';body=`<ul class="help-list"><li>點選場景中的事件進入對話，再選擇做法。查看場景、閱讀不耗時。</li><li>早、午、晚各一時段。活動前顯示耗時；已知期限在右側提醒。</li><li>三人依速度輪流行動，每人各有十張牌、真氣與勢。敵人不隨你的成長變強。</li><li>點選手牌與敵人，再選普通施展或運勁。每回合可保留一張。</li><li>同伴預設自行出牌；角色下方按鈕可接管。想慢慢看，先暫停自動行動。</li><li>不同情報揭露不同敵人的意圖。院中切磋會完整顯示，野外交手需蒐集情報。</li><li>戰敗可能受傷、損失財物或證據。客舍可免費休養一時段；普通戰鬥可撤退。</li><li>研習保底有進步，每門每層記最好成績，後續直接沿用。新招式要自行配入牌組。</li><li>Ctrl/Cmd＋S 保存到手動欄位1。任何時候都可從存檔頁下載檔案備份。</li></ul><div class="credits">這是點選場景的獨立網頁試玩版本，武學資料由現有 Godot 專案匯出；完整小說正文尚未接入。場景及同伴圖使用生成素材，字型為霞鶩文楷 TC 開源字型。詳見隨包 README。</div>`;}
    return `<div class="overlay" role="presentation"><section class="dialog paper ${modal.kind} ${wide?'wide':''}" role="dialog" aria-modal="true" aria-labelledby="dialog-title"><header class="dialoghead"><h2 id="dialog-title">${h(title)}</h2>${canClose?btn('×','close','quiet',false,'aria-label="關閉視窗"'):''}</header><div class="dialogbody">${body}</div></section></div>`;
  }
  function scheduleAI(){clearTimeout(aiTimer);if(!game?.s.battle||modal||paused)return;const b=game.s.battle,a=F.actor(b);if(b.status!=='active'||a.side==='ally'&&!a.auto)return;aiTimer=setTimeout(()=>{if(modal||paused||game.s.battle!==b)return;try{F.aiStep(b);selectedCard=0;cycleSelected=[];persist();render();}catch(e){paused=true;toast(e.message);render();}},850);}
  function render(){if(modal?.kind==='story'){const story=modal;modal=null;openStory(story);return;}const focusAction=document.activeElement?.dataset?.action;clearTimeout(aiTimer);clearTimeout(readTimer);if(!game){const held=modal;showTitle();modal=held;if(modal)app.insertAdjacentHTML('beforeend',modalMarkup());applyUX();return;}if(game.s.pending?.type==='study'&&!modal)modal={kind:'puzzle'};app.innerHTML=(game.s.battle?battleMarkup():exploration())+modalMarkup();applyUX();if(focusAction)document.querySelector(`[data-action="${CSS.escape(focusAction)}"]`)?.focus({preventScroll:true});scheduleAI();scheduleReading();}
  function afterEvent(){persist();const last=game.s.last;if(last?.id==='E13'&&last.success){openModal({kind:'outcome'});return;}const lines=last?.success?T.events[last.id].after:[last?.message||'旅程繼續。',last?.retreat?'能退一步，也是一種決定。回客舍整理，再選下一條路。':'先回客舍養傷。尚未取到的東西不會因此出現在行囊裡，但調查仍有其他途徑。'];openModal({kind:'story',title:T.events[last?.id]?.name||'行旅記錄',speaker:last?.success?T.events[last.id].speaker:'歸途',lines});}
  function loadSlot(slot){const saved=readSave(slot);if(!saved)throw new Error('此欄位沒有可讀取的完整存檔。');game=new F.Game(saved.state);restoreUI(saved.ui);modal=null;paused=!!game.s.battle;persist();render();toast(game.s.battle?'已載入旅程，自動行動先暫停。':'已載入旅程。');}
  function doAction(action){const [kind,a,b]=action.split(':');
    if(handlePresentation(kind,a,b))return;
    if(kind==='new'){const name=document.getElementById('hero-name')?.value||'陳天佑';if(readSave()&&!modal){openModal({kind:'confirm',title:'開始另一段旅程？',text:'新的旅程會取代自動存檔；手動欄位仍保留。',action:`new-confirm:${encodeURIComponent(name)}`,label:'開始新旅程'});return;}startNew(name);return;}
    if(kind==='new-confirm'){startNew(decodeURIComponent(a));return;}
    if(kind==='continue'){loadSlot('auto');return;}
    if(kind==='title-saves'){modal={kind:'saves'};const held=modal;showTitle();modal=held;app.insertAdjacentHTML('beforeend',modalMarkup());applyUX();return;}
    if(kind==='close'){closeModal();return;}
    if(kind==='puzzle-saves'){openModal({kind:'saves'});return;}
    if(kind==='help'){openModal({kind:'help'});return;}
    if(kind==='import'){document.getElementById('import-file').click();return;}
    if(kind==='load'){loadSlot(a);return;}
    if(!game)return;
    const s=game.s;
    if(kind==='save'){if(localStorage.getItem(`${KEY}:${a}`)){openModal({kind:'confirm',title:'覆寫手札？',text:'這個手動欄位已有紀錄，確認後將以目前旅程取代。其他欄位仍保留。',action:`save-confirm:${a}`,label:'覆寫此欄'});}else{persist(a,true);render();}return;}
    if(kind==='save-confirm'){persist(a,true);openModal({kind:'saves'});return;}
    if(kind==='export'){const blob=new Blob([JSON.stringify({state:s,savedAt:new Date().toISOString(),ui:{reader,history}},null,2)],{type:'application/json'});const url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download=`江湖未遠-渡口餘波-D${Math.floor(s.spent/3)+1}.json`;link.click();setTimeout(()=>URL.revokeObjectURL(url),5000);return;}
    if(kind==='title'){persist();showTitle();return;}
    if(['inventory','journal','party','study','saves','gallery','history'].includes(kind)){if(kind==='study'&&s.pending){toast('先完成目前的出行或研習。');return;}openModal({kind});return;}
    if(kind==='area'){setArea(a);return;}
    if(kind==='goto'){if(s.pending){toast('先完成目前活動。');return;}setArea(T.events[a].area);s.selected=a;openEvent(a);return;}
    if(kind==='point'){if(s.pending)return toast('請先完成目前活動。');s.selected=a;openEvent(a);return;}
    if(kind==='event'){const e=T.events[a];let extra=a==='E07'&&!s.flags.trust?'另付20文查抄費。':'';if(a==='E10'&&b==='fight')extra+='正面開戰會暴露行蹤；撤退或落敗會失去原始紀錄。';if(a==='E09'&&b==='fight')extra+='這兩名對手較強；落敗會失去本區的輪值便條。';openModal({kind:'confirm',title:e.name,text:`${e.cost?`耗費${e.cost}時段，完成時為 ${F.date(s.spent+e.cost)}。`:'交談不耗時。'}${extra}開始後可隨時存檔，閱讀和思考不額外耗時。`,action:`begin:${a}:${b}`,label:'就這樣做'});return;}
    if(kind==='begin'){modal=null;reader=null;const result=game.begin(a,b);if(result==='battle'){paused=false;selectedCard=0;target='enemy0';persist();render();}else if(result==='search'){persist();render();}else afterEvent();return;}
    if(kind==='inspect'){game.search(Number(a));persist();render();return;}
    if(kind==='finish-search'){game.finishSearch();afterEvent();return;}
    if(kind==='rest'){openModal({kind:'confirm',title:'客舍休養',text:`休養一時段，恢復傷勢。日期將到 ${F.date(s.spent+1)}，限時事件照常推進。`,action:'rest-confirm',label:'歇一歇'});return;}
    if(kind==='rest-confirm'){game.rest();modal=null;reader=null;persist();render();return;}
    if(kind==='team-tab'){teamTab=a;render();return;}
    if(kind==='team-toggle'){game.team(a,!s.team.includes(a));persist();render();return;}
    if(kind==='default-auto'){s.actors[a].auto=!s.actors[a].auto;persist();render();return;}
    if(kind==='style'){if(s.pending)throw new Error('活動途中不能改策略。');s.actors[a].style=b;persist();render();return;}
    if(kind==='inner'){game.changeInner('hero',a);persist();render();return;}
    if(kind==='send-huai'){game.sendHuai();persist();render();return;}
    if(kind==='meet'){game.meetHuai();persist();render();return;}
    if(kind==='study-start'||kind==='study-replay'){const result=game.startStudy(a,kind==='study-replay');if(result==='puzzle'){modal={kind:'puzzle'};}else {modal={kind:'story',title:'研習有得',speaker:'運功筆記',lines:[s.last.message,'新招式與內功會加入已學武學，配招仍由你決定。']};modalPage=0;}persist();render();return;}
    if(kind==='study-swap'){game.moveStudy(Number(a));persist();render();return;}
    if(kind==='study-submit'||kind==='study-cancel'){const message=kind==='study-submit'?game.submitStudy():game.cancelStudy();persist();openModal({kind:'story',title:'研習有得',speaker:'運功筆記',lines:[message,'下次研習同一層會自動沿用最佳成績；進入新層時，再推演新的運功順序。']});return;}
    if(kind==='outcome'){openModal({kind:'outcome'});return;}
    if(!s.battle)return;const battle=s.battle,current=F.actor(battle);
    if(kind==='control'){const unit=F.actor(battle,a);if(unit?.side==='ally'){unit.auto=!unit.auto;s.actors[a].auto=unit.auto;}persist();render();return;}
    if(kind==='pause-ai'){paused=!paused;render();return;}
    if(kind==='target'){target=a;render();return;}
    if(kind==='card'){selectedCard=Number(a);render();return;}
    if(kind==='play'||kind==='boost'){const name=C.cards[current.hand[selectedCard]].name;F.play(battle,selectedCard,target,kind==='boost');selectedCard=0;cycleSelected=[];persist();render();if(!preferences.reduced){const el=document.createElement('div');el.className='battle-flash';el.textContent=name;document.querySelector('.battle')?.append(el);setTimeout(()=>el.remove(),650);}return;}
    if(kind==='retain'){current.retain=current.retain===selectedCard?-1:selectedCard;persist();render();return;}
    if(kind==='end-turn'){F.endTurn(battle,current.retain);selectedCard=0;persist();render();return;}
    if(kind==='cycle'){const index=Number(a);if(cycleSelected.includes(index))cycleSelected=cycleSelected.filter(i=>i!==index);else if(cycleSelected.length<battle.choice.max)cycleSelected.push(index);render();return;}
    if(kind==='cycle-done'){F.resolveChoice(battle,cycleSelected);cycleSelected=[];selectedCard=0;persist();render();return;}
    if(kind==='medicine'){F.medicine(battle,document.getElementById('heal-target').value);s.medicine=battle.medicine;persist();render();return;}
    if(kind==='ask-retreat'){openModal({kind:'confirm',title:battle.event==='E03'?'收劍認輸':'撤回安全處',text:battle.event==='E03'?'切磋仍消耗一時段，不會受傷，研習照常開放。':`保留本次活動耗時，不取得未到手的獎勵。${battle.event==='E10'?'河倉紀錄將被轉移；行蹤曝光仍會保留。':battle.event==='E09'?'伏哨會帶走輪值便條，本區無法再取得。':''}`,action:'retreat-confirm',label:'撤回去'});return;}
    if(kind==='retreat-confirm'){game.retreat();modal=null;afterEvent();return;}
    if(kind==='battle-result'){const result=game.resolveBattle();if(result==='search'){persist();render();}else afterEvent();}
  }
  function startNew(name){game=F.Game.fresh(name);reader=null;history=[];modal=null;paused=false;persist();openModal({kind:'story',title:'雨後抵達',speaker:'前情',lines:T.opening});}
  app.addEventListener('click',event=>{const el=event.target.closest('[data-action]');if(el&&!el.disabled){try{doAction(el.dataset.action);}catch(e){toast(e.message);console.error(e);}return;}});
  app.addEventListener('change',event=>{const el=event.target;if(el.dataset.deckActor){try{game.changeCard(el.dataset.deckActor,Number(el.dataset.deckSlot),el.value);persist();}catch(e){toast(e.message);}render();}});
  document.getElementById('import-file').addEventListener('change',async event=>{const file=event.target.files[0];if(!file)return;try{if(file.size>1024*1024)throw new Error('存檔檔案超過1MB，請選擇遊戲匯出的JSON。');const parsed=JSON.parse(await file.text());const next=new F.Game(parsed.state);game=next;restoreUI(parsed.ui);modal=null;paused=!!game.s.battle;persist();render();toast('已匯入旅程。');}catch(e){toast('無法匯入：'+e.message);}event.target.value='';});
  document.addEventListener('keydown',event=>{
    if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='s'){event.preventDefault();if(game&&!modal)doAction('save:1');return;}
    if(event.key==='Tab'&&modal){const nodes=[...document.querySelectorAll('[role=dialog] button:not(:disabled),[role=dialog] input,[role=dialog] select')];if(!nodes.length)return;const first=nodes[0],last=nodes.at(-1);if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus();}else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}return;}
    if(event.key==='Escape'&&modal&&!['story','puzzle'].includes(modal.kind)){closeModal();return;}
    if(event.target.matches('input,select,textarea'))return;
    if(event.key==='Enter'&&event.target.matches('[role="button"][data-action]')){doAction(event.target.dataset.action);return;}
    if(!modal&&reader&&['Enter',' '].includes(event.key)&&!event.target.matches('button,a')){event.preventDefault();advanceReading();}

  });
  document.addEventListener('visibilitychange',()=>{if(document.hidden){clearTimeout(aiTimer);clearTimeout(readTimer);if(game?.s.battle)paused=true;persist();}else if(game)render();});
  window.addEventListener('beforeunload',()=>persist());
  showTitle();
})();
