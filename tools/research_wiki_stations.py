#!/usr/bin/env python3
"""Print station-table rows from a public wiki page for content review.

Research helper only: it fetches one page and prints cell text so a human can
copy an official station order into a project spec. It never writes game data.
"""
from __future__ import annotations

import gzip
import re
import sys
import urllib.parse
import urllib.request


def fetch(url: str) -> str:
    request = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 MetroAtlasDesktop/0.25 research",
        "Accept-Encoding": "gzip",
    })
    with urllib.request.urlopen(request, timeout=45) as response:
        raw = response.read()
        if response.headers.get("Content-Encoding") == "gzip":
            raw = gzip.decompress(raw)
        return raw.decode("utf-8", "replace")


def cell_text(cell: str) -> str:
    cell = re.sub(r"<sup[\s\S]*?</sup>", "", cell)
    cell = re.sub(r"<[^>]+>", " ", cell)
    cell = cell.replace("&nbsp;", " ").replace("&#91;", "[").replace("&#93;", "]")
    return re.sub(r"\s+", " ", cell).strip()


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    url = sys.argv[1]
    html = fetch(url)
    tables = re.findall(r'<table[^>]*class="[^"]*wikitable[^"]*"[\s\S]*?</table>', html)
    for table_index, table in enumerate(tables):
        rows = re.findall(r"<tr[^>]*>([\s\S]*?)</tr>", table)
        if len(rows) < 3:
            continue
        print(f"--- table {table_index} rows {len(rows)}")
        for row in rows:
            cells = [cell_text(cell) for cell in re.findall(r"<t[hd][^>]*>([\s\S]*?)</t[hd]>", row)]
            if any(cells):
                print(" | ".join(cells))


if __name__ == "__main__":
    main()
