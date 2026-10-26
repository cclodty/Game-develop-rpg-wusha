#!/usr/bin/env python3
"""Measure transparent atlas gaps without modifying or exporting any image pixels."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
THRESHOLD = 32
WINDOW = 0.12


def zero_runs(values: list[int]) -> list[tuple[int, int]]:
    runs, start = [], None
    for pos, count in enumerate(values + [1]):
        if count == 0 and start is None:
            start = pos
        elif count != 0 and start is not None:
            runs.append((start, pos))
            start = None
    return runs


def boundaries(foreground: list[int], any_alpha: list[int], label: str) -> tuple[list[int], list[dict]]:
    """Choose zero-projection cuts near quarter positions; exact alpha zero wins."""
    length = len(foreground)
    cuts, decisions = [0], []
    exact_runs, threshold_runs = zero_runs(any_alpha), zero_runs(foreground)
    for n in (1, 2, 3):
        target = n * length / 4
        low, high = target - WINDOW * length, target + WINDOW * length
        choice = None
        for mode, runs in [('alpha_zero', exact_runs), ('alpha_at_most_32', threshold_runs)]:
            candidates = []
            for start, end in runs:
                # Do not select the outside padding or clip a gap's midpoint to a search edge.
                mid = (start + end) // 2
                if start > 0 and end < length and low <= mid <= high:
                    candidates.append((abs(mid - target), -(end - start), mid, start, end))
            if candidates:
                _, _, cut, start, end = min(candidates)
                choice = {'axis': label, 'boundary': n, 'cut': cut, 'gap_start': start,
                          'gap_end': end, 'method': mode}
                break
        if choice is None:
            raise ValueError(f'{label}: no transparent gap near boundary {n} (±12%)')
        if choice['cut'] <= cuts[-1]:
            raise ValueError(f'{label}: detected boundaries are not ordered')
        cuts.append(choice['cut'])
        decisions.append(choice)
    cuts.append(length)
    return cuts, decisions


def measure(meta_path: Path) -> dict:
    meta = json.loads(meta_path.read_text(encoding='utf-8'))
    atlas_id = meta.get('atlas_id', meta_path.name.removesuffix('.meta.json'))
    rel = meta.get('image_path', f'assets/atlases/{atlas_id}.png')
    path = (ROOT / rel).resolve()
    entry = {'atlas_id': atlas_id, 'image_path': rel, 'status': 'qa_failed', 'regions': []}
    try:
        if not path.is_relative_to(ROOT) or not path.is_file():
            raise ValueError('Image path is missing or outside this library')
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        entry['sha256'] = digest
        if meta.get('sha256') and meta['sha256'] != digest:
            raise ValueError('PNG does not match its source metadata SHA-256')
        with Image.open(path) as im:
            width, height = im.size
            entry.update(width=width, height=height)
            if 'A' not in im.getbands():
                raise ValueError('PNG has no alpha channel; transparent gaps cannot be verified')
            # Read alpha bytes only; no crop, resize, pixel rewrite, or image export.
            alpha = im.getchannel('A').tobytes()
        rows_fg, rows_any = [], []
        for y in range(height):
            scan = alpha[y * width:(y + 1) * width]
            rows_fg.append(sum(v > THRESHOLD for v in scan))
            rows_any.append(sum(v > 0 for v in scan))
        y_cuts, gaps = boundaries(rows_fg, rows_any, 'rows')
        regions = []
        for row in range(4):
            top, bottom = y_cuts[row:row + 2]
            columns_fg, columns_any = [0] * width, [0] * width
            for y in range(top, bottom):
                for x, value in enumerate(alpha[y * width:(y + 1) * width]):
                    columns_fg[x] += value > THRESHOLD
                    columns_any[x] += value > 0
            x_cuts, row_gaps = boundaries(columns_fg, columns_any, f'row_{row}_columns')
            gaps.extend(row_gaps)
            for column in range(4):
                left, right = x_cuts[column:column + 2]
                if not any(columns_fg[left:right]):
                    raise ValueError(f'Cell {row * 4 + column} contains no foreground above alpha 32')
                regions.append({'cell_index': row * 4 + column, 'x': left, 'y': top,
                                'width': right - left, 'height': bottom - top})
        edge_foreground = (sum(v > THRESHOLD for v in alpha[:width]) +
                           sum(v > THRESHOLD for v in alpha[-width:]) +
                           sum(alpha[y * width] > THRESHOLD for y in range(1, height - 1)) +
                           sum(alpha[(y + 1) * width - 1] > THRESHOLD for y in range(1, height - 1)))
        warnings = []
        if any(g['method'] != 'alpha_zero' for g in gaps):
            warnings.append('Some boundaries contain faint alpha at most 32; no stronger foreground is cut.')
        if edge_foreground:
            warnings.append(f'{edge_foreground} foreground edge pixels; visual review should check outer clipping.')
        entry.update(status='passed', regions=regions, gaps=gaps, warnings=warnings,
                     foreground_outer_edge_pixels=edge_foreground)
    except (OSError, ValueError) as error:
        entry['error'] = str(error)
    return entry


def main() -> None:
    entries = [measure(p) for p in sorted((ROOT / 'assets' / 'atlases').glob('*.meta.json'))]
    report = {'schema_version': 1, 'method': 'Read-only alpha projections; gap-centered row and per-row column cuts.',
              'alpha_threshold': THRESHOLD, 'search_window_fraction': WINDOW,
              'summary': {'measured': len(entries), 'passed': sum(e['status'] == 'passed' for e in entries),
                          'failed': sum(e['status'] != 'passed' for e in entries)},
              'atlases': {e['atlas_id']: e for e in entries}}
    (ROOT / 'atlas-regions.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'summary': report['summary'],
                      'failures': {e['atlas_id']: e.get('error') for e in entries if e['status'] != 'passed'},
                      'warnings': {e['atlas_id']: e['warnings'] for e in entries if e.get('warnings')}}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
