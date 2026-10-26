"""Bounded browser smoke: all data interactions, one representative real PNG atlas."""
import base64
import json
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
        assert page.locator('#detail-fields dd').count() >= 4
        page.keyboard.press('Escape')
        assert not page.locator('#detail').is_visible()
        page.locator('#reset').click()
        page.locator('#search').fill('TM016')
        assert page.locator('.item').count() == 1
        page.locator('#search').fill('NOT-AN-ITEM-XYZ')
        assert page.locator('.item').count() == 0
        page.locator('#reset').click()
        progress('classic martial names and reference links')
        # Use recognisable name fragments so editions such as 太極劍 / 太極劍法
        # still exercise the actual delivered names, without silently testing old originals.
        familiar_names = ['易筋經', '太極', '金頂綿掌', '紫霞', '兩儀',
                          '七傷拳', '降龍十八掌', '暴雨梨花', '羅漢拳', '梯雲縱']
        name_checks, checked_ids = [], set()
        for query in familiar_names:
            item = next((i for i in catalog['items'] if i['collection'] == 'sect'
                         and query in i['name'] and i['id'] not in checked_ids), None)
            if item is None:
                continue
            assert item.get('name_origin'), f'{item["id"]}: missing name_origin'
            assert item.get('reference_note'), f'{item["id"]}: missing reference_note'
            sources = [s for s in item.get('reference_sources', [])
                       if isinstance(s, dict) and str(s.get('url', '')).startswith('https://')]
            assert sources, f'{item["id"]}: no HTTPS reference sources'
            page.locator('#search').fill(query)
            assert page.locator('.item').count() >= 1
            page.get_by_role('button', name=f'查看 {item["name"]} 詳情', exact=True).click()
            assert page.locator('#detail-name').inner_text() == item['name']
            assert item['reference_note'] in page.locator('#detail-fields').inner_text()
            links = page.locator('#detail-fields a').evaluate_all('''els => els.map(e => ({
              text:e.textContent, href:e.getAttribute('href'), target:e.target, rel:e.rel
            }))''')
            assert len(links) == len(sources), f'{item["id"]}: incorrect source link count'
            for source, link in zip(sources, links):
                assert link['href'] == source['url'], (item['id'], source, link)
                assert link['text'] == source['title'], (item['id'], source, link)
                assert link['target'] == '_blank'
                assert {'noopener', 'noreferrer'} <= set(link['rel'].split())
            page.locator('#close-detail').click()
            checked_ids.add(item['id'])
            name_checks.append({'id':item['id'], 'name':item['name'], 'query':query,
                                'source_links_verified':len(links)})
        assert len(name_checks) >= 4, f'Expected at least four recognisable martial names, found {name_checks}'
        report['classic_name_checks'] = name_checks
        report['tested'] += ['classic martial name searches', 'name provenance notes',
                             'reference link title/URL/target/rel attributes (links not fetched)']
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
