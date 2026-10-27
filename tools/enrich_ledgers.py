"""Add extra dated sources to a ledger, with quotes cut from the live page.

The reviewer will not accept a quote that was written by hand or copied from a
summary. When a milestone needs a second document — the announcement of the day
does not name the section, or the first source turns out to be a retrospective —
this tool opens the extra URL, pulls the publication date off the page, and cuts
the sentence that names the stations the ledger needs. If the page does not
contain that sentence, nothing is added and the gap stays visible.

Config: data/official_evidence/milestone_extra_sources.json

  {"<city>": {"<chapterId>": {"chapterKind": "opening",
                              "sources": [{"url": "...", "kind": "opening_day",
                                           "locator": "...", "need": ["A站", "B站"]}]}}}
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import page_cache
from build_history_ledgers import published_date, sentences

CONFIG = 'data/official_evidence/milestone_extra_sources.json'
LEDGER = 'data/official_evidence/history_two_source_{city}_2026-10-29.json'


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def write(name, value):
    (ROOT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def cut(text, need, date):
    """Shortest sentence that names every required station and the date."""
    for want_date in (True, False):
        best = ''
        for sentence in sentences(text):
            if not all(name in sentence for name in need):
                continue
            if want_date and not (date in sentence or f'{int(date[5:7])}月{int(date[8:10])}日' in sentence):
                continue
            if not best or len(sentence) < len(best):
                best = sentence
        if best:
            return best
    for sentence in sentences(text):
        if date in sentence or f'{int(date[5:7])}月{int(date[8:10])}日' in sentence:
            return sentence
    return ''


def main(city):
    config = read(CONFIG).get(city, {})
    ledger = read(LEDGER.format(city=city))
    changed = 0
    for entry in ledger['milestones']:
        rules = config.get(entry['chapterId'])
        if not rules:
            continue
        if rules.get('chapterKind'):
            entry['chapterKind'] = rules['chapterKind']
        for patch in rules.get('rewrite', []):
            for source in entry['dateSources']:
                if source['url'] != patch['url']:
                    continue
                for field in ('kind', 'edition', 'publicationDate', 'locator', 'basisNote'):
                    if field in patch:
                        source[field] = patch[field]
                changed += 1
                print(f'  REWROTE {entry["chapterId"]} {patch["url"]}')
        known = {source['url'] for source in entry['dateSources']}
        for rule in rules.get('sources', []):
            url = rule['url']
            if rule.get('refresh'):
                entry['dateSources'] = [source for source in entry['dateSources'] if source['url'] != url]
            page = page_cache.load(url)
            if page['status'] != 200:
                print(f'  FAIL {entry["chapterId"]} {page["status"]} {url}')
                continue
            publication, basis = published_date(page, url)
            quote = cut(page['text'], rule.get('need', []), entry['date'])
            if not publication or not quote:
                print(f'  MISS {entry["chapterId"]} pub={publication or "-"} quote={bool(quote)} {url}')
                continue
            existing = [source['quote'] for source in entry['dateSources'] if source['url'] == url]
            if quote in existing:
                continue
            entry['dateSources'].append({
                'url': url, 'publicationDate': publication, 'publicationBasis': basis,
                'kind': rule.get('kind', 'opening_day'),
                'locator': rule.get('locator', ''), 'quote': quote,
                'httpStatus': page['status'], 'sha256': page['sha256'],
            })
            known.add(url)
            changed += 1
            print(f'  ADDED {entry["chapterId"]} pub={publication} ({basis}) {url}')
    if changed:
        write(LEDGER.format(city=city), ledger)
    print(f'{city}: {changed} source(s) added')


if __name__ == '__main__':
    for city in sys.argv[1:]:
        main(city)
