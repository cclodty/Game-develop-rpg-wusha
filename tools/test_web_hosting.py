#!/usr/bin/env python3
"""Exercise the native game at GitHub Pages' project path, using real input."""
import argparse
import json
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import shutil
from threading import Thread
from urllib.parse import urlsplit

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
PREFIX = '/Game-develop-rpg-wusha/'


class ProjectHandler(SimpleHTTPRequestHandler):
    def translate_path(self, path):
        parsed = urlsplit(path)
        if not parsed.path.startswith(PREFIX):
            return str(ROOT / '__not_a_public_path__')
        return super().translate_path(parsed.path[len(PREFIX) - 1:])

    def log_message(self, *_args):
        pass


def run(url, output):
    errors, missing, checks = [], [], []
    output.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=shutil.which('chromium'), headless=True,
                                    args=['--no-sandbox', '--disable-dev-shm-usage'])
        for width, height in [(1440, 900), (960, 600)]:
            context = browser.new_context(viewport={'width': width, 'height': height})
            page = context.new_page()
            page.on('pageerror', lambda error: errors.append(str(error)))
            page.on('console', lambda message: errors.append(message.text) if message.type == 'error' else None)
            page.on('response', lambda response: missing.append(response.url) if response.status >= 400 else None)
            page.goto(url, wait_until='networkidle')
            page.locator('#hero-name').wait_for()
            assert urlsplit(page.url).path.endswith('/web/'), page.url
            page.evaluate('document.fonts.ready')
            assert page.evaluate('document.fonts.check("24px WenKai")')
            page.screenshot(path=str(output / f'title-{width}.png'))
            checks.append(f'{width}x{height}: root redirects to the project web path; bundled font renders')

            # Use the actual settings controls so reading is stable across reloads.
            page.locator('[data-action="settings"]').click()
            page.locator('[data-action="speed:0"]').click()
            page.locator('[data-action="close"]').click()
            page.locator('#hero-name').fill('渡口試行者')
            page.locator('[data-action="new"]').click()
            page.locator('.vn-text').wait_for()
            page.locator('[data-action="inventory"]').click()
            page.locator('.inventory[role="dialog"]').wait_for()
            page.screenshot(path=str(output / f'inventory-{width}.png'))
            page.locator('[data-action="bag-filter:key"]').click()
            assert page.locator('.inventory-grid').inner_text()
            page.locator('[data-action="close"]').click()
            page.locator('.vn-text').click()
            page.wait_for_timeout(100)
            read_save = 'JSON.parse(localStorage.getItem("jianghu-gal-web-v1:auto"))'
            before = page.evaluate(read_save)
            assert before['state']['actors']['hero']['name'] == '渡口試行者'
            page.screenshot(path=str(output / f'dialogue-{width}.png'))
            page.reload(wait_until='networkidle')
            page.locator('[data-action="continue"]').click()
            page.locator('.vn-text').wait_for()
            after = page.evaluate(read_save)
            assert before['state'] == after['state'], 'reload changed story/model state'
            assert before['ui']['reader']['index'] == after['ui']['reader']['index']
            assert before['ui']['reader']['id'] == after['ui']['reader']['id']
            assert page.evaluate('JSON.parse(localStorage.getItem("jianghu-gal-web-reading-v1")).speed') == 0
            checks.append(f'{width}x{height}: naming, dialogue, inventory/filter, preferences and exact model reload pass')
            context.close()
        browser.close()
    assert not missing, missing
    assert not errors, errors
    result = {'url': url, 'checks': checks, 'page_or_console_errors': errors,
              'failed_http_resources': missing, 'state_injection': False}
    (output / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f'WEB HOSTING: {len(checks)} flow groups passed, no resource or browser errors')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', help='Optional deployed site; default serves a temporary project subpath')
    parser.add_argument('--output', type=Path, default=ROOT / 'artifacts/web-hosting')
    args = parser.parse_args()
    if args.url:
        run(args.url, args.output)
        return
    server = ThreadingHTTPServer(('127.0.0.1', 0), partial(ProjectHandler, directory=str(ROOT)))
    Thread(target=server.serve_forever, daemon=True).start()
    try:
        run(f'http://127.0.0.1:{server.server_port}{PREFIX}', args.output)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
