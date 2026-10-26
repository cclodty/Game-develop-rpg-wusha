#!/usr/bin/env python3
"""Build a portable, offline catalogue from the authored JSON source files."""
from __future__ import annotations

import csv
import hashlib
import json
import struct
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ITEM_FILES = [
    'base_01_05.json', 'base_06_10.json', 'base_11_15.json',
    'sects_01_04.json', 'sects_05_08.json',
]
PROFILE_FILES = ['sect_profiles_01_04.json', 'sect_profiles_05_08.json']
FIELDS = [
    'id', 'name', 'collection', 'category_id', 'category_name', 'sect_id',
    'tier', 'description', 'use', 'limitation', 'acquisition', 'appearance',
    'art_prompt', 'atlas_id', 'cell_index', 'art_status', 'asset_ref',
    'implementation_status',
]
REFERENCE_FIELDS = ['name_origin', 'reference_note', 'reference_sources']


def read_array(name: str) -> list[dict]:
    path = ROOT / 'data' / name
    if not path.is_file():
        raise ValueError(f'Missing input: {path}')
    value = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value, list) or not all(isinstance(x, dict) for x in value):
        raise ValueError(f'{name} must be a JSON array of objects')
    return value


def read_atlases() -> tuple[dict, list[str]]:
    path = ROOT / 'atlas-manifest.json'
    if not path.is_file():
        return {}, []
    raw = json.loads(path.read_text(encoding='utf-8'))
    entries = raw.get('atlases', raw) if isinstance(raw, dict) else raw
    if isinstance(entries, dict):
        entries = [dict(value, atlas_id=key) for key, value in entries.items() if isinstance(value, dict)]
    if not isinstance(entries, list):
        raise ValueError('atlas-manifest.json must contain an atlas list or mapping')
    region_path = ROOT / 'atlas-regions.json'
    measured = json.loads(region_path.read_text(encoding='utf-8')).get('atlases', {}) if region_path.is_file() else {}
    result, warnings = {}, []
    for entry in entries:
        atlas_id = entry.get('atlas_id', entry.get('id'))
        rel = entry.get('image_path')
        if not atlas_id or not isinstance(rel, str):
            warnings.append(f'Skipped manifest entry without atlas_id/image_path: {atlas_id}')
            continue
        target = (ROOT / rel).resolve()
        if not target.is_relative_to(ROOT) or not target.is_file():
            warnings.append(f'Unavailable atlas file: {atlas_id} ({rel})')
            continue
        if entry.get('columns', 4) != 4 or entry.get('rows', 4) != 4:
            raise ValueError(f'{atlas_id}: expected a 4 by 4 atlas')
        content = target.read_bytes()
        if len(content) < 24 or content[:8] != b'\x89PNG\r\n\x1a\n':
            warnings.append(f'Invalid PNG: {atlas_id}')
            continue
        width, height = struct.unpack('>II', content[16:24])
        digest = hashlib.sha256(content).hexdigest()
        if entry.get('sha256') and entry['sha256'] != digest:
            raise ValueError(f'{atlas_id}: image SHA-256 does not match manifest')
        if width == 0 or height == 0:
            raise ValueError(f'{atlas_id}: empty image dimensions')
        if atlas_id in result:
            raise ValueError(f'Duplicate atlas manifest entry: {atlas_id}')
        atlas = dict(entry, atlas_id=atlas_id, image_path=target.relative_to(ROOT).as_posix(),
                     width=width, height=height, columns=4, rows=4, sha256=digest)
        measurement = measured.get(atlas_id)
        if measurement:
            if measurement.get('sha256') != digest:
                raise ValueError(f'{atlas_id}: region measurements are stale; rerun measure_atlases.py')
            if measurement.get('status') != 'passed':
                warnings.append(f'{atlas_id}: region QA failed; atlas withheld: {measurement.get("error", "unknown") }')
                continue
            regions = measurement.get('regions', [])
            if len(regions) != 16 or [r.get('cell_index') for r in regions] != list(range(16)):
                raise ValueError(f'{atlas_id}: expected 16 ordered measured regions')
            last_y = 0
            for row in range(4):
                cells = regions[row * 4:row * 4 + 4]
                first = cells[0]
                if first.get('y') != last_y:
                    raise ValueError(f'{atlas_id}: region rows must cover the image in order')
                last_x = 0
                for region in cells:
                    if any(not isinstance(region.get(k), int) for k in ['x', 'y', 'width', 'height']):
                        raise ValueError(f'{atlas_id}: region coordinates must be integers')
                    if region['x'] != last_x or region['y'] != first['y'] or region['height'] != first['height']:
                        raise ValueError(f'{atlas_id}: region columns must tile each row in order')
                    if region['width'] <= 0 or region['height'] <= 0 or region['x'] < 0 or region['y'] < 0 or region['x'] + region['width'] > width or region['y'] + region['height'] > height:
                        raise ValueError(f'{atlas_id}: region outside image bounds')
                    last_x += region['width']
                if last_x != width:
                    raise ValueError(f'{atlas_id}: measured row does not span image width')
                last_y += first['height']
            if last_y != height:
                raise ValueError(f'{atlas_id}: measured rows do not span image height')
            atlas['regions'] = regions
            atlas['region_qa'] = 'passed'
            warnings.extend(f'{atlas_id}: {warning}' for warning in measurement.get('warnings', []))
        result[atlas_id] = atlas
    return result, warnings


