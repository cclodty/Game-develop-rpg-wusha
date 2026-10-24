#!/usr/bin/env python3
"""Serve the exported browser game locally; no external publication."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class GameHandler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8072)
    args = parser.parse_args()
    directory = Path(__file__).resolve().parents[1] / "build" / "web"
    if not (directory / "index.html").is_file():
        parser.error("No web build found; run bash tools/export_web.sh first.")
    with ThreadingHTTPServer(("127.0.0.1", args.port), partial(GameHandler, directory=str(directory))) as server:
        print(f"Local game: http://127.0.0.1:{args.port}/  (Ctrl-C to stop)", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
