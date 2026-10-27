"""Assemble a two-source ledger for one city from live documents.

The ledger records two separate facts per milestone and never conflates them:

  * a **dated official document** that states the opening date;
  * a **published station roster** that fixes the station order.

Quotes are cut out of the fetched page text by rule, not written by hand: the
builder looks for the sentence that states the date, and for each section the
sentence that names both of its endpoints. If no such sentence exists the quote
stays empty and the review says so, instead of the ledger inventing prose.

Usage:  python tools/build_history_ledgers.py <city> [<city> ...]
"""
import datetime
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import official_rosters
import page_cache
from review_history_two_source import alignment, loop_alignment, resolve_alignment

REVIEWS = {
    'shenzhen': 'data/official_evidence/history_review_shenzhen_shanghai_2026-10-28.json',
    'shanghai': 'data/official_evidence/history_review_shenzhen_shanghai_2026-10-28.json',
    'beijing': 'data/official_evidence/history_review_beijing_guangzhou_2026-10-28.json',
    'guangzhou': 'data/official_evidence/history_review_beijing_guangzhou_2026-10-28.json',
    'chengdu': 'data/official_evidence/history_review_chengdu_2026-10-28.json',
}
ROSTER_FILES = {city: source for city, (source, _) in official_rosters.SOURCES.items()}
ROSTER_URLS = {
    'shenzhen': ('https://fgw.sz.gov.cn/zwgk/qt/tzgg/content/post_12849099.html', '2026-06-22'),
    'shanghai': ('https://m.shmetro.com/interface/metromap/metromap.aspx?func=fltime&line=1', '2026-10-23'),
    'beijing': ('https://www.bjmoa.cn/metroLineList.html?sline=1', '2026-10-25'),
    'guangzhou': ('https://www.gzmtr.com/ygwm/gsgk/xxjs/', '2026-10-25'),
    'chengdu': ('https://www.chengdurail.com/', '2026-10-23'),
}
ALIAS_FILE = 'data/official_evidence/station_name_aliases.json'
BASIS_FILE = 'data/official_evidence/milestone_date_basis.json'
DATE_PATTERNS = [
    re.compile(r'name=["\']?(?:PubDate|publishdate|pubdate)["\']?[^>]*?content=["\']?(\d{4})-(\d{1,2})-(\d{1,2})', re.I),
    re.compile(r'property=["\']?article:published_time["\']?[^>]*?content=["\']?(\d{4})-(\d{1,2})-(\d{1,2})', re.I),
]
MARKED = re.compile(r'(?:发布时间|发布日期|发布于|发表时间|成文日期|公开日期)[：:\s]*(\d{4})-(\d{1,2})-(\d{1,2})')
MARKED_CN = re.compile(r'(?:发布时间|发布日期|发布于|发表时间|成文日期|公开日期)[：:\s]*(\d{4})年(\d{1,2})月(\d{1,2})日')
URL_DATE = [re.compile(r'/(20\d{2})(\d{2})(\d{2})/'), re.compile(r'/t(20\d{2})(\d{2})(\d{2})_'),
            re.compile(r'/(20\d{2})/(\d{2})/(\d{2})/'), re.compile(r'/(20\d{2})/(\d{2})-(\d{2})/')]
DATELINE = re.compile(r'(20\d{2})\s*[-年/]\s*(\d{1,2})\s*[-月/]\s*(\d{1,2})')


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def write(name, value):
    path = ROOT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def squash(text):
    return re.sub(r'\s+', '', text or '')


def sentences(text):
    parts = re.split(r'(?<=[。！？；!?;])', re.sub(r'\s+', ' ', text or ''))
    return [part.strip() for part in parts if len(part.strip()) >= 8]


def date_forms(date):
    year, month, day = date.split('-')
    return [date, f'{year}年{int(month)}月{int(day)}日', f'{int(month)}月{int(day)}日',
            f'{year}年{int(month)}月{int(day)}', f'{int(month)}/{int(day)}']


def stated_date(text, date):
    plain = squash(text)
    return any(form in plain for form in date_forms(date))


def published_date(row, url):
    """The date the document itself declares, most specific signal first."""
    for pattern in (MARKED, MARKED_CN):
        match = pattern.search(squash(row['text']))
        if match:
            return _iso(match.groups()), 'visible'
    for pattern in DATE_PATTERNS:
        match = pattern.search(row['html'])
        if match:
            return _iso(match.groups()), 'meta'
    for pattern in URL_DATE:
        match = pattern.search(url)
        if match:
            return _iso(match.groups()), 'url'
    # A news page that declares no date still prints one in its dateline, above
    # the first paragraph. Only the opening of the text is considered, so a
    # date buried in the story is not mistaken for the publication date.
    head = row['text'][:1200]
    match = DATELINE.search(head)
    if match:
        return _iso(match.groups()), 'dateline'
    return '', ''


