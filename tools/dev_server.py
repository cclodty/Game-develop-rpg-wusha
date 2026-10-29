"""Local GAL development server. Python 3.10+, standard library only."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import threading
from urllib.parse import urlsplit, unquote
import webbrowser

ROOT = Path(__file__).resolve().parents[1]
WATCH = ('web', 'battle', 'spire', 'chapter', 'assets')
CLIENT = r"""
(() => {
  let previous = null;
  async function poll() {
    try {
      const response = await fetch('/__dev/version', {cache:'no-store'});
      if (!response.ok) return;
      const current = await response.json();
      if (previous) {
        for (const link of document.querySelectorAll('link[rel="stylesheet"]')) {
          const url = new URL(link.href);
          const key = decodeURIComponent(url.pathname).slice(1);
          if (current.css[key] !== previous.css[key]) {
            url.searchParams.set('dev', Date.now()); link.href = url.href;
          }
        }
        if (current.code !== previous.code && !document.getElementById('dev-update')) {
          const button = document.createElement('button');
          button.id = 'dev-update';
          button.textContent = '程式或素材已更新 · 點此重新載入';
          button.style.cssText = 'position:fixed;right:clamp(8px,.84vw,12px);top:clamp(8px,.84vw,12px);z-index:9999;min-height:0;min-width:0;line-height:1.35;font:clamp(12px,1.25vw,18px) WenKai,serif;background:#fff4db;color:#28463c;border:2px solid #a58a51;padding:clamp(6px,.7vw,10px);cursor:pointer';
          button.onclick = () => location.reload();
          document.body.append(button);
        }
      }
      previous = current;
    } catch (_) { /* Server can be stopped and restarted without losing the page. */ }
    finally { setTimeout(poll, 1000); }
  }
  poll();
})();
"""

def versions(root):
    css, code = {}, []
    for folder in WATCH:
        for file in sorted((root/folder).rglob('*')):
            if not file.is_file() or file.suffix not in {'.css','.js','.mjs','.html','.png','.webp','.ttf','.otf'}:
                continue
            stat = file.stat()
            key = file.relative_to(root).as_posix()
            stamp = f'{stat.st_mtime_ns}:{stat.st_size}'
            if file.suffix == '.css':
                css[key] = stamp
            else:
                code.append((key, stamp))
    return {'css': css, 'code': json.dumps(code, separators=(',', ':'))}

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, root=ROOT, **kwargs):
        self.root = root.resolve()
        super().__init__(*args, directory=str(self.root), **kwargs)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def send_data(self, body, content_type):
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = unquote(urlsplit(self.path).path)
        if path == '/__dev/version':
            return self.send_data(json.dumps(versions(self.root)).encode(), 'application/json')
        if path == '/__dev/client.js':
            return self.send_data(CLIENT.encode(), 'text/javascript; charset=utf-8')
        if path == '/':
            self.send_response(302)
            self.send_header('Location', '/web/')
            self.end_headers()
            return
        candidate = (self.root/path.lstrip('/')).resolve()
        allowed = any(candidate.is_relative_to((self.root/folder).resolve()) for folder in WATCH)
        if not allowed:
            return self.send_error(404)
        if candidate.is_dir():
            candidate /= 'index.html'
        if candidate.is_file() and candidate.suffix == '.html':
            html = candidate.read_text(encoding='utf-8')
            html = html.replace('</body>', '<script src="/__dev/client.js"></script></body>')
            return self.send_data(html.encode(), 'text/html; charset=utf-8')
        if not candidate.is_file():
            return self.send_error(404)
        super().do_GET()

    def do_HEAD(self):
        # Do not let the inherited handler bypass the GET allowlist.
        self.send_error(405)

    def log_message(self, fmt, *args):
        if '/__dev/version' not in str(args):
            super().log_message(fmt, *args)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8091)
    parser.add_argument('--no-browser', action='store_true')
    args = parser.parse_args()
    try:
        server = ThreadingHTTPServer(('127.0.0.1', args.port), partial(Handler, root=ROOT))
    except OSError as error:
        raise SystemExit(f'Cannot start port {args.port}: {error}\nClose the previous preview window and retry. Keep the same port to retain browser saves.')
    url = f'http://127.0.0.1:{args.port}/web/'
    print(f'Local game: {url}\nCSS updates automatically. Code changes offer a reload button.\nPress Ctrl+C to stop.', flush=True)
    if not args.no_browser:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

if __name__ == '__main__':
    main()
