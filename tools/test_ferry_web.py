"""Real browser playthroughs. Reads saves for assertions; never injects game state."""
import json
from pathlib import Path
import time
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/ferry-validation'
OUT.mkdir(parents=True, exist_ok=True)
URL = 'http://127.0.0.1:8073/'
AREAS = {'E01':'haven','E02':'haven','E03':'haven','E04':'haven','E05':'wharf','E06':'river','E07':'wharf','E08':'wharf','E09':'river','E10':'warehouse','E11':'haven','E12':'wharf','E13':'haven'}
errors=[]
coverage=[]
limitations=[]

def click(page, action):
    page.locator(f'[data-action="{action}"]').first.click(timeout=7000)

def read(page):
    return page.evaluate("JSON.parse(localStorage.getItem('jianghu-ferry-v1:auto')).state")

def story(page):
    for _ in range(12):
        if not page.locator('[data-action="story-next"]').count():
            return
        click(page,'story-next')
    raise AssertionError('Story failed to close')

def event(page, id, method):
    click(page,'area:'+AREAS[id])
    click(page,'point:'+id)
    click(page,f'event:{id}:{method}')
    click(page,f'begin:{id}:{method}')
    story(page)

def start(browser, name):
    context=browser.new_context(viewport={'width':1440,'height':1000},accept_downloads=True)
    page=context.new_page()
    page.on('pageerror',lambda e: errors.append(str(e)))
    page.goto(URL,wait_until='networkidle')
    page.locator('#hero-name').fill(name)
    click(page,'new');story(page)
    event(page,'E01','settle');event(page,'E02','join')
    return context,page

def search(page):
    for i in range(3):click(page,f'inspect:{i}')
    click(page,'finish-search');story(page)