def _iso(groups):
    year, month, day = (int(value) for value in groups)
    if not (1 <= month <= 12 and 1 <= day <= 31):
        return ''
    return f'{year:04d}-{month:02d}-{day:02d}'


def date_quote(text, date, fallback_names):
    """Cut out the sentence that states the date, else a window around it."""
    for sentence in sentences(text):
        if stated_date(sentence, date):
            return sentence
    plain = re.sub(r'\s+', ' ', text or '')
    for form in date_forms(date):
        index = plain.find(form)
        if index >= 0:
            return plain[max(0, index - 40):index + len(form) + 40].strip()
    for name in fallback_names:
        for sentence in sentences(text):
            if name and name in sentence:
                return sentence
    return ''


def section_quote(text, first, last):
    """Cut out the shortest span of the page that names both endpoints."""
    best = ''
    for sentence in sentences(text):
        if first in sentence and last in sentence:
            if not best or len(sentence) < len(best):
                best = sentence
    if best:
        return best
    plain = re.sub(r'\s+', ' ', text or '')
    start = plain.find(first)
    if start < 0:
        return ''
    end = plain.find(last, start + len(first))
    if end < 0 or end - start > 220:
        return ''
    return plain[start:end + len(last)].strip()


def line_of_group(group):
    route = str(group.get('mapRouteId', '')) or str(group.get('historicalLineId', ''))
    match = re.search(r'-r(\d+)', route) or re.search(r'-line(\d+)', route)
    return int(match.group(1)) if match else None


def roster_label(rosters, names, group):
    """Pick the published line whose order the group reproduces."""
    wanted = line_of_group(group)
    best = None
    for label, patterns in rosters.items():
        number = re.search(r'(\d+)', label)
        number = int(number.group(1)) if number else None
        for index, pattern in enumerate(patterns):
            kind, detail = alignment(names, pattern)
            if kind == 'unaligned':
                kind, detail = loop_alignment(names, pattern)
            if kind == 'unaligned':
                continue
            score = {'exact': 0, 'loop_exact': 0, 'contiguous': 1, 'subsequence': 2,
                     'loop_subsequence': 2, 'existing_lead': 3}[kind]
            penalty = 0 if (wanted is None or number == wanted) else 10
            if best is None or score + penalty < best[0]:
                best = (score + penalty, label, kind)
    return (best[1], best[2]) if best else ('', 'unaligned')


def normalise(names, aliases, date):
    lookup = {}
    for alias in aliases:
        if date and str(alias.get('until', '')) and date > str(alias['until']):
            continue
        lookup[str(alias['from'])] = str(alias['to'])
    return [lookup.get(name, name) for name in names]


def later_stations(city, ledger):
    """Interior gaps that a later chapter of the same city opens."""
    milestones = {str(m.get('chapterId', '')): m for m in city.get('historicalMilestones', [])}
    records = {}
    for entry in ledger['milestones']:
        date = str(entry['date'])
        gaps = {name for order in entry['orders'] for name in order.get('gaps', [])}
        for name in gaps:
            if name in records:
                continue
            for other in city.get('historicalMilestones', []):
                if str(other.get('date', '')) <= date:
                    continue
                if not any(name in group.get('stationNames', []) for group in other.get('groups', [])):
                    continue
                source = ''
                for row in ledger['milestones']:
                    if row['chapterId'] == other['chapterId']:
                        source = row['dateSources'][0]['url'] if row['dateSources'] else ''
                        break
                records[name] = {'station': name, 'chapterId': str(other['chapterId']),
                                 'date': str(other.get('date', '')), 'source': source}
                break
    return list(records.values())