def build() -> dict:
    items = [x for name in ITEM_FILES for x in read_array(name)]
    profiles = [x for name in PROFILE_FILES for x in read_array(name)]
    if len(items) != 368 or Counter(x.get('collection') for x in items) != {'base': 240, 'sect': 128}:
        raise ValueError('Expected exactly 240 base items and 128 sect items')
    if len({x.get('id') for x in items}) != 368:
        raise ValueError('Item IDs must be unique')
    if len(profiles) != 8 or len({x.get('id') for x in profiles}) != 8:
        raise ValueError('Expected eight unique sect profiles')
    sect_ids = {x['id'] for x in profiles}
    atlas_cells = defaultdict(list)
    for item in items:
        missing = [key for key in FIELDS if key not in item]
        if missing:
            raise ValueError(f'{item.get("id")}: missing fields {missing}')
        for field in ['id', 'name', 'description', 'use', 'limitation', 'acquisition', 'appearance', 'art_prompt']:
            if not isinstance(item[field], str) or not item[field].strip():
                raise ValueError(f'{item["id"]}: {field} must be nonempty text')
        if item['collection'] == 'base' and item['sect_id'] is not None:
            raise ValueError(f'{item["id"]}: base item cannot belong to a sect')
        if item['collection'] == 'sect' and item['sect_id'] not in sect_ids:
            raise ValueError(f'{item["id"]}: unknown sect')
        if item['implementation_status'] != 'design_only':
            raise ValueError(f'{item["id"]}: catalogue cannot claim game implementation')
        atlas_cells[item['atlas_id']].append(item['cell_index'])
    expected_atlases = {f'B{i:02}' for i in range(1, 16)} | {f'S{i:02}' for i in range(1, 9)}
    if set(atlas_cells) != expected_atlases:
        raise ValueError('Expected atlases B01–B15 and S01–S08')
    for key, cells in atlas_cells.items():
        if len(cells) != 16 or set(cells) != set(range(16)):
            raise ValueError(f'{key}: must have every cell_index 0–15 exactly once')
    if set(Counter(x['sect_id'] for x in items if x['collection'] == 'sect').values()) != {16}:
        raise ValueError('Every sect must have exactly 16 items')

    atlases, warnings = read_atlases()
    for item in items:
        atlas = atlases.get(item['atlas_id'])
        # Derive availability from disk and manifest, never from an optimistic source flag.
        item['art_status'] = 'generated' if atlas else 'pending'
        item['asset_ref'] = ({'image_path': atlas['image_path'], 'atlas_id': item['atlas_id'],
                              'cell_index': item['cell_index'], 'columns': 4, 'rows': 4} if atlas else None)
        if atlas:
            item['asset_ref'].update(image_width=atlas['width'], image_height=atlas['height'])
            if atlas.get('regions'):
                region = atlas['regions'][item['cell_index']]
                item['asset_ref']['region'] = {k: region[k] for k in ['x', 'y', 'width', 'height']}
    items.sort(key=lambda x: (x['atlas_id'], x['cell_index']))
    metadata = {
        'version': 'wuxia-library-classic-v2', 'language': 'zh-Hant',
        'provenance': '240 original common items; sect arts use established names with sources, alongside plainly named traditional equipment. Gameplay and acquisition remain this project’s design.',
        'implementation_status': 'design_only', 'total_items': len(items),
        'base_items': 240, 'sect_items': 128,
        'generated_images': sum(x['art_status'] == 'generated' for x in items),
        'generated_atlases': len(atlases), 'warnings': warnings,
    }
    document = {'metadata': metadata, 'sects': profiles, 'atlases': atlases, 'items': items}
    (ROOT / 'catalog.json').write_text(json.dumps(document, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    with (ROOT / 'catalog.csv').open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS + REFERENCE_FIELDS)
        writer.writeheader()
        for item in items:
            row = {key: item[key] for key in FIELDS}
            row.update({key: item.get(key, '') for key in REFERENCE_FIELDS})
            row['reference_sources'] = json.dumps(item.get('reference_sources', []), ensure_ascii=False)
            row['asset_ref'] = json.dumps(row['asset_ref'], ensure_ascii=False) if row['asset_ref'] else ''
            writer.writerow(row)
    template = (ROOT / 'tools' / 'catalog_template.html').read_text(encoding='utf-8')
    payload = json.dumps(document, ensure_ascii=False).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
    if template.count('__CATALOG_DATA__') != 1:
        raise ValueError('Template must contain exactly one data placeholder')
    (ROOT / 'index.html').write_text(template.replace('__CATALOG_DATA__', payload), encoding='utf-8')
    sect_names = {x['id']: x['name'] for x in profiles}
    lines = ['武俠物品圖鑑｜經典門派版', '240 件通用物品＋128 件門派物品；門派武學採已有原名，玩法及取得方式另行設計。尚未接入遊戲。',
             f'已生成圖像：{metadata["generated_images"]}／368 件。', '']
    for item in items:
        lines.extend([f'{item["id"]}｜{item["name"]}｜{sect_names.get(item["sect_id"], "江湖通用")}｜{item["category_name"]}｜{item["tier"]}',
                      item['description'], f'用途：{item["use"]}', f'限制：{item["limitation"]}',
                      f'取得：{item["acquisition"]}', f'外觀：{item["appearance"]}',
                      '圖像：' + ('已生成' if item['art_status'] == 'generated' else '待製作'), ''])
        if item.get('reference_note'):
            lines.extend(['名稱說明：' + item['reference_note']])
        for source in item.get('reference_sources', []):
            lines.append('參考：' + source['title'] + ' ' + source['url'])
    (ROOT / 'CATALOG.txt').write_text('\n'.join(lines), encoding='utf-8')
    return metadata


if __name__ == '__main__':
    try:
        print(json.dumps(build(), ensure_ascii=False, indent=2))
    except (ValueError, OSError, json.JSONDecodeError) as error:
        raise SystemExit(f'Build stopped: {error}')
