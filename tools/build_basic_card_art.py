"""Compress accepted single-card PNGs; retain originals and verify dimensions."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'art-source/basic-v1'

def build():
    source = json.loads((SOURCES / 'sources.json').read_text())
    records = []
    for item in source['images']:
        assert item.get('reviewed') is True, f"Review the full-size original before publishing: {item}"
        actor, card = item['actor'], item['card']
        original = SOURCES / actor / f'{card}.png'
        output = ROOT / 'assets/cards/basic' / actor / f'{card}.webp'
        output.parent.mkdir(parents=True, exist_ok=True)
        with Image.open(original) as image:
            assert image.size == (1536, 1024), (original, image.size)
            image.convert('RGB').resize((768, 512), Image.Resampling.LANCZOS).save(output, 'WEBP', quality=84, method=6)
        records.append({**item, 'original':str(original.relative_to(ROOT)), 'url':str(output.relative_to(ROOT)),
            'source_sha256':hashlib.sha256(original.read_bytes()).hexdigest(),
            'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
            'source_size':[1536,1024], 'size':[768,512], 'bytes':output.stat().st_size})
    manifest={'version':1,'generator':'image_gen','method':'one image per actor/technique; no atlas or slicing',
        'images':records,'total_web_bytes':sum(x['bytes'] for x in records)}
    target=ROOT/'assets/cards/basic/manifest.json'
    target.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'cards':len(records),'web_bytes':manifest['total_web_bytes']},indent=2))

if __name__=='__main__':build()