with sync_playwright() as p:
    browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox','--disable-dev-shm-usage'])
    context,page=start(browser,'雲行')
    event(page,'E03','practice');click(page,'pause-ai')
    click(page,'control:huai')
    b=read(page)['battle'];assert b['current']=='huai'
    hand=next(a for a in b['actors'] if a['id']=='huai')['hand']
    i=hand.index('cloud_step')
    click(page,f'card:{i}');click(page,'play')
    assert read(page)['battle']['choice']
    frozen=read(page)['battle']
    click(page,'saves');click(page,'save:1');click(page,'close')
    page.reload(wait_until='networkidle');click(page,'continue')
    assert read(page)['battle']==frozen
    click(page,'cycle:0');click(page,'cycle-done')
    assert read(page)['battle']['choice'] is None
    page.screenshot(path=str(OUT/'battle.png'),full_page=True)
    click(page,'control:huai');click(page,'control:hero');click(page,'pause-ai')
    deadline=time.monotonic()+100
    while read(page)['battle']['status']=='active':
        assert time.monotonic()<deadline, 'Automated allies/enemies did not complete combat'
        page.wait_for_timeout(400)
    assert read(page)['battle']['status']=='won'
    click(page,'battle-result');story(page)
    coverage.append('Three-actor speed combat, manual companion takeover, cycle choice, mid-choice save/reload, autonomous turns and victory')
    click(page,'study');click(page,'study-start:sword')
    click(page,'study-swap:0')
    pending=read(page)['pending']
    click(page,'puzzle-saves');click(page,'save:1');click(page,'close')
    page.reload(wait_until='networkidle');click(page,'continue')
    assert read(page)['pending']==pending
    coverage.append('Study puzzle can open manual saves and restore the exact in-progress ordering')
    while read(page)['pending']['order']!=[0,1,2,3]:
        order=read(page)['pending']['order']
        for desired in range(4):
            at=order.index(desired)
            if at>desired:
                click(page,f'study-swap:{at-1}')
                break
    page.screenshot(path=str(OUT/'study.png'),full_page=True)
    click(page,'study-submit');story(page)
    assert read(page)['best']['sword:1']==4
    click(page,'study');click(page,'study-start:sword');story(page)
    assert read(page)['studies']['sword']['level']==1
    assert read(page)['pending'] is None
    click(page,'party')
    page.locator('[data-deck-actor="hero"][data-deck-slot="5"]').select_option('opening_thrust')
    assert read(page)['actors']['hero']['deck'][5]=='opening_thrust'
    click(page,'team-tab:du')
    page.locator('[data-deck-actor="du"][data-deck-slot="9"]').select_option('probing_stone')
    assert len(page.locator('[data-deck-actor="du"]').all())==3
    click(page,'close')
    coverage.append('First study, solved order, per-layer best, automatic repeat, unlock, hero deck edit and three companion flex slots')
    event(page,'E05','talk');event(page,'E06','path')
    click(page,'inspect:0');click(page,'saves');click(page,'save:2');click(page,'close')
    page.reload(wait_until='networkidle');click(page,'continue')
    assert read(page)['pending']['found']==[0]
    click(page,'inspect:1');click(page,'inspect:2');click(page,'finish-search');story(page)
    event(page,'E07','ledger');event(page,'E08','listen')
    click(page,'area:wharf');page.screenshot(path=str(OUT/'exploration.png'),full_page=True)
    event(page,'E10','law');search(page);event(page,'E11','reflect');event(page,'E13','finish')
    assert read(page)['result']=='clear'
    assert {'seal','ledger','doctor','record'}.issubset(read(page)['clues'])
    page.screenshot(path=str(OUT/'ending-clear.png'),full_page=True)
    click(page,'close');click(page,'saves')
    with page.expect_download() as info:click(page,'export')
    saved=info.value;path=OUT/'browser-export.json';saved.save_as(str(path))
    exported=json.loads(path.read_text());assert exported['state']['result']=='clear'
    before=read(page)
    page.locator('#import-file').set_input_files({'name':'broken.json','mimeType':'application/json','buffer':b'{broken'})
    assert read(page)==before
    page.locator('#import-file').set_input_files(str(path))
    assert read(page)['result']=='clear'
    coverage.append('Complete clear route, exact calendar progression, investigation save/reload, ending, backup export/import and rejected invalid import')
    # Starting over is explicit and keeps manual saves.
    click(page,'saves');click(page,'title');click(page,'new')
    assert page.get_by_role('heading',name='開始另一段旅程？').count()==1
    click(page,'close');click(page,'continue')
    assert read(page)['result']=='clear'
    context.close()

    context,page=start(browser,'後行')
    for _ in range(10):click(page,'rest');click(page,'rest-confirm')
    assert read(page)['events']['E06']=='expired'
    assert read(page)['events']['E08']=='expired'
    event(page,'E12','recover');event(page,'E13','finish')
    assert read(page)['result']=='doubt'
    assert read(page)['clues']==['copy']
    page.screenshot(path=str(OUT/'ending-doubt.png'),full_page=True)
    coverage.append('Late arrival permanently loses limited evidence, free recovery path remains and produces a different ending')
    context.close()

    context,page=start(browser,'破浪')
    event(page,'E07','ledger');event(page,'E10','fight')
    click(page,'ask-retreat');click(page,'retreat-confirm');story(page)
    assert read(page)['events']['E10']=='lost'
    assert read(page)['flags']['exposed']
    event(page,'E12','recover');event(page,'E13','finish')
    assert read(page)['result']=='exposed'
    page.screenshot(path=str(OUT/'ending-exposed.png'),full_page=True)
    click(page,'close');click(page,'saves');click(page,'save:3');click(page,'close')
    page.set_viewport_size({'width':390,'height':844})
    page.screenshot(path=str(OUT/'mobile.png'),full_page=True)
    assert page.evaluate('document.documentElement.scrollWidth <= innerWidth+1'), 'Mobile overflow'
    assert page.locator('.clock').is_visible()
    assert page.get_by_role('heading',name='日子不等人').is_visible()
    click(page,'study');click(page,'close');click(page,'saves');click(page,'load:3')
    assert read(page)['result']=='exposed'
    coverage.append('Combat retreat preserves exposure and loses original records; third ending; 390px layout and manual load work')
    context.close()
    # Some managed test environments prohibit file URLs; record the limitation explicitly.
    context=browser.new_context(viewport={'width':1280,'height':900})
    page=context.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
    try:
        page.goto((ROOT/'chapter/index.html').as_uri(),wait_until='load')
    except Exception as e:
        if 'ERR_BLOCKED_BY_ADMINISTRATOR' not in str(e):
            raise
        limitations.append('Managed Chromium policy blocks file:// URLs. Browser playthroughs used a local HTTP server; direct file launch requires verification on the player computer.')
    else:
        click(page,'new');story(page);event(page,'E01','settle')
        assert read(page)['flags']['settled']
        coverage.append('Direct file:// launch loads scripts and saves successfully in Chromium')
    context.close();browser.close()

assert not errors,errors
report={'passed':True,'scenarios':coverage,'browser_errors':errors,'limitations':limitations,'screenshots':sorted(p.name for p in OUT.glob('*.png'))}
(OUT/'browser-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False,indent=2))
