#!/usr/bin/env python3
"""Real mouse/keyboard regression at the GitHub Pages project path. No state injection."""
import json
from functools import partial
from http.server import ThreadingHTTPServer
from pathlib import Path
from threading import Thread
import sys
import time

from playwright.sync_api import sync_playwright
from test_web_hosting import ProjectHandler

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/basic-battle/browser'
READ='JSON.parse(localStorage.getItem("jianghu-combat-lab-v1"))'
COST={'strike':1,'guard':1,'break':1,'observe':1,'step':1,'breath':0}

def saved(page):return page.evaluate(READ)
def actor(s):return next(a for a in s['actors'] if a['id']==s['order'][s['index']])
def click(page,action):page.locator(f'[data-action="{action}"]').click();page.wait_for_timeout(30)
def wait_saved(page,predicate,label):
    deadline=time.monotonic()+15
    while time.monotonic()<deadline:
        value=saved(page)
        if value and predicate(value):return value
        page.wait_for_timeout(60)
    page.screenshot(path=str(OUT/'failure.png'))
    raise AssertionError(label)
def capture(page,name):page.screenshot(path=str(OUT/(name+'.png')))

def victory(page,checks,exercise=False):
    cycled=False;used=set()
    for _ in range(450):
        env=saved(page);s=env['battle']
        if s['status']!='active':
            assert s['status']=='won',s['status']
            capture(page,f'result-{s["config"]["enemy"]}')
            checks.append(f'Legal mouse-input victory against {s["config"]["enemy"]}')
            return used,cycled
        a=actor(s)
        if a['side']=='enemy':page.wait_for_timeout(700);continue
        if s['choice']:
            if a['hand']:
                click(page,'card:0')
                if exercise and not cycled:
                    click(page,'pause')
                    before=saved(page);capture(page,'cycle-selected')
                    page.reload(wait_until='networkidle')
                    assert saved(page)['battle']==before['battle']
                    assert saved(page)['view']['cycleSelection']==[0]
                    capture(page,'cycle-resumed')
                    click(page,'saves')
                    with page.expect_download() as downloaded:click(page,'export')
                    backup=OUT/'cycle-export.json';downloaded.value.save_as(backup)
                    click(page,'close');click(page,'cycle');after=saved(page)
                    click(page,'saves');click(page,'import')
                    page.locator('#import-save').set_input_files(str(backup))
                    wait_saved(page,lambda d:d['battle']==before['battle'],'import exact paid cycle')
                    click(page,'cycle')
                    assert saved(page)['battle']==after['battle'],'import must resolve once with identical RNG'
                    stable=saved(page);broken=OUT/'invalid-import.json';broken.write_text('{broken')
                    click(page,'saves');click(page,'import')
                    page.locator('#import-save').set_input_files(str(broken))
                    page.wait_for_function('document.querySelector("#toast").textContent.includes("匯入失敗")')
                    assert saved(page)==stable,'invalid import preserves existing save'
                    click(page,'close')
                    checks.append('Invalid JSON upload preserves the previous lab save')
                    click(page,'pause');cycled=True
                    checks.append('Cycle selection survives reload and exported/imported real backup; identical single resolution')
                else:click(page,'cycle')
            else:click(page,'cycle-skip')
            continue
        hand=a['hand'];qi=a['qi'];enemies=[e for e in s['actors'] if e['side']=='enemy' and e['hp']>0]
        target=min(enemies,key=lambda e:e['hp']);click(page,'target:'+target['id'])
        incoming=sum(e['intent']['damage']*e['intent']['hits'] for e in enemies if e['intent']['target']==a['id'])
        index=None
        if exercise and not cycled and 'step' in hand and qi>=1:index=hand.index('step')
        elif 'breath' in hand:index=hand.index('breath')
        elif incoming>a['block'] and qi>=1:
            index=next((i for i,c in enumerate(hand) if c in ('guard','step')),None)
        if index is None and qi>=1:
            priority=('break','strike') if target['block'] else ('strike','break')
            index=next((hand.index(c) for c in priority if c in hand),None)
        if index is None and qi>=2 and 'observe' in hand:index=hand.index('observe')
        if index is None and qi>=1 and 'step' in hand:index=hand.index('step')
        if index is None:click(page,'end');continue
        used.add(hand[index]);before=saved(page)['battle'];click(page,'card:'+str(index))
        assert saved(page)['battle']==before,'selection never casts a card'
        click(page,'play')
    raise AssertionError('browser battle did not terminate')

