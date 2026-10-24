#!/usr/bin/env python3
"""Real Chromium mouse/keyboard regression for martial v3.

Uses an isolated browser context and random loopback port. IndexedDB is read only:
no cards, health, rewards, random state, or engine actions are injected.
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
from test_web import Journey, QuietHandler, build_hashes, READ_SAVE_JS as LEGACY_SAVE_JS

JOURNEY_JS = LEGACY_SAVE_JS.replace('/run-v1.json', '/run-martial-v3.json').replace('value.version === 1', 'value.version === 3')
LAB_JS = JOURNEY_JS.replace('/run-martial-v3.json', '/lab-martial-v3.json')
ANSWERS = {'herbalist': [1, 2, 2, 2, 2, 2], 'courier': [0, 1, 0, 1, 2, 1], 'performer': [2, 0, 1, 0, 1, 0]}
# These values choose legal input actions, not a parallel rules implementation.
# All assertions inspect the game's saved result, and no future draw is read.
CARDS = {
    'strike': dict(cost=1, type='attack', damage=6),
    'guard': dict(cost=1, type='guard', block=5),
    'breath': dict(cost=0, type='change', energy=1),
    'observe': dict(cost=1, type='change', draw=2),
    'cloud_step': dict(cost=1, type='change', block=3, cycle=1),
    'opening_thrust': dict(cost=1, type='attack', damage=4, guard_bonus=4, boost=1, boost_damage=4),
    'sword_qi': dict(cost=2, type='attack', damage=10, boost=3, boost_damage=12),
    'pushing_palm': dict(cost=1, type='attack', damage=4, strip=6),
    'yielding_palm': dict(cost=1, type='guard', block=4, boost=1, boost_retaliation=6),
    'probing_stone': dict(cost=0, type='change', strip=2, boost=1, boost_draw=1),
    'hidden_needle': dict(cost=1, type='change', delayed=7, boost=1, boost_delayed=11),
    'gather_momentum': dict(cost=1, type='change', momentum_gain=1),
}
# Fixed logical viewport is 1440x900. Coordinates are verified against rendered
# native and browser screenshots; interaction remains ordinary mouse input.
TITLE_NEW = (376, 552)
TITLE_CONTINUE = (376, 632)
TITLE_LAB_NEW = (1083, 628)
TITLE_LAB_CONTINUE = (1083, 696)
HUB_PRESETS = {'shouzhong': (280, 369), 'xingyun': (720, 369), 'guiyuan': (1160, 369)}
HUB_ENEMIES = {'flurry': (225, 595), 'armored': (555, 595), 'charging': (885, 595), 'counter': (1215, 595)}
HUB_START = (1195, 813)
HUB_DECK = (245, 813)
HUB_EXIT = (1270, 83)
CARD_CENTER = lambda index: (147 + 210 * (index % 5), 542)
PLAY_NORMAL = (201, 696)
PLAY_BOOST = (517, 696)
RETAIN = (783, 692)
END_TURN = (990, 750)
MEDICINE = (783, 750)
MULLIGAN_SKIP = (750, 750)
PAUSE = (1320, 65)
SAVE_EXIT = (910, 665)
TRIAL_AGAIN = (513, 679)


class MartialJourney(Journey):
    def __init__(self, *args):
        super().__init__(*args)
        self.kind = 'journey'
        self.coverage = set()

    def read(self, kind=None):
        return self.page.evaluate(LAB_JS if (kind or self.kind) == 'lab' else JOURNEY_JS)

    def save(self, predicate, description, timeout=20):
        deadline, last = time.monotonic() + timeout, None
        while time.monotonic() < deadline:
            last = self.read()
            if isinstance(last, dict) and predicate(last):
                print('PASS MARTIAL WEB:', description, flush=True)
                return last
            self.page.wait_for_timeout(150)
        self.capture('failure')
        (self.output / f'{self.name}-failure-save.json').write_text(json.dumps(last, ensure_ascii=False, indent=2))
        raise AssertionError(f'Timed out: {description}; actual save={last}')

    def click(self, point):
        self.page.mouse.click(*point)
        self.page.wait_for_timeout(160)

    def reload_continue(self, expected, description):
        self.page.reload(wait_until='load')
        self.loaded()
        self.click(TITLE_LAB_CONTINUE if self.kind == 'lab' else TITLE_CONTINUE)
        current = self.save(lambda d: d.get('mode') == self.kind and bool(d.get('pending', {}).get('combat') or d.get('creation')), description)
        if expected.get('pending'):
            assert current['pending']['combat'] == expected['pending']['combat'], description
        else:
            assert current['creation'] == expected['creation'] and current['attributes'] == expected['attributes'], description
        assert current['spent'] == expected['spent']
        return current

    def create(self, checks):
        self.kind = 'journey'
        self.page.goto(self.url, wait_until='load', timeout=30000)
        self.loaded()
        self.capture('title')
        self.click(TITLE_NEW)
        self.click((460, 230))
        self.page.keyboard.press('Control+A')
        self.page.keyboard.type(self.hero_name, delay=30)
        self.click(({'herbalist': 334, 'courier': 719, 'performer': 1104}[self.name], 655))
        self.click((1109, 758))
        current = self.save(lambda d: d.get('phase') == 'prologue' and d['origin'] == self.name and d['hero_name'] == self.hero_name, 'real naming and origin selection start v3 creation')
        assert current['mode'] == 'journey' and current['spent'] == 0
        for index, answer in enumerate(ANSWERS[self.name]):
            self.save(lambda d: d['creation']['question'] == index and d['creation']['page'] == 'question', f'question {index + 1} is visible')
            screenshot = Image.open(io.BytesIO(self.capture(f'question-{index + 1}'))).convert('RGB')
            body = screenshot.crop((60, 218, 990, 548))
            pixels = body.get_flattened_data() if hasattr(body, 'get_flattened_data') else body.getdata()
            assert sum(1 for r, g, b in pixels if r < 120 and g < 150 and b < 130) > 1000, 'Authored prose must render, not merely exist in the save'
            self.click((720, 676 + 66 * answer))
            current = self.save(lambda d: d['creation']['page'] == 'aftermath' and d['creation']['answers'][index] == answer, 'answer persists its authored response')
            if self.name == 'herbalist' and index == 2:
                self.click((1267, 52))
                current = self.reload_continue(current, 'creation aftermath restores exactly')
                checks.append('Formal journey: mid-prologue save/reload preserves the response, choices and attributes')
            self.click((1175, 794))
        current = self.save(lambda d: d['creation']['page'] == 'summary', 'six decisions reach the attribute review')
        assert sum(current['attributes'].values()) == 30
        before = current['attributes'].copy()
        self.click((118, 348))
        self.click((604, 702))
        current = self.save(lambda d: len(d['creation']['adjustments']) == 1, 'manual point transfer saves once')
        assert current['attributes']['constitution'] == before['constitution'] - 1
        assert current['attributes']['fortune'] == before['fortune'] + 1
        self.capture('summary')
        # The advice sits below the six answer explanations; reveal it with
        # genuine wheel input so copy and wrapping can be visually reviewed.
        self.page.mouse.move(1090, 500)
        self.page.mouse.wheel(0, 1600)
        self.page.wait_for_timeout(200)
        self.capture('summary-advice')
        if self.name == 'performer':
            self.click((1267, 52))
            current = self.reload_continue(current, 'attribute summary restores its adjustment exactly')
        self.click((1189, 827))
        self.save(lambda d: d.get('dialogue', {}).get('title') == 'arrival_morning', 'confirmation enters the authored morning')
        current = self.finish_dialogue()
        assert current['phase'] == 'town' and current['spent'] == 0 and current['inner'] == 'guiyuan' and current['weapon'] == 'sword'
        before_x = current['world_position'][0]
        self.page.keyboard.down('d')
        self.page.wait_for_timeout(650)
        self.page.keyboard.up('d')
        self.page.keyboard.press('Control+s')
        current = self.save(lambda d: d['world_position'][0] > before_x + 35, 'WASD movement saves without spending time')
        assert current['spent'] == 0
        self.capture('town')
        checks.append(f'{self.name}: six choices, manual adjustment, authored morning and free movement on an independent v3 journey')
        return current

    def select_hand(self, index, combat):
        current_page = combat.get('_view', {}).get('page', 0)
        target_page = index // 5
        while current_page != target_page:
            self.click((1077 if current_page < target_page else 1049, 418))
            current_page += 1 if current_page < target_page else -1
            self.save(lambda d: d['pending']['combat'].get('_view', {}).get('page', 0) == current_page, 'actual hand-page button changes the displayed page')
        self.click(CARD_CENTER(index))

    def checkpoint_battle(self, label):
        self.click(PAUSE)
        frozen = self.save(lambda d: bool(d.get('pending', {}).get('combat')), 'paused card model is saved')
        self.page.wait_for_timeout(500)
        assert self.read()['pending']['combat'] == frozen['pending']['combat']
        self.capture(label + '-paused')
        self.click(SAVE_EXIT)
        self.reload_continue(frozen, label + ' restores its exact model and UI selections')
        self.capture(label + '-resumed')
        self.coverage.add(label)

    def choose_action(self, combat):
        living = [(i, enemy) for i, enemy in enumerate(combat['enemies']) if enemy['hp'] > 0]
        target, foe = min(living, key=lambda item: item[1]['hp'])
        incoming = sum(e['intent'].get('display_damage', e['intent'].get('damage', 0)) * e['intent'].get('hits', 1) for _, e in living)
        best, selected = 0.05, None
        for index, card_id in enumerate(combat['hand']):
            base = CARDS[card_id]
            for empowered in (False, True):
                card = dict(base)
                cost, boost_cost = card['cost'], card.get('boost', 0)
                if cost > combat['qi'] or (empowered and (boost_cost == 0 or boost_cost > combat['momentum'])):
                    continue
                damage = card.get('damage', 0) + (card.get('boost_damage', 0) if empowered else 0)
                if card.get('guard_bonus') and combat['block'] > 0:
                    damage += card['guard_bonus']
                if empowered and boost_cost == 3 and combat['stats']['inner'] == 'guiyuan' and card['type'] == 'attack':
                    damage += 8
                score = max(0, damage - max(0, foe['block'] - card.get('strip', 0))) * 3
                block = card.get('block', 0)
                if empowered and combat['stats']['inner'] == 'shouzhong':
                    block += boost_cost * 2
                score += min(block, max(0, incoming - combat['block'])) * 4
                score += min(card.get('strip', 0), foe['block']) * 2
                score += (card.get('boost_delayed', card.get('delayed', 0)) if empowered else card.get('delayed', 0)) * 2.5
                if empowered and incoming > 0 and not combat.get('retaliation', 0):
                    score += card.get('boost_retaliation', 0) * 3.5
                if card.get('energy'):
                    score += 45 if len(combat['hand']) > 1 else 1
                draw = card.get('draw', 0) + (card.get('boost_draw', 0) if empowered else 0)
                if combat['qi'] > cost:
                    score += draw * 7
                if card.get('cycle') and len(combat['hand']) > 1:
                    score += 6
                if card.get('momentum_gain') and combat['momentum'] < 3 and combat['momentum_gained'] < 2:
                    score += 12
                if empowered:
                    score -= boost_cost * 2
                if combat['stats']['inner'] == 'guiyuan' and combat['qi'] == cost and combat['momentum'] < 3 and score < 15:
                    score -= 12
                if score > best:
                    best, selected = score, (index, target, empowered)
        return selected

    def fight(self, checks, label, save_cycle=False, save_retain=False):
        current = self.save(lambda d: d.get('pending', {}).get('combat', {}).get('phase') == 'mulligan', 'trial opens an actual five-card starting hand')
        assert len(current['pending']['combat']['hand']) == 5
        self.capture(label + '-mulligan')
        self.click(MULLIGAN_SKIP)
        self.save(lambda d: d['pending']['combat']['phase'] == 'player', 'visible keep-hand button starts the first turn')
        for _ in range(220):
            current = self.read()
            combat = current.get('pending', {}).get('combat', {})
            if not combat:
                break
            phase = combat['phase']
            if phase in ('won', 'lost'):
                assert phase == 'won', f'{label} lost a legally played battle'
                self.page.wait_for_timeout(500)
                continue
            if phase == 'choice':
                if combat['hand']:
                    self.select_hand(0, combat)
                    self.save(lambda d: d['pending']['combat'].get('_view', {}).get('cycle_selection') == [0], 'cycle card selection is recorded in the UI snapshot')
                if save_cycle and 'cycle-choice' not in self.coverage:
                    self.capture(label + '-cycle')
                    self.checkpoint_battle('cycle-choice')
                before = self.read()['pending']['combat']
                self.click(PLAY_NORMAL if combat['hand'] else PLAY_BOOST)
                after = self.save(lambda d: d['pending']['combat']['phase'] == 'player', 'visible cycle confirmation resolves the waiting action')['pending']['combat']
                assert not after['in_play'] and not after['pending_choice']
                assert after['cards_played'] == before['cards_played']
                self.coverage.add('cycle')
                continue
            if combat['hp'] <= combat['max_hp'] - 20 and combat['medicine_used'] == 0 and combat['qi'] >= 1 and combat['stats']['medicine'] > 0:
                self.click(MEDICINE)
                self.save(lambda d: d['pending']['combat']['medicine_used'] == 1, 'medicine costs a legal once-per-battle use')
                continue
            action = self.choose_action(combat)
            if action is None:
                if combat['hand']:
                    keep = next((i for i, card in enumerate(combat['hand']) if card in ('sword_qi', 'cloud_step')), 0)
                    self.select_hand(keep, combat)
                    if self.read()['pending']['combat'].get('_view', {}).get('retained_index', -1) != keep:
                        self.click(RETAIN)
                    self.save(lambda d: d['pending']['combat'].get('_view', {}).get('retained_index') == keep, 'retention marks one actual hand card')
                    self.coverage.add('retain')
                    if save_retain and 'retain-selection' not in self.coverage:
                        self.capture(label + '-retained')
                        self.checkpoint_battle('retain-selection')
                turn = combat['turn']
                self.click(END_TURN)
                self.save(lambda d: not d.get('pending') or d['pending']['combat']['turn'] > turn or d['pending']['combat']['phase'] in ('won', 'lost'), 'ending the turn resolves visible intentions and fills to five')
                continue
            index, target, empowered = action
            self.select_hand(index, combat)
            self.save(lambda d: d['pending']['combat'].get('_view', {}).get('selected_card') == index, 'selecting a card does not auto-spend it')
            if len([e for e in combat['enemies'] if e['hp'] > 0]) > 1:
                self.click((748 + target * 220, 350))
            if empowered and 'boost' not in self.coverage:
                self.capture(label + '-boost-preview')
            self.click(PLAY_BOOST if empowered else PLAY_NORMAL)
            self.save(lambda d: not d.get('pending') or d['pending']['combat']['cards_played'] > combat['cards_played'], 'explicit normal or empowered button resolves the selected card')
            self.coverage.add('boost' if empowered else 'normal')
        current = self.save(lambda d: d['mode'] == 'lab' and d['phase'] == 'town' and not d['pending'], 'trial victory settles without a journey reward')
        assert current['spent'] == 0 and current['training'] == 0 and not current['completed']
        assert current['trial_history'][-1]['won'], 'The trial must have ended in a legal victory'
        self.capture(label + '-result')
        self.click(TRIAL_AGAIN)
        checks.append(label + ': legal visible actions win and settle once; no journey costs or rewards')

    def lab(self, checks):
        self.click(PAUSE)
        self.click(SAVE_EXIT)
        formal = self.read('journey')
        self.click(TITLE_LAB_NEW)
        self.kind = 'lab'
        current = self.save(lambda d: d['mode'] == 'lab' and d['phase'] == 'town', 'dedicated trial entry creates a separate lab save')
        assert len(current['learned_cards']) == 12 and len(current['learned_inners']) == 3
        assert set(current['attributes'].values()) == {5}
        self.capture('lab-hub')
        for preset, foe in [('shouzhong', 'flurry'), ('xingyun', 'armored'), ('guiyuan', 'charging')]:
            self.click(HUB_PRESETS[preset])
            self.save(lambda d: d['inner'] == preset and not d['refinements'], 'sample preset changes its genuine loadout')
            self.click(HUB_ENEMIES[foe])
            self.click(HUB_START)
            self.save(lambda d: d.get('pending', {}).get('battle_mode') == foe, 'selected trial enemy starts with a locked loadout')
            self.fight(checks, 'lab-' + preset + '-' + foe, save_cycle=preset == 'xingyun', save_retain=preset == 'shouzhong')
            assert self.read('journey') == formal, 'Lab input must leave the formal journey unchanged'
        assert {'normal', 'boost', 'retain', 'cycle', 'cycle-choice', 'retain-selection'} <= self.coverage, self.coverage
        self.click(HUB_ENEMIES['counter'])
        self.click(HUB_START)
        current = self.save(lambda d: d.get('pending', {}).get('battle_mode') == 'counter', 'fourth enemy type has its actual public counter intent')
        assert current['pending']['combat']['enemies'][0]['intent'].get('counter_damage', 0) > 0
        self.capture('lab-counter-intent')
        self.click((1275, 740))
        self.click((913, 575))
        self.save(lambda d: not d['pending'] and d['phase'] == 'town', 'withdrawal settles only the trial')
        self.click(HUB_EXIT)
        self.page.reload(wait_until='load')
        self.loaded()
        self.click(TITLE_CONTINUE)
        self.kind = 'journey'
        restored = self.save(lambda d: d['mode'] == 'journey', 'formal Continue selects the original character')
        assert restored == formal
        checks.append('Independent lab and formal saves, all three presets and four enemy choices preserve the formal character')
        checks.append('Actual retain and cycle selections restore mid-action; explicit boost and normal decisions both execute')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--browser', default=shutil.which('chromium') or shutil.which('google-chrome'))
    parser.add_argument('--output', type=Path)
    parser.add_argument('--origins', nargs='+', choices=tuple(ANSWERS), default=list(ANSWERS))
    parser.add_argument('--record-video', action='store_true')
    parser.add_argument('--creation-only', action='store_true', help='Scoped follow-up; does not claim lab coverage.')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output or root / 'artifacts/martial-validation/web'
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
                journey = MartialJourney(page, url, output, origin)
                journey.create(checks)
                capability = page.evaluate('({width:canvas.width,height:canvas.height,threads:GODOT_THREADS_ENABLED,webgl:!!canvas.getContext("webgl2")})')
                assert capability == {'width': 1440, 'height': 900, 'threads': False, 'webgl': True}, capability
                if origin == 'herbalist' and not args.creation_only:
                    journey.lab(checks)
                context.close()
                if args.record_video:
                    target = output / 'recordings' / f'{origin}-martial.webm'
                    page.video.save_as(str(target))
                    recordings.append({'origin': origin, 'path': str(target)})
                completed.append(origin)
                (output / 'progress.json').write_text(json.dumps({'status': 'partial', 'completed_origins': completed, 'checks': checks, 'build_sha256': hashes, 'state_injection': False}, ensure_ascii=False, indent=2))
            browser.close()
        errors = [m for m in messages if m['type'] == 'pageerror' or 'SCRIPT ERROR' in m['text'] or m['text'].startswith('ERROR:')]
        assert not errors, errors
        assert build_hashes(web) == hashes, 'Export changed during browser testing'
        result = {'checks': checks, 'origins': args.origins, 'creation_only': args.creation_only, 'console': messages, 'state_injection': False, 'build_sha256': hashes, 'recordings': recordings}
        (output / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
        print(f'MARTIAL WEB TESTS COMPLETE: {len(checks)} flow groups passed; no engine/browser errors', flush=True)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
