"""Build an allowlisted offline trial package; never include player saves."""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CHAPTER = ROOT / 'chapter'
OUT = ROOT / 'artifacts/ferry-release'
VALIDATION = ROOT / 'artifacts/ferry-validation'
FILES = ['index.html','style.css','app.js','model.js','content.js','catalog.js','README.md','Play-Windows.cmd']

def package():
    OUT.mkdir(parents=True,exist_ok=True)
    files=[CHAPTER / name for name in FILES]+sorted((CHAPTER/'assets').glob('*'))
    assert all(p.is_file() for p in files)
    report=json.loads((VALIDATION/'browser-report.json').read_text())
    assert report['passed'] and not report['browser_errors']
    assert 'fail 0' in (VALIDATION/'model-tests.txt').read_text()
    archive=OUT/'jianghu-ferry-trial.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for file in files:
            z.write(file,Path('jianghu-ferry')/file.relative_to(CHAPTER))
        for name in ['browser-report.json','model-tests.txt']:
            z.write(VALIDATION/name,Path('jianghu-ferry/validation')/name)
        for name in ['NOVEL_FIRST_REGION_EVENTS.md','GAME_DESIGN.md','CARD_DESIGN.md']:
            z.write(ROOT/'docs'/name,Path('jianghu-ferry/design')/name)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        assert not any('browser-export' in name or name.endswith('save.json') for name in z.namelist())
        for name in FILES:
            assert z.read('jianghu-ferry/'+name)==(CHAPTER/name).read_bytes()
    digest=hashlib.sha256(archive.read_bytes()).hexdigest()
    (OUT/'SHA256SUMS.txt').write_text(f'{digest}  {archive.name}\n')
    (OUT/'release.json').write_text(json.dumps({'artifact':archive.name,'bytes':archive.stat().st_size,'sha256':digest,'source_files':len(files),'offline':True,'browser_scenarios':len(report['scenarios'])},indent=2))
    print(json.dumps({'path':str(archive),'bytes':archive.stat().st_size,'sha256':digest},indent=2))

if __name__=='__main__':package()
