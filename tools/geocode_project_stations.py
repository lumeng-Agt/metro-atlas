#!/usr/bin/env python3
"""Resolve proposed station area labels to OSM place coordinates for review.

This helper only suggests coordinates. It never writes game data. Every result
must be checked against the cited project alignment before it is added to a
playable plan.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.parse
import urllib.request


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("city")
    parser.add_argument("names", nargs="+")
    args = parser.parse_args()
    results = []
    for index, name in enumerate(args.names):
        if index:
            time.sleep(1.1)
        query = urllib.parse.urlencode({"q": f"{name}站, {args.city}, 中国", "format": "jsonv2", "limit": 3})
        request = urllib.request.Request(
            f"https://nominatim.openstreetmap.org/search?{query}",
            headers={"User-Agent": "MetroAtlasDesktop/0.25 project-station-review"},
        )
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                rows = json.loads(response.read().decode("utf-8"))
            results.append({"name": name, "results": rows})
        except Exception as exc:  # Keep going so one miss does not discard the batch.
            results.append({"name": name, "error": str(exc), "results": []})
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
