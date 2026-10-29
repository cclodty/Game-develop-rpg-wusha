"""Package the editable native GAL project; never uploads or alters the release ZIP."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/windows-dev'
LOCAL_AGENTS = '''# Native GAL local workspace

Read docs/LOCAL_WINDOWS.md, docs/CHAPTER_ONE_PLAN.md and
docs/GAL_INTERFACE_FRAMEWORK.md before changing design or presentation.
This package contains the native browser game. Historical Godot/3D references
in the design documents describe other builds, absent from this package.

- Preserve approved watercolor manga art, proportional portraits, indigo hero,
  green Huai, and the hero's gaze toward the player.
- All UI text uses the bundled LXGW WenKai TC Medium, including buttons,
  cards, numbers and tooltips. Do not replace it with system Ming fonts.
- web/ is the active interface; chapter/{catalog,content,model,card_art}.js
  are its shared source. Preserve gameplay and independent save namespaces.
- Use python tools/dev_server.py (Windows: Start-Local.cmd), port 8091.
  CSS refreshes live; other changes offer a reload button. Keep the same origin.
- After each visual step, inspect actual browser screenshots at 1440x900 and
  960x600 and operate the affected controls. Check overlapping frames, text
  clipping, illustration boundaries and focus states. Fix defects before delivery.
- For model changes run node tests/test_ferry.cjs and node tests/test_card_art.cjs.
  Preview needs Python only; Node and Playwright are optional verification tools.
- Update the chapter plan when a milestone or design decision changes.
- Preserve existing user changes. Do not push to GitHub or publish without new
  explicit authorization. No public deployment has been authorized.
'''

def package():
    paths = list((ROOT/'web').glob('*'))
    paths += [ROOT/'chapter'/n for n in ('catalog.js','content.js','model.js','card_art.js')]
    paths += [p for p in (ROOT/'chapter/assets').iterdir() if p.suffix in ('.png','.json')]
    paths += [ROOT/'assets/fonts'/n for n in ('LXGWWenKaiTC-Medium.ttf','LICENSE-WENKAI.txt','wenkai-provenance.json')]
    paths += [ROOT/'assets/generated/gal'/n for n in ('hero-player.png','huai.png','du.png','inn.png','paper.png','inventory-bag.png','inventory-items.png','investigation-clues.png','provenance.json')]
    paths += [ROOT/'assets/generated'/n for n in ('battle-back-hero.png','battle-riverside.png','characters-illustrated.png','rear-battle.provenance.json','characters-illustrated.provenance.json','card-art.provenance.json','card-art.json','card-art-hero.png','card-art-huai.png')]
    paths += [ROOT/'docs'/n for n in ('LOCAL_WINDOWS.md','CHAPTER_ONE_PLAN.md','GAL_INTERFACE_FRAMEWORK.md','NOVEL_FIRST_REGION_EVENTS.md','ART_DIRECTION.md','CHARACTER_CARD_ART.md')]
    paths += list((ROOT/'docs/images').glob('native-web-*.png'))
    paths += [ROOT/p for p in ('Start-Local.cmd','tools/dev_server.py','tools/package_windows_dev.py','tests/test_ferry.cjs','tests/test_card_art.cjs')]
    content = {p.relative_to(ROOT).as_posix():p.read_bytes() for p in paths if p.is_file()}
    content['Start-Local.cmd'] = content['Start-Local.cmd'].replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')
    content['AGENTS.md'] = LOCAL_AGENTS.encode()
    content['README.md'] = content['docs/LOCAL_WINDOWS.md']
    content['.gitignore'] = b'__pycache__/\n*.pyc\nartifacts/\nbuild/\nnode_modules/\n'
    manifest = {name:hashlib.sha256(data).hexdigest() for name,data in content.items()}
    content['source-manifest.json'] = json.dumps(manifest,ensure_ascii=False,indent=2).encode()
    OUT.mkdir(parents=True,exist_ok=True)
    archive = OUT/'jianghu-gal-windows-dev.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for name,data in content.items(): z.writestr('Jianghu-weiyuan/'+name,data)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for name,digest in manifest.items():
            assert hashlib.sha256(z.read('Jianghu-weiyuan/'+name)).hexdigest()==digest
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    report = {'archive':str(archive),'bytes':archive.stat().st_size,'files':len(content),'sha256':digest,'published':False}
    (OUT/'package.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (OUT/'SHA256SUMS.txt').write_text(f'{digest}  {archive.name}\n',encoding='ascii')
    print(json.dumps(report,indent=2))

if __name__=='__main__': package()
