#!/usr/bin/env python3
"""Real Chromium card-prototype input regression; read-only save inspection.

Uses isolated browser contexts on a random loopback origin. No state injection,
engine automation API, artificial rewards, or player save files are used.
"""
import argparse
from functools import partial
from http.server import ThreadingHTTPServer
import io
import json
from pathlib import Path
import shutil
from threading import Thread
import time

from PIL import Image
from playwright.sync_api import sync_playwright
from test_web import Journey, QuietHandler, build_hashes, READ_SAVE_JS as LEGACY_READ_SAVE_JS

READ_SAVE_JS = LEGACY_READ_SAVE_JS.replace('/run-v1.json', '/run-cards-v2.json').replace('value.version === 1', 'value.version === 2')
ANSWERS = {'herbalist': [1, 2, 2, 2, 2, 2], 'courier': [0, 1, 0, 1, 2, 1], 'performer': [2, 0, 1, 0, 1, 0]}
BASIC = {'strike': {'cost': 1, 'damage': 6}, 'guard': {'cost': 1, 'block': 5}, 'breath': {'cost': 0, 'energy': 1}, 'observe': {'cost': 1, 'draw': 2}, 'feint': {'cost': 1, 'damage': 4, 'weak': 1}, 'herb_poultice': {'cost': 1, 'block': 3, 'heal': 5}}


