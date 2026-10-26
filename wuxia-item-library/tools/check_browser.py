"""Bounded browser smoke: all data interactions, one representative real PNG atlas."""
import base64
import json
import time
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / 'browser-validation.json'
report = {'status': 'running', 'items': 368, 'decoded_atlases': 0,
          'image_scope': 'Tangmen S08 only: all 16 measured sprite regions. Other images suppressed in memory for this bounded smoke.',
          'tested': [], 'loading': 'In-memory HTML with one local PNG supplied as a blob URL; no outbound traffic. Delivered HTML is unchanged and uses relative image paths.'}

def progress(name):
    print(name, flush=True)
    report['last_step'] = name
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2))

try:
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True,
                                   args=['--no-sandbox', '--disable-dev-shm-usage'])
        page = browser.new_page(viewport={'width':1440, 'height':1100}, device_scale_factor=1)
        page.set_default_timeout(10000)
        errors = []
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.route('**/*', lambda route: route.abort())
        progress('load in-memory catalogue')
        page.set_content((ROOT / 'index.html').read_text(), wait_until='domcontentloaded', timeout=15000)
        catalog = json.loads((ROOT / 'catalog.json').read_text())
        assert page.locator('.item').count() == 368
        # Keep every item for interaction checks, suppress bulk image decoding only in memory.
        page.evaluate('''() => {for(const item of data.items) if(item.atlas_id !== 'S08') {
          item.asset_ref=null; item.art_status='pending';} render();}''')
        progress('all eight sect filters and details')
        for sect in catalog['sects']:
            page.locator('#sect').select_option(sect['id'])
            assert page.locator('.item').count() == 16
        page.locator('#category').select_option('inner_manual')
        assert page.locator('.item').count() == 3
        page.locator('.open-item').first.click()
        assert page.locator('#detail').is_visible()
        assert page.locator('#detail-fields dd').count() == 4
        page.keyboard.press('Escape')
        assert not page.locator('#detail').is_visible()
        page.locator('#reset').click()
        page.locator('#search').fill('TM016')
        assert page.locator('.item').count() == 1
        page.locator('#search').fill('NOT-AN-ITEM-XYZ')
        assert page.locator('.item').count() == 0
        page.locator('#reset').click()
        page.locator('#sect').select_option('tangmen')
        report['tested'] += ['368 item rows', '8 sect filters', 'inner manual filter', 'detail modal and Escape', 'ID search', 'empty state', 'reset']
        progress('decode one Tangmen atlas with an 8-second bound')
        atlas = catalog['atlases']['S08']
        png_base64 = base64.b64encode((ROOT / atlas['image_path']).read_bytes()).decode()
        decoded = page.evaluate('''async encoded => {
          const bytes=Uint8Array.from(atob(encoded),c=>c.charCodeAt(0));
          const url=URL.createObjectURL(new Blob([bytes],{type:'image/png'}));
          const result=await Promise.race([
            new Promise(resolve=>{const img=new Image();img.onload=()=>resolve({ok:true,width:img.naturalWidth,height:img.naturalHeight});img.onerror=()=>resolve({ok:false,error:'Image error'});img.src=url;}),
            new Promise(resolve=>setTimeout(()=>resolve({ok:false,error:'Image decode timeout'}),8000))
          ]);
          for(const item of data.items) if(item.atlas_id==='S08') item.asset_ref.image_path=url;
          render();return result;
        }''', png_base64)
        report['atlas_decode'] = decoded
        assert decoded.get('ok'), decoded
        assert (decoded['width'],decoded['height']) == (atlas['width'],atlas['height'])
        report['decoded_atlases'] = 1
        assert page.locator('#grid .sprite-window').count() == 16
        bounds = page.locator('#grid .sprite-window').evaluate_all('(els)=>els.map(e=>({w:e.clientWidth,h:e.clientHeight,bg:getComputedStyle(e).backgroundImage,size:getComputedStyle(e).backgroundSize}))')
        assert all(b['w'] > 30 and b['h'] > 30 and 'blob:' in b['bg'] for b in bounds)
        for item, bound in zip([i for i in catalog['items'] if i['atlas_id']=='S08'], bounds):
            region = item['asset_ref']['region']
            assert abs(bound['w']/bound['h'] - region['width']/region['height']) < .03
        report['tested'] += ['S08 PNG decoded', '16 measured sprite region aspect ratios and CSS image sources']
        progress('save actual rendered Tangmen preview')
        page.screenshot(path=str(ROOT/'catalog-preview.png'), full_page=True, timeout=10000)
        page.set_viewport_size({'width':390,'height':844})
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
        assert not errors, errors
        report['tested'] += ['mobile overflow', 'JavaScript errors']
        report['status'] = 'passed'
        report['preview'] = 'catalog-preview.png'
        progress('passed')
        browser.close()
except Exception as error:
    report['status'] = 'failed'
    report['error'] = str(error)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    raise
print(json.dumps(report, ensure_ascii=False), flush=True)
