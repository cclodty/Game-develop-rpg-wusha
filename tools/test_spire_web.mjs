#!/usr/bin/env node
// Real mouse/keyboard regression for spire/ at the GitHub Pages project path. No state injection.
// Usage: node tools/test_spire_web.mjs   (needs Playwright; screenshots go to artifacts/spire/)
import {createServer} from 'node:http';
import {readFile,mkdir} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {extname,join,normalize} from 'node:path';
import {fileURLToPath} from 'node:url';

const {chromium}=createRequire(import.meta.url)('playwright');
const ROOT=fileURLToPath(new URL('..',import.meta.url)),OUT=join(ROOT,'artifacts/spire'),PREFIX='/Game-develop-rpg-wusha/';
const TYPES={'.html':'text/html; charset=utf-8','.mjs':'text/javascript','.js':'text/javascript','.css':'text/css','.png':'image/png','.webp':'image/webp','.ttf':'font/ttf','.json':'application/json'};
const KEY='jianghu-combat-spire-v1',COST={strike:1,guard:1,break:1,observe:1,step:1,breath:0},PRIORITY=['breath','break','strike','step','observe','guard'];

const server=createServer(async(req,res)=>{const path=decodeURIComponent(new URL(req.url,'http://x').pathname);
  if(!path.startsWith(PREFIX)){res.writeHead(404).end();return;}
  let file=normalize(join(ROOT,path.slice(PREFIX.length)));if(file.endsWith('/'))file+='index.html';
  try{res.writeHead(200,{'content-type':TYPES[extname(file)]||'application/octet-stream'}).end(await readFile(file));}catch{res.writeHead(404).end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const URL_=`http://127.0.0.1:${server.address().port}${PREFIX}spire/`;
await mkdir(OUT,{recursive:true});

function slots(n){const gap=n>1?Math.min(176*.84,860/(n-1)):0;return Array.from({length:n},(_,i)=>{const o=i-(n-1)/2;return {x:720+o*gap,y:774+o*o*2.4};});}
const current=s=>s.actors.find(a=>a.id===s.order[s.index]);
const saved=async p=>(await p.evaluate(k=>JSON.parse(localStorage.getItem(k)||'null'),KEY))?.battle;
function foeAt(s,id){const foes=s.actors.filter(a=>a.side==='enemy'),i=foes.findIndex(a=>a.id===id),p=foes.length===1?{x:1146,y:550}:[{x:1028,y:536},{x:1268,y:562}][i];return {x:p.x,y:p.y-150};}
async function phase(p){for(const t=Date.now();Date.now()-t<30000;await p.waitForTimeout(60)){
  const r=await p.evaluate(()=>{const o=document.querySelector('#overlay');if(o.classList.contains('is-result'))return 'result';if(o.classList.contains('is-choice'))return 'choice';const e=document.querySelector('#end');return e&&!e.disabled?'turn':'';});
  if(r)return r;}throw Error('timed out waiting for a playable state');}

async function fight(p,enemy,count){
  await p.evaluate(k=>localStorage.removeItem(k),KEY);await p.reload({waitUntil:'networkidle'});
  await p.click(`[data-act="foe:${enemy}"]`);await p.click(`[data-act="count:${count}"]`);await p.click('[data-act="start"]');
  const used={drag:0,click:0,key:0,choice:0,reload:0};
  for(let step=0;step<600;step++){const ph=await phase(p);if(ph==='result')break;
    const s=await saved(p),a=current(s);
    if(ph==='choice'){if(used.choice++%2===0){await p.locator('.pickable').first().click();await p.click('[data-act="cycle"]');}else await p.click('[data-act="cycle-skip"]');continue;}
    if(step>=6&&!used.reload){used.reload++;await p.reload({waitUntil:'networkidle'});continue;}
    const foe=s.actors.filter(x=>x.side==='enemy'&&x.hp>0).sort((x,y)=>x.hp-y.hp)[0];
    let idx=-1;for(const id of PRIORITY){idx=a.hand.findIndex(c=>c===id&&COST[c]<=a.qi);if(idx>=0)break;}
    if(idx<0){await p.click('#end');continue;}
    const id=a.hand[idx],at=slots(a.hand.length)[idx],aim=id==='strike'||id==='break'?foeAt(s,foe.id):{x:690,y:340},mode=['drag','click','drag','key','drag'][step%5],before=JSON.stringify(s.metrics);
    if(mode==='key'){await p.keyboard.press(String((idx+1)%10));await p.keyboard.press('Enter');}
    else{await p.mouse.move(at.x,at.y+30);await p.mouse.down();
      if(mode==='click'){await p.mouse.up();await p.mouse.move(aim.x,aim.y,{steps:4});await p.mouse.down();await p.mouse.up();}
      else{await p.mouse.move(at.x,at.y-160,{steps:4});await p.mouse.move(aim.x,aim.y,{steps:6});await p.mouse.up();}}
    used[mode]++;await p.mouse.move(700,240);
    for(const t=Date.now();Date.now()-t<4000&&JSON.stringify((await saved(p)).metrics)===before;)await p.waitForTimeout(50);
    if(JSON.stringify((await saved(p)).metrics)===before)throw Error(`${mode} ${id} did not register`);}
  const s=await saved(p);await p.screenshot({path:join(OUT,`result-${enemy}-${count}.png`)});
  if(s.status!=='won')throw Error(`${enemy}×${count} ended ${s.status}`);
  for(const k of ['drag','click','key','reload'])if(!used[k])throw Error(`${enemy}×${count} never exercised ${k}`);
  return `${enemy}×${count} won in ${s.round} rounds (${JSON.stringify(used)})`;}

const browser=await chromium.launch(),errors=[],checks=[];
try{
  for(const [width,height] of [[1440,900],[960,600]]){const p=await browser.newPage({viewport:{width,height}});
    p.on('pageerror',e=>errors.push(e.message));p.on('console',m=>m.type()==='error'&&errors.push(m.text()));p.on('response',r=>r.status()>=400&&errors.push(`${r.status()} ${r.url()}`));
    await p.goto(width===1440?`${URL_}?fast`:URL_,{waitUntil:'networkidle'});await p.screenshot({path:join(OUT,`setup-${width}.png`)});
    if(width===1440)for(const [enemy,count] of [['flurry',1],['armored',1],['charging',1],['counter',1],['counter',2],['flurry',2]])checks.push(await fight(p,enemy,count));
    else{await p.evaluate(k=>localStorage.removeItem(k),KEY);await p.reload({waitUntil:'networkidle'});await p.check('input[data-act="auto"]');await p.click('[data-act="start"]');await phase(p);
      const s=await saved(p);if(current(s).id!=='hero'||!s.metrics.aiActions)throw Error('auto companions did not act before the hero');
      await p.screenshot({path:join(OUT,'combat-960.png')});checks.push(`960×600 with auto companions reached 陳天佑 after ${s.metrics.aiActions} AI actions`);}
    await p.close();}
}finally{await browser.close();server.close();}
for(const c of checks)console.log('ok',c);
if(errors.length){console.error(errors.join('\n'));process.exit(1);}
console.log(`no page errors; screenshots in ${OUT}`);
