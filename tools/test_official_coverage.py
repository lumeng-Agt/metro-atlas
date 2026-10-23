#!/usr/bin/env python3
import argparse
import json
import sys
from official_coverage import audit

def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    result = audit()
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        for city, row in result['cities'].items():
            print(f"{'PASS' if row['ok'] else 'FAIL'} {city}: {len(row['errors'])} issue(s)")
            for error in row['errors']:
                print('  ' + error)
    return 0 if result['ok'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