def main():
    OUT.mkdir(parents=True,exist_ok=True);checks=[];errors=[];bad=[];requests=[]
    server=ThreadingHTTPServer(('127.0.0.1',0),partial(ProjectHandler,directory=str(ROOT)))
    Thread(target=server.serve_forever,daemon=True).start()
    base=f'http://127.0.0.1:{server.server_port}/Game-develop-rpg-wusha/'
    try:
        with sync_playwright() as p:
            browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox','--disable-dev-shm-usage'])
            for width,height in [(1440,900),(960,600)]:
                ctx=browser.new_context(viewport={'width':width,'height':height},accept_downloads=True)
                page=ctx.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
                page.on('console',lambda m:errors.append(m.text) if m.type=='error' else None)
                page.on('response',lambda r:bad.append(r.url) if r.status>=400 else None)
                page.on('request',lambda r:requests.append(r.url))
                page.goto(base,wait_until='networkidle');capture(page,f'chapter-entry-{width}')
                page.locator('.battle-entry').click();page.wait_for_url('**/battle/')
                page.locator('#seed').wait_for();page.evaluate('document.fonts.ready')
                capture(page,f'preparation-{width}')
                box=page.locator('[data-action="start"]').bounding_box();assert box and box['y']+box['height']<=height-2,'start fits viewport'
                for owner in ['hero','huai','du']:
                    click(page,'tab:'+owner)
                    page.locator('.deck-card').last.scroll_into_view_if_needed()
                    page.wait_for_timeout(120)
                    assert page.locator('.deck-card img').evaluate_all('(els)=>els.every(e=>e.complete&&e.naturalWidth===768)')
                    capture(page,f'cards-{owner}-{width}')
                click(page,'tab:hero');page.locator('#inner').select_option('shouzhong')
                page.locator('[data-item="wrist"]').check();page.locator('[data-item="coat"]').check()
                assert '氣血 74' in page.locator('.stats').inner_text()
                assert '力道 +1' in page.locator('.stats').inner_text()
                click(page,'remove:strike')
                assert '15–25' in page.locator('.deck-validation').inner_text()
                click(page,'start');assert not saved(page).get('battle'),'invalid fourteen blocked'
                click(page,'add:strike');assert page.locator('[data-action="add:strike"]').is_disabled()
                checks.append(f'{width}: 18 distinct assets, loadout bonuses, family cap and 14-card rejection via actual controls')
                # Establish a real chapter save; only the chapter UI writes its own namespace.
                page.goto(base+'web/',wait_until='networkidle');page.locator('#hero-name').fill('原旅程')
                click(page,'new');page.locator('.vn-text').wait_for()
                page.goto(base+'battle/',wait_until='networkidle')
                legacy=page.evaluate('Object.fromEntries(Object.entries(localStorage).filter(([k])=>k.startsWith("jianghu-gal-web")))')
                for id in ['huai','du']:page.locator(f'[data-auto="{id}"]').uncheck()
                page.locator('#seed').fill('42');page.locator('#seed').press('Tab')
                click(page,'start');capture(page,f'combat-{width}')
                if width==1440:
                    used,cycled=victory(page,checks,True)
                    assert cycled,'actual step choice covered'
                    for enemy in ['armored','charging','counter']:
                        click(page,'reset-confirm');page.locator('#enemy').select_option(enemy);click(page,'start')
                        capture(page,'intent-'+enemy);victory(page,checks)
                    # Retry has the same seed and first hand, with fresh resources.
                    click(page,'retry');initial=saved(page)['battle'];click(page,'card:0');capture(page,'selected-card')
                    click(page,'rules');capture(page,'rules');click(page,'close')
                    click(page,'control:huai');assert next(a for a in saved(page)['battle']['actors'] if a['id']=='huai')['auto']
                    wait_saved(page,lambda d:d['battle']['metrics']['aiActions']>0,'automatic companion actually acts')
                    click(page,'pause');assert saved(page)['view']['paused']
                    click(page,'control:huai')
                    checks.append('Automatic companion performs a legal scheduled action before pause and manual takeover')
                    click(page,'retreat');click(page,'retreat-confirm');click(page,'retry')
                    assert saved(page)['battle']==initial,'same-config retry reproduces initial piles and intentions'
                    checks.append('Four intents, rules, takeover, pause, retreat and deterministic retry pass')
                else:
                    click(page,'card:0');before=saved(page);capture(page,'selected-small')
                    page.reload(wait_until='networkidle');assert saved(page)==before
                    click(page,'retreat');click(page,'retreat-confirm');capture(page,'result-small')
                    checks.append('960: selected card, snapshot, retreat and result layout pass')
                assert page.evaluate('Object.fromEntries(Object.entries(localStorage).filter(([k])=>k.startsWith("jianghu-gal-web")))')==legacy
                checks.append(f'{width}: formal chapter save remains byte-for-byte unchanged')
                ctx.close()
            browser.close()
        assert not bad,bad;assert not errors,errors
        assert not any('/art-source/' in u for u in requests),'raw production PNGs are not runtime assets'
        assert len({u.split('/assets/cards/basic/')[1] for u in requests if '/assets/cards/basic/' in u and u.endswith('.webp')})==18
        report={'checks':checks,'errors':errors,'failed_resources':bad,'state_injection':False,'runtime_card_images':18,'raw_card_sources_requested':False}
        (OUT/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        print(f'BASIC BATTLE WEB COMPLETE: {len(checks)} flow groups; zero resource or browser errors')
    finally:server.shutdown();server.server_close()

if __name__=='__main__':main()