class CardJourney(Journey):
    def save(self, predicate, description, timeout=20):
        deadline, last = time.monotonic() + timeout, None
        while time.monotonic() < deadline:
            last = self.page.evaluate(READ_SAVE_JS)
            if isinstance(last, dict) and predicate(last):
                print('PASS CARD WEB:', description, flush=True)
                return last
            self.page.wait_for_timeout(150)
        self.capture('failure')
        (self.output / f'{self.name}-failure-save.json').write_text(json.dumps(last, ensure_ascii=False, indent=2))
        raise AssertionError(f'Timed out: {description}; actual save={last}')

    def click(self, x, y):
        self.page.mouse.click(x, y)
        self.page.wait_for_timeout(100)

    def continue_saved(self, expected_creation=None):
        self.page.reload(wait_until='load')
        self.loaded()
        self.click(376, 632)
        if expected_creation is not None:
            return self.save(lambda d: d.get('phase') == 'prologue' and d.get('creation') == expected_creation, 'Continue restores the exact creation answers, page and adjustments')
        return self.save(lambda d: d.get('pending', {}).get('combat'), 'Continue restores the pending card encounter')

    def creation(self, checks):
        self.page.goto(self.url, wait_until='load', timeout=30000)
        self.loaded()
        self.capture('title')
        self.click(376, 552)
        self.click(460, 230)
        self.page.keyboard.press('Control+A')
        self.page.keyboard.type(self.hero_name, delay=35)
        self.click({'herbalist': 334, 'courier': 719, 'performer': 1104}[self.name], 655)
        self.capture('name-origin')
        self.click(1109, 758)
        current = self.save(lambda d: d.get('phase') == 'prologue' and d.get('hero_name') == self.hero_name and d.get('origin') == self.name, 'real keyboard name and mouse origin enter the prologue')
        assert current['spent'] == 0
        self.mark('prologue-start')
        for index, answer in enumerate(ANSWERS[self.name]):
            current = self.save(lambda d: d['creation']['question'] == index and d['creation']['page'] == 'question', f'question {index + 1} is active')
            picture = Image.open(io.BytesIO(self.capture(f'question-{index + 1}'))).convert('RGB')
            body = picture.crop((60, 218, 990, 548))
            pixels = body.get_flattened_data() if hasattr(body, 'get_flattened_data') else body.getdata()
            dark = sum(1 for r, g, b in pixels if r < 120 and g < 150 and b < 130)
            assert dark > 1000, f'Question {index + 1} body appears blank: {dark} dark pixels'
            self.click(720, 676 + 66 * answer)
            current = self.save(lambda d: d['creation']['page'] == 'aftermath' and d['creation']['answers'][index] == answer, f'choice {index + 1} persists its authored response')
            if self.name == 'herbalist' and index == 2:
                checkpoint = current['creation']
                self.capture('mud-response')
                self.click(1267, 52)
                current = self.continue_saved(checkpoint)
                self.capture('mud-response-resumed')
                checks.append('Herbalist: save/exit and reload resume the exact third-question aftermath')
            self.click(1175, 794)
        current = self.save(lambda d: d['creation']['page'] == 'summary', 'six choices reach the ability summary')
        assert current['creation']['answers'] == ANSWERS[self.name]
        assert sum(current['attributes'].values()) == 30
        self.capture('summary-before')
        before = current['attributes'].copy()
        self.click(118, 348)  # Constitution source, not a DOM mutation.
        self.click(604, 702)  # Fortune destination.
        current = self.save(lambda d: len(d['creation']['adjustments']) == 1, 'visible controls transfer one ability point')
        assert current['attributes']['constitution'] == before['constitution'] - 1
        assert current['attributes']['fortune'] == before['fortune'] + 1
        assert sum(current['attributes'].values()) == 30 and all(2 <= value <= 8 for value in current['attributes'].values())
        self.capture('summary-after')
        if self.name == 'performer':
            checkpoint = current['creation']
            self.click(1267, 52)
            current = self.continue_saved(checkpoint)
            self.capture('summary-resumed')
            checks.append('Performer: summary adjustments persist across save/exit and reload')
        self.click(1189, 827)
        current = self.save(lambda d: d.get('dialogue', {}).get('title') == 'arrival_morning', 'confirmation enters the new morning arrival story')
        self.mark('prologue-end')
        current = self.finish_dialogue()
        assert current['phase'] == 'town' and current['spent'] == 0 and not current['pending']
        self.page.wait_for_timeout(1800)
        self.capture('town')
        before_x = current['world_position'][0]
        self.page.keyboard.down('d')
        self.page.wait_for_timeout(650)
        self.page.keyboard.up('d')
        self.page.keyboard.press('Control+s')
        current = self.save(lambda d: d['world_position'][0] > before_x + 35, 'real WASD walking saves the new world position')
        assert current['spent'] == 0
        checks.append(f'{self.name}: six real choices, thirty-point summary, manual adjustment, bespoke morning, free town walking')
        return current

    def equip_origin(self, checks):
        original = self.save(lambda d: d['phase'] == 'town', 'read original ten-card deck')['deck']
        self.click(1276, 457)
        self.capture('deck')
        self.click(983, 267)  # Remove one strike from the draft.
        self.capture('deck-nine')
        self.click(1180, 820)  # Disabled Apply cannot commit nine cards.
        assert self.save(lambda d: True, 'incomplete deck does not overwrite the saved ten cards')['deck'] == original
        # Bring the sixth (learned origin) row into view with real scrolling.
        self.page.mouse.move(1200, 420)
        self.page.mouse.wheel(0, 450)
        self.page.wait_for_timeout(250)
        self.capture('deck-origin-scroll')
        picture = Image.open(io.BytesIO(self.page.screenshot())).convert('RGB')
        spans, first = [], None
        for y in range(180, 710):
            enabled = picture.getpixel((1090, y)) == (255, 251, 239)
            if enabled and first is None:
                first = y
            elif not enabled and first is not None:
                if 20 <= y - first <= 50:
                    spans.append((first, y))
                first = None
        assert len(spans) == 1, f'Expected one visible enabled add button for the learned origin card; found {spans}'
        self.click(1103, sum(spans[0]) / 2)
        self.capture('deck-origin-added')
        self.click(1180, 820)
        current = self.save(lambda d: d['deck'].count('herb_poultice') == 1 and d['deck'].count('strike') == 1, 'actual visible origin-card swap commits a legal ten-card deck')
        assert len(current['deck']) == 10 and current['spent'] == 0
        checks.append('Visible deck editing rejects nine cards and saves an actual origin-card substitution without spending time')
        return current

    def practice(self, checks):
        self.click(1276, 653)
        self.capture('planner')
        self.click(784, 464)
        self.capture('practice-cost')
        assert self.save(lambda d: True, 'activity preview does not spend a slot')['spent'] == 0
        self.click(970, 670)
        current = self.save(lambda d: d.get('pending', {}).get('id') == 'practice', 'practice starts and charges exactly one slot')
        assert current['spent'] == 1
        self.finish_dialogue()
        current = self.save(lambda d: d.get('pending', {}).get('combat', {}).get('phase') == 'mulligan', 'actual card encounter presents five-card mulligan')
        assert len(current['pending']['combat']['hand']) == 5 and current['pending']['combat']['qi'] == 3
        self.capture('battle-mulligan')
        self.click(147, 606)
        self.save(lambda d: d['pending']['combat'].get('_view', {}).get('mulligan_selection') == [0], 'actual first card is selected for the opening redraw')
        self.click(986, 746)
        current = self.save(lambda d: d['pending']['combat']['phase'] == 'player' and d['pending']['combat']['mulligan_used'], 'visible redraw button begins the first turn')
        self.mark('battle-start')
        self.capture('battle')
        self.click(1320, 65)
        frozen = self.save(lambda d: d['pending']['combat']['phase'] == 'player', 'pause preserves the current card turn')['pending']['combat']
        self.page.wait_for_timeout(700)
        assert self.save(lambda d: True, 'paused time does not change the card model')['pending']['combat'] == frozen
        self.capture('battle-paused')
        self.click(910, 665)
        current = self.continue_saved()
        assert current['spent'] == 1 and current['pending']['combat'] == frozen
        self.capture('battle-resumed')
        for _ in range(100):
            current = self.save(lambda d: True, 'read live card checkpoint')
            if current.get('dialogue'):
                current = self.finish_dialogue()
                break
            combat = current.get('pending', {}).get('combat', {})
            if not combat:
                break
            if combat['phase'] in ('won', 'lost'):
                assert combat['phase'] == 'won', combat
                self.page.wait_for_timeout(500)
                continue
            assert combat['phase'] == 'player'
            incoming = sum(e['intent'].get('display_damage', e['intent']['damage']) * e['intent']['hits'] for e in combat['enemies'] if e['hp'] > 0)
            if not combat['medicine_used_this_turn'] and combat['medicine_used'] < combat['stats']['medicine'] and combat['hp'] <= combat['max_hp'] - 20:
                self.click(783, 746)
            else:
                choice, best = None, -1000
                for index, card_id in enumerate(combat['hand']):
                    card = BASIC[card_id]
                    if card['cost'] > combat['qi']:
                        continue
                    score = 40 + card['damage'] if 'damage' in card else 0
                    if 'weak' in card and combat['enemies'][0]['weak'] == 0 and incoming > combat['block']:
                        score += 20
                    if 'block' in card and incoming > combat['block']:
                        score += 60
                    if 'draw' in card and combat['qi'] > card['cost']:
                        score += 15
                    if 'energy' in card:
                        score += 100
                    if score > best:
                        choice, best = index, score
                if choice is None:
                    self.click(986, 746)
                else:
                    page_index = combat.get('_view', {}).get('page', 0)
                    wanted = choice // 5
                    while page_index != wanted:
                        self.click(1063 if page_index < wanted else 875, 480)
                        page_index += 1 if page_index < wanted else -1
                    self.page.mouse.move(147 + 210 * (choice % 5), 606)
                    self.page.wait_for_timeout(60)
                    self.click(147 + 210 * (choice % 5), 606)
            previous = (combat['turn'], combat['cards_played'], combat['medicine_used'])
            current = self.save(lambda d: bool(d.get('dialogue')) or not d.get('pending') or (d['pending']['combat']['turn'], d['pending']['combat']['cards_played'], d['pending']['combat']['medicine_used']) != previous, 'visible card or turn input changes the real model')
        current = self.save(lambda d: d['phase'] == 'town' and not d['pending'], 'card victory and authored debrief settle once')
        assert current['spent'] == 1 and current['training'] == 1 and current['mastery'] == 1
        assert current['completed'].count('practice') == 1
        self.capture('practice-complete')
        checks.append('Real opening redraw, pause/save/reload, legal card/turn inputs and victory settle one practice slot/reward exactly once')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--browser', default=shutil.which('chromium') or shutil.which('google-chrome'))
    parser.add_argument('--output', type=Path)
    parser.add_argument('--origins', nargs='+', choices=tuple(ANSWERS), default=list(ANSWERS))
    parser.add_argument('--record-video', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output or root / 'artifacts/cards-validation/web'
    output.mkdir(parents=True, exist_ok=True)
    for name in ('result.json', 'progress.json'):
        (output / name).unlink(missing_ok=True)
    web = root / 'build/web'
    hashes = build_hashes(web)
    messages, checks, completed, recordings = [], [], [], []
    server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(web)))
    Thread(target=server.serve_forever, daemon=True).start()
    url = f'http://127.0.0.1:{server.server_address[1]}/'
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(executable_path=args.browser, headless=True, args=['--no-sandbox', '--disable-dev-shm-usage', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'])
            for origin in args.origins:
                options = {'viewport': {'width': 1440, 'height': 900}, 'device_scale_factor': 1}
                if args.record_video:
                    options.update(record_video_dir=str(output / 'recordings'), record_video_size={'width': 1440, 'height': 900})
                context = browser.new_context(**options)
                page = context.new_page()
                page.on('console', lambda event: messages.append({'type': event.type, 'text': event.text}))
                page.on('pageerror', lambda error: messages.append({'type': 'pageerror', 'text': str(error)}))
                journey = CardJourney(page, url, output, origin)
                journey.creation(checks)
                capability = page.evaluate('({width:canvas.width,height:canvas.height,threads:GODOT_THREADS_ENABLED,isolated:crossOriginIsolated,webgl:!!canvas.getContext("webgl2")})')
                assert capability == {'width': 1440, 'height': 900, 'threads': False, 'isolated': False, 'webgl': True}, capability
                if origin == 'herbalist':
                    journey.equip_origin(checks)
                    journey.practice(checks)
                context.close()
                if args.record_video:
                    target = output / 'recordings' / f'{origin}-cards.webm'
                    page.video.save_as(str(target))
                    recordings.append({'origin': origin, 'path': str(target), 'markers': journey.markers})
                completed.append(origin)
                (output / 'progress.json').write_text(json.dumps({'status': 'partial', 'completed_origins': completed, 'checks': checks, 'build_sha256': hashes, 'state_injection': False, 'recordings': recordings}, ensure_ascii=False, indent=2))
            browser.close()
        errors = [m for m in messages if m['type'] == 'pageerror' or 'SCRIPT ERROR' in m['text'] or m['text'].startswith('ERROR:')]
        assert not errors, errors
        assert build_hashes(web) == hashes, 'Export changed during browser testing'
        (output / 'result.json').write_text(json.dumps({'checks': checks, 'origins': args.origins, 'console': messages, 'state_injection': False, 'build_sha256': hashes, 'recordings': recordings}, ensure_ascii=False, indent=2))
        print(f'CARD WEB TESTS COMPLETE: {len(checks)} flow groups passed; no engine/browser errors', flush=True)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
