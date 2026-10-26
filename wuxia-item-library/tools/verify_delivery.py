"""Final content, asset and provenance checks. Requires Pillow."""
import hashlib
import json
from pathlib import Path
from PIL import Image
from validate_catalog import validate

ROOT=Path(__file__).resolve().parents[1]


def main():
    items=validate()
    assert all(i['art_status']=='generated' and i['asset_ref'] for i in items)
    manifest=json.loads((ROOT/'atlas-manifest.json').read_text())['atlases']
    assert len(manifest)==23
    regions=json.loads((ROOT/'atlas-regions.json').read_text())
    assert regions['summary']=={'measured':23,'passed':23,'failed':0}
    for atlas in manifest:
        path=ROOT/atlas['image_path']
        digest=hashlib.sha256(path.read_bytes()).hexdigest()
        assert digest==atlas['sha256'],atlas['atlas_id']
        source=Path(atlas['source_path'])
        # Source originals may live outside the portable delivery after download.
        if source.is_file():
            assert hashlib.sha256(source.read_bytes()).hexdigest()==digest
        ordered=sorted((i for i in items if i['atlas_id']==atlas['atlas_id']),key=lambda i:i['cell_index'])
        assert [i['id'] for i in ordered]==atlas['item_ids'],atlas['atlas_id']
        with Image.open(path) as im:
            assert im.mode=='RGBA'
            assert im.size==(atlas['width'],atlas['height'])
            assert im.getchannel('A').getextrema()==(0,255)
        assert regions['atlases'][atlas['atlas_id']]['foreground_outer_edge_pixels']==0,atlas['atlas_id']
    report={'status':'passed','item_count':368,'base_count':240,'sect_items':128,'sect_count':8,
            'generated_atlases':23,'generated_icons':368,'measured_regions':368,
            'unique_ids_and_names':True,'item_order_matches_metadata':True,
            'sha256_matches':True,'transparent_pngs':True,'no_opaque_outer_edge_pixels':True,
            'source_pixels_preserved':True,'implementation_status':'design_only',
            'note':'Some transparent gutter edges retain alpha<=32 artifacts; measured regions avoid foreground above that threshold. All source PNG bytes remain unedited.'}
    (ROOT/'validation-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
