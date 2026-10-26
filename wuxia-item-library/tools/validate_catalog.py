"""Validate the delivered design catalog and any real image references."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def validate():
    payload = json.loads((ROOT / 'catalog.json').read_text())
    items = payload if isinstance(payload, list) else payload['items']
    assert len(items) == 368, len(items)
    assert len({x['id'] for x in items}) == 368
    assert len({x['name'] for x in items}) == 368, '重複物品名稱'
    assert sum(x['collection'] == 'base' for x in items) == 240
    assert sum(x['collection'] == 'sect' for x in items) == 128
    sects = {'shaolin','wudang','emei','huashan','kunlun','kongtong','gaibang','tangmen'}
    assert {x['sect_id'] for x in items if x['collection'] == 'sect'} == sects
    for sect in sects:
        assert sum(x['sect_id'] == sect for x in items) == 16
    atlases = {f'B{i:02}' for i in range(1, 16)} | {f'S{i:02}' for i in range(1, 9)}
    assert {x['atlas_id'] for x in items} == atlases
    for atlas in atlases:
        assert sorted(x['cell_index'] for x in items if x['atlas_id'] == atlas) == list(range(16))
    for item in items:
        for field in ['name','description','use','limitation','acquisition','appearance','art_prompt']:
            assert isinstance(item[field], str) and item[field].strip(), (item['id'], field)
        assert item['implementation_status'] == 'design_only'
        if item['collection'] == 'sect':
            assert item.get('name_origin') in {'existing_martial_arts', 'existing_named_item', 'generic_traditional_item'}, item['id']
            assert item.get('reference_note'), item['id']
            assert not item.get('needs_art_revision'), item['id']
            if item['name_origin'].startswith('existing_'):
                assert item.get('reference_sources'), (item['id'], 'missing name source')
            for source in item.get('reference_sources', []):
                assert source.get('title') and source.get('url', '').startswith('https://'), item['id']
        if item['asset_ref']:
            ref = item['asset_ref']
            path = ref if isinstance(ref, str) else ref.get('image_path', ref.get('path'))
            assert path and (ROOT / path).is_file(), (item['id'], ref)
    mapping = json.loads((ROOT / 'canonical-name-mapping.json').read_text())['items']
    current = {x['id']: x for x in items if x['collection'] == 'sect'}
    assert len(mapping) == 128 and {x['id'] for x in mapping} == set(current)
    for entry in mapping:
        assert entry['new_name'] == current[entry['id']]['name'], entry['id']
        assert entry['reference_sources'] == current[entry['id']]['reference_sources'], entry['id']
    return items


if __name__ == '__main__':
    items = validate()
    print(json.dumps({'items':len(items),'base':240,'sect':128,'sect_count':8,
        'atlas_count':23,'items_with_assets':sum(bool(i['asset_ref']) for i in items),
        'design_only':True,'unique_ids_and_names':True}, ensure_ascii=False, indent=2))