def build(city):
    targets = read('data/official_targets_2026-10-01.json')
    campaigns = read('data/campaigns.json')
    reviews = read(REVIEWS[city])['cities'][city]['milestones']
    review_by_id = {row['chapterId']: row for row in reviews}
    rosters, _ = official_rosters.load(city)
    roster_path = ROSTER_FILES[city]
    url, publication = ROSTER_URLS[city]
    alias_config = read(ALIAS_FILE).get(city, {})
    aliases = alias_config.get('nameAliases', [])
    renumbering = alias_config.get('lineRenumbering', [])
    basis_overrides = read(BASIS_FILE).get(city, {})
    ledger = {
        'schemaVersion': 1,
        'reviewedAt': '2026-10-29',
        'city': city,
        'methodNote': ('日期与站序分开取证。日期用带日期的官方公告原文，引文由 tools/build_history_ledgers.py '
                       '从抓取到的页面文本中按规则截取，不是手写；站序用运营方/政府发布的逐线站表。'
                       '每条分组与官方站表逐站对齐，对齐方式由 tools/review_history_two_source.py 复算，'
                       '不采信台账自述。'),
        'orderSources': {
            f'{city}-operator-roster': {
                'url': url, 'publicationDate': publication, 'file': roster_path,
                'sha256': hashlib.sha256((ROOT / roster_path).read_bytes()).hexdigest(),
                'locator': '运营方/政府发布的逐线站表，按线路分表',
                'note': '这是逐线站表，与各条开通公告是两份不同文件。',
            }
        },
        'nameAliases': aliases,
        'lineRenumbering': renumbering,
        'milestones': [],
    }
    undated, blocked = [], []
    for milestone in targets['cities'][city].get('historicalMilestones', []):
        chapter_id = milestone['chapterId']
        review = review_by_id.get(chapter_id, {})
        date = str(milestone.get('date', ''))
        chapter_kind = ('reconciliation' if 'reconciliation' in chapter_id
                        else 'rename' if 'rename' in chapter_id else 'opening')
        entry = {'chapterId': chapter_id, 'date': date,
                 'chapterKind': chapter_kind,
                 'dateSources': [], 'orderSourceId': f'{city}-operator-roster', 'orders': []}
        page = page_cache.load(review.get('sourceUrl', '')) if review.get('sourceUrl') else None
        text = page['text'] if page else ''
        publication_date, basis = published_date(page, review.get('sourceUrl', '')) if page else ('', '')
        groups = milestone.get('groups', [])
        flat_names = [name for group in groups
                      for name in (list(group.get('stationNames') or [])[:1] + list(group.get('stationNames') or [])[-1:])]
        quote = date_quote(text, date, flat_names) if text else ''
        if not publication_date:
            undated.append(chapter_id)
        override = basis_overrides.get(chapter_id, {})
        source_kind = override.get('kind') or ('network_state' if entry['chapterKind'] == 'reconciliation'
                                              else 'opening_day')
        source = {
            'url': review.get('sourceUrl', ''),
            'publicationDate': publication_date,
            'publicationBasis': basis,
            'kind': source_kind,
            'locator': review.get('locator', ''),
            'quote': quote,
            'httpStatus': page['status'] if page else 0,
            'sha256': page['sha256'] if page else '',
        }
        if override.get('edition'):
            source['edition'] = str(override['edition'])
        if override.get('note'):
            source['basisNote'] = override['note']
        entry['dateSources'].append(source)
        for group in groups:
            names = normalise(list(group.get('stationNames', [])), aliases, date)
            label, _ = roster_label(rosters, names, group)
            pseudo = {'stationNames': names}
            kind, detail = resolve_alignment(pseudo, {'line': label}, rosters, date, [])
            if kind == 'contiguous':
                first, last = detail['endpoints']
                extra = section_quote(text, first, last)
                if extra and extra not in [source['quote'] for source in entry['dateSources']]:
                    entry['dateSources'].append({
                        'url': review.get('sourceUrl', ''),
                        'publicationDate': publication_date,
                        'publicationBasis': basis,
                        'kind': source_kind,
                        'locator': f'区间端点原文（{first}—{last}）',
                        'quote': extra,
                        'httpStatus': page['status'] if page else 0,
                        'sha256': page['sha256'] if page else '',
                    })
            if kind == 'unaligned':
                blocked.append(f'{chapter_id} {group.get("id")}')
            entry['orders'].append({'groupId': str(group.get('id', '')), 'line': label, 'expect': kind,
                                    'gaps': detail.get('skipped', []) if isinstance(detail, dict) else []})
        ledger['milestones'].append(entry)
    ledger['laterStations'] = later_stations(targets['cities'][city], ledger)
    write(f'data/official_evidence/history_two_source_{city}_2026-10-29.json', ledger)
    print(f'{city}: {len(ledger["milestones"])} milestones, undated={len(undated)}, unaligned={len(blocked)}')
    for chapter_id in undated:
        print('  undated', chapter_id)
    for item in blocked:
        print('  unaligned', item)


if __name__ == '__main__':
    for city in sys.argv[1:]:
        build(city)
