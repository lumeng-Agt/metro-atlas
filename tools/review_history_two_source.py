"""Two-source review of the historical milestones, city by city.

A milestone makes two separate claims and needs two separate documents:

  * the **date** of the opening  -> a dated official announcement whose text
    names that date (or, for a reconciliation chapter, an official roster
    published at or before the cutoff that shows the network state);
  * the **station order**        -> the operator/government station roster,
    which is a different document from the announcement.

The earlier review only re-opened each milestone's own `source`. Official
announcements usually give endpoints and counts, never a station-by-station
list, so almost every order came back "not checkable" even when the order was
in fact right. This script closes that gap by aligning every group against the
official roster and *recomputing* the alignment, so the ledger cannot simply
assert a verdict.

Alignment kinds, all recomputed here:

  exact          the group equals the official order (either direction);
  contiguous     the group is a slice of the official order (an extension
                 added later stations at one end); the two endpoints of the
                 slice have to be named by a dated source, so a section that
                 stops one stop short cannot pass as the published section;
  subsequence    the group omits stations that the dated source says were not
                 open yet — each omitted name has to appear in that source;
  existing_lead  the group starts with through-running stations that belong to
                 another line's roster (Shenzhen line 8 runs through line 2's
                 莲塘) — each leading name has to exist in another roster;
  loop_exact     the group is the whole ring, at any published start point;
  loop_subsequence
                 the group is the ring minus named gaps (Beijing line 10 opened
                 as an arc before 角门东 existed);
  through        the group is two published lines run through at a shared
                 station (Beijing line 4 + Daxing line).

Three normalisations are allowed, each with its own dated official source:

  nameAliases      a station renamed after the milestone (上海 8 号线
                   航天博物馆 -> 沈杜公路), applied only up to `until`;
  lineRenumbering  a line renumbered after the milestone (成都 17 号线 became
                   19 号线 in 2023), applied only up to `until`;
  throughService   two published orders joined at a named station.

Anything else is `unaligned` and the milestone stays unverified.
"""
import datetime
import glob
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEDGER_DIR = 'data/official_evidence'
OUT = 'docs/history-two-source-2026-10-29.json'
TARGETS = 'data/official_targets_2026-10-01.json'
CITIES = ('shenzhen', 'shanghai', 'beijing', 'guangzhou', 'chengdu')
DATE_TOLERANCE_DAYS = 45


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def write(name, value):
    path = ROOT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def digest(name):
    return hashlib.sha256((ROOT / name).read_bytes()).hexdigest()


def ledgers():
    """Every city ledger on disk, keyed by the city it claims to review."""
    found = {}
    for name in sorted(glob.glob(str(ROOT / LEDGER_DIR / 'history_two_source_*.json'))):
        document = json.loads(Path(name).read_text(encoding='utf-8'))
        city = document.get('city', '')
        if city in CITIES:
            found[city] = str(Path(name).relative_to(ROOT)).replace('\\', '/')
    return found


# ---------------------------------------------------------------- normalising

def apply_aliases(names, aliases, date):
    """Rename a station only while the old name was the official one."""
    if not aliases:
        return list(names)
    lookup = {}
    for alias in aliases:
        if date and str(alias.get('until', '')) and date > str(alias['until']):
            continue
        lookup[str(alias['from'])] = str(alias['to'])
    return [lookup.get(name, name) for name in names]


def apply_renumbering(rows, renumbering, date):
    """Point a group at the line number the roster publishes today."""
    if not renumbering:
        return rows
    lookup = {}
    for rule in renumbering:
        if date and str(rule.get('until', '')) and date > str(rule['until']):
            continue
        lookup[str(rule['from'])] = str(rule['to'])
    return [{**row, 'line': lookup.get(str(row.get('line', '')), str(row.get('line', '')))} for row in rows]


def alias_errors(ledger, rosters):
    """An alias has to rename something the roster no longer publishes."""
    errors = []
    for alias in ledger.get('nameAliases', []):
        label = f"{alias.get('from')}->{alias.get('to')}"
        if not alias.get('from') or not alias.get('to') or alias.get('from') == alias.get('to'):
            errors.append(f'{label}: alias does not rename anything')
        if not str(alias.get('source', '')).startswith('https://'):
            errors.append(f'{label}: alias has no dated official source')
        if not str(alias.get('until', '')):
            errors.append(f'{label}: alias has no end date')
        line = str(alias.get('line', ''))
        patterns = rosters.get(line, [])
        if line and not patterns:
            errors.append(f'{label}: alias names a line the roster does not publish')
        elif line:
            flat = [name for pattern in patterns for name in pattern]
            if str(alias['to']) not in flat:
                errors.append(f'{label}: the new name is not in the roster')
            if str(alias['from']) in flat:
                errors.append(f'{label}: the roster still publishes the old name')
    for rule in ledger.get('lineRenumbering', []):
        label = f"{rule.get('from')}->{rule.get('to')}"
        if not str(rule.get('source', '')).startswith('https://') or not str(rule.get('until', '')):
            errors.append(f'{label}: renumbering has no dated official source')
        if str(rule.get('to')) not in rosters:
            errors.append(f'{label}: the new line number is not in the roster')
        if str(rule.get('from')) in rosters and rule.get('from') != rule.get('to'):
            errors.append(f'{label}: the roster still publishes the old line number')
    return errors


# ---------------------------------------------------------------- alignment

def group_line_number(group):
    """The line number a chapter group claims, when its identifier carries one."""
    for field in ('historicalLineId', 'mapRouteId'):
        match = re.search(r'-(?:line|r)(\d+)(?:$|-)', str(group.get(field, '')))
        if match:
            return int(match.group(1))
    return None


def _line_number(label):
    match = re.search(r'(\d+)', label)
    return int(match.group(1)) if match else None


def _subsequence(seq, official):
    """Return (ok, interior_gaps, tail, head_size).

    Only stations that sit *between* two stations of the group count as gaps.
    Stations before the group's first station or after its last one are outside
    the section the milestone describes, and the endpoint rule already pins the
    section down.
    """
    position = 0
    gaps = []
    started = False
    head = 0
    for name in seq:
        while position < len(official) and official[position] != name:
            if started:
                gaps.append(official[position])
            else:
                head += 1
            position += 1
        if position >= len(official):
            return False, [], [], 0
        started = True
        position += 1
    return True, gaps, official[position:], head


def alignment(names, official):
    """Try both service directions: a chapter may list the order either way."""
    for reverse, candidate in ((False, list(names)), (True, list(reversed(names)))):
        if candidate == official:
            return 'exact', {'reverse': reverse}
        size = len(candidate)
        for start in range(len(official) - size + 1):
            if official[start:start + size] == candidate:
                return 'contiguous', {'start': start, 'reverse': reverse,
                                      'endpoints': [candidate[0], candidate[-1]],
                                      'spans': start == 0 and start + size == len(official)}
        ok, gaps, tail, head = _subsequence(candidate, official)
        if ok:
            return 'subsequence', {'skipped': gaps, 'tail': tail, 'reverse': reverse,
                                   'endpoints': [candidate[0], candidate[-1]],
                                   'spans': head == 0 and not tail}
        lead = []
        rest = list(candidate)
        while rest and rest[0] not in official:
            lead.append(rest.pop(0))
        if lead and rest:
            ok, gaps, tail, head = _subsequence(rest, official)
            if ok:
                return 'existing_lead', {'lead': lead, 'skipped': gaps, 'tail': tail,
                                         'reverse': reverse,
                                         'endpoints': [candidate[0], candidate[-1]],
                                         'spans': False}
    return 'unaligned', {}


def loop_alignment(names, official):
    """A ring publishes an arbitrary start point; a group is a rotation of it."""
    size = len(official)
    if size < 3 or len(names) > size:
        return 'unaligned', {}
    for start in range(size):
        rotated = official[start:] + official[:start]
        for reverse in (False, True):
            candidate = rotated if not reverse else list(reversed(rotated))
            if candidate == names:
                return 'loop_exact', {'start': start, 'reverse': reverse}
            ok, gaps, tail, head = _subsequence(names, candidate)
            if ok and gaps:
                return 'loop_subsequence', {'start': start, 'reverse': reverse, 'skipped': gaps,
                                            'endpoints': [names[0], names[-1]], 'spans': False}
    return 'unaligned', {}


def through_alignment(names, first, second, join):
    """Two published lines run through: the group is both orders end to end."""
    pairs = []
    for left in first:
        for right in second:
            if left[-1] == right[0] == join:
                pairs.append(left + right[1:])
            if right[-1] == left[0] == join:
                pairs.append(right + left[1:])
    for candidate in pairs:
        if list(names) == candidate:
            return 'through', {'join': join}
        if list(reversed(names)) == candidate:
            return 'through', {'join': join, 'reverse': True}
    return 'unaligned', {}


def resolve_alignment(group, row, rosters, date, aliases):
    """Normalise the group, then take the tightest published order that fits.

    Trying the patterns in order and stopping at the first loose match would let
    a branch pattern win by accident (Shanghai line 11 publishes both 嘉定北 and
    花桥 starts), so every pattern is scored and the tightest alignment wins.
    """
    names = apply_aliases(list(group.get('stationNames', [])), aliases, date)
    label = str(row.get('line', ''))
    if isinstance(row.get('lines'), list) and len(row['lines']) == 2:
        first_label, second_label = (str(x) for x in row['lines'])
        if not all(name in rosters for name in (first_label, second_label)):
            return 'unaligned', {'reason': f'no roster for {row["lines"]}'}
        return through_alignment(names, rosters[first_label], rosters[second_label],
                                 str(row.get('join', '')))
    patterns = rosters.get(label, [])
    if not patterns:
        return 'unaligned', {'reason': f'no roster for {label}'}
    rank = {'exact': 0, 'loop_exact': 0, 'contiguous': 1, 'subsequence': 2,
            'loop_subsequence': 2, 'existing_lead': 3}
    best = None
    for pattern in patterns:
        kind, detail = alignment(names, pattern)
        if kind == 'unaligned':
            kind, detail = loop_alignment(names, pattern)
        if kind == 'unaligned':
            continue
        if best is None or rank[kind] < rank[best[0]]:
            best = (kind, detail)
    return best if best else ('unaligned', {'reason': f'no published order matches {label}'})


def name_variants(name, aliases, date):
    """Every spelling a document published that day could legitimately use."""
    forms = [name]
    for alias in aliases or []:
        if str(alias.get('to', '')) != name:
            continue
        if date and str(alias.get('until', '')) and date > str(alias['until']):
            continue
        forms.append(str(alias['from']))
    return forms


def _with_junction(names, fresh):
    """Keep the already-open station the new section starts from.

    An announcement words a new section as "from the existing A to the new B",
    so the section's own start is the junction, not the first brand-new stop.
    """
    if not fresh or len(fresh) < 2:
        return fresh
    try:
        start = names.index(fresh[0])
    except ValueError:
        return fresh
    return [names[start - 1]] + fresh if start > 0 else fresh


def build_increments(city_milestones, ledger):
    """What each chapter actually added, line by line.

    A chapter's group is a *service pattern* of the line as it stood that day,
    and a line may publish several patterns (Shanghai line 11 runs both from
    嘉定北 and from 花桥). Taking the difference per pattern therefore
    reports nonsense: a brand-new pattern looks like a whole new line. The
    increment is worked out per line -- the stations this chapter has that no
    earlier chapter on the same line had -- and each pattern then reports the
    part of that increment it contains.
    """
    aliases = ledger.get('nameAliases', [])
    seen = {}
    line_increments = {}
    for milestone in sorted(city_milestones, key=lambda m: str(m.get('date', ''))):
        date = str(milestone.get('date', ''))
        per_line = {}
        for group in milestone.get('groups', []):
            line = str(group.get('historicalLineId') or group.get('id', ''))
            names = apply_aliases(list(group.get('stationNames', [])), aliases, date)
            bucket = per_line.setdefault(line, [])
            bucket.extend(name for name in names if name not in bucket)
        chapter_increments = {}
        for line, names in per_line.items():
            earlier = seen.setdefault(line, set())
            chapter_increments[line] = [name for name in names if name not in earlier]
            earlier.update(names)
        line_increments[str(milestone.get('chapterId', ''))] = chapter_increments
    increments = {}
    for milestone in city_milestones:
        date = str(milestone.get('date', ''))
        chapter = line_increments.get(str(milestone.get('chapterId', '')), {})
        per_group = {}
        for group in milestone.get('groups', []):
            line = str(group.get('historicalLineId') or group.get('id', ''))
            names = apply_aliases(list(group.get('stationNames', [])), aliases, date)
            fresh = [name for name in chapter.get(line, []) if name in names]
            reviewed = group.get('constructionStationNames')
            reviewed_names = apply_aliases(list(reviewed), aliases, date) if reviewed else []
            if reviewed_names and set(reviewed_names) != set(names):
                fresh = reviewed_names
            else:
                fresh = _with_junction(names, fresh)
            per_group[str(group.get('id', ''))] = fresh
        increments[str(milestone.get('chapterId', ''))] = per_group
    return increments


def order_errors(milestone, entry, rosters, ledger):
    """Recompute every declared alignment against the official rosters."""
    errors = []
    date = str(milestone.get('date', ''))
    aliases = ledger.get('nameAliases', [])
    declared_rows = apply_renumbering(entry.get('orders', []), ledger.get('lineRenumbering', []), date)
    declared = {row['groupId']: row for row in declared_rows}
    groups = milestone.get('groups', [])
    if len(declared) != len(groups):
        errors.append(f'{entry["chapterId"]}: {len(groups)} groups but {len(declared)} alignments declared')
    quotes = ' '.join(str(source.get('quote', '')) for source in entry.get('dateSources', []))
    for group in groups:
        group_id = str(group.get('id', ''))
        row = declared.get(group_id)
        if row is None:
            errors.append(f'{entry["chapterId"]}: group {group_id} has no declared alignment')
            continue
        names = apply_aliases(list(group.get('stationNames', [])), aliases, date)
        kind, detail = resolve_alignment(group, row, rosters, date, aliases)
        wanted_number = group_line_number(group)
        declared_number = _line_number(str(row.get('line', '')))
        if wanted_number is not None and declared_number is not None and wanted_number != declared_number:
            errors.append(f'{entry["chapterId"]}: {group_id} is line {wanted_number} but the ledger checks line '
                          f'{row.get("line")}')
        if kind != row.get('expect'):
            errors.append(f'{entry["chapterId"]}: {group_id} aligns as {kind}, ledger says {row.get("expect")}'
                          f'{(" (" + detail["reason"] + ")") if detail.get("reason") else ""}')
            continue
        if kind in ('contiguous', 'subsequence', 'loop_subsequence', 'existing_lead'):
            # What the dated document has to describe is the *increment*: the
            # section that opened that day, not the whole line as it then stood.
            # The group is the line's state, so its two ends can be termini that
            # opened years earlier; the announcement names the new section.
            if entry.get('chapterKind', 'opening') == 'opening':
                increment = ledger.get('_increments', {}).get(
                    entry['chapterId'], {}).get(group_id)
                if increment is None:
                    increment = group.get('stationNames') or []
                # An empty increment means this pattern opened nothing that day
                # (only the other branch of the line did), so there is no new
                # section to name.
                endpoints = [increment[0], increment[-1]] if increment else []
                # The announcement carries the name the station had on the day,
                # so every historical spelling of an endpoint is accepted too.
                missing = [name for name in dict.fromkeys(endpoints)
                           if not any(form in quotes for form in name_variants(name, aliases, date))]
                if missing:
                    errors.append(f'{entry["chapterId"]}: {group_id} opened section endpoints {missing} are not named by any dated source')
        if kind in ('subsequence', 'loop_subsequence', 'existing_lead'):
            later = later_station_index(ledger, milestone, entry)
            missing = [name for name in detail.get('skipped', [])
                       if name not in quotes and name not in later]
            if missing:
                errors.append(f'{entry["chapterId"]}: {group_id} omits {missing} with no dated statement')
        if kind == 'existing_lead':
            for name in detail['lead']:
                elsewhere = [station for key, patterns in rosters.items() if key != row.get('line')
                             for pattern in patterns for station in pattern]
                if name not in elsewhere:
                    errors.append(f'{entry["chapterId"]}: {group_id} leads with {name}, which no other roster lists')
    return errors


def later_station_index(ledger, milestone, entry):
    """Stations that are inside the section but only opened on a later date.

    A 2009 opening announcement cannot name a station that was built in 2020, so
    an interior gap is justified either by the announcement itself or by a
    *later* chapter of the same city that opens exactly that station. Both
    directions are checked: the referenced chapter has to exist, has to be
    later, and has to contain the station.
    """
    known = {}
    for record in ledger.get('laterStations', []):
        chapter_id = str(record.get('chapterId', ''))
        city_milestones = {str(m.get('chapterId', '')): m for m in ledger['_milestones']}
        target = city_milestones.get(chapter_id)
        station = str(record.get('station', ''))
        if target is None:
            continue
        if str(target.get('date', '')) <= str(milestone.get('date', '')):
            continue
        if any(station in group.get('stationNames', []) for group in target.get('groups', [])):
            known[station] = chapter_id
    return known


def later_station_errors(ledger):
    """Every declared later station must point at a real, later chapter."""
    errors = []
    milestones = {str(m.get('chapterId', '')): m for m in ledger['_milestones']}
    for record in ledger.get('laterStations', []):
        station = str(record.get('station', ''))
        chapter_id = str(record.get('chapterId', ''))
        target = milestones.get(chapter_id)
        if not station or target is None:
            errors.append(f'later station {station or "-"}: no such chapter {chapter_id}')
            continue
        if not str(record.get('source', '')).startswith('https://'):
            errors.append(f'later station {station}: no dated official source')
        if not any(station in group.get('stationNames', []) for group in target.get('groups', [])):
            errors.append(f'later station {station}: chapter {chapter_id} does not open it')
    return errors


# ---------------------------------------------------------------- dates

def _short_date(date):
    return f'{int(date[5:7])}月{int(date[8:10])}日'


def _states_date(quote, date):
    return date in quote or _short_date(date) in quote


def _states_full_date(quote, date):
    year, month, day = date.split('-')
    return (date in quote
            or f'{year}年{int(month)}月{int(day)}日' in quote
            or f'{year} 年 {int(month)} 月 {int(day)} 日' in quote)


def _is_government(url):
    from urllib.parse import urlparse
    host = (urlparse(url).hostname or '').lower()
    return host.endswith('.gov.cn') or host.endswith('.gov') or host.endswith('.mil.cn')


def date_errors(entry, ledger=None):
    """A dated source has to be official, dated, and quote real text.

    A report published a few days after the opening is still a contemporaneous
    source, so a short lag is allowed when the quote names the day; a document
    from a later year is not. A reconciliation chapter is the one case that
    needs no opening announcement: it reproduces a network state the roster
    publishes at or before the cutoff.
    """
    errors = []
    chapter = entry.get('chapterId', '')
    kind = entry.get('chapterKind', 'opening')
    sources = entry.get('dateSources', [])
    if not sources:
        return [f'{chapter}: no dated source']
    date = str(entry.get('date', ''))
    for source in sources:
        if not str(source.get('url', '')).startswith('https://'):
            errors.append(f'{chapter}: date source is not https')
        if source.get('kind') == 'official_chronicle':
            # A chronicle volume records the day inside the year it covers, so
            # the volume's coverage year pins the year and the quote pins the day.
            if str(source.get('edition', '')) != date[:4]:
                errors.append(f'{chapter}: chronicle edition does not cover {date[:4]}')
            if not _states_date(str(source.get('quote', '')), date):
                errors.append(f'{chapter}: chronicle quote never states {date}')
            continue
        if source.get('kind') == 'official_history':
            # A government publication that prints the full date is self-dating;
            # it is not contemporaneous, so it is held to the stricter rule.
            if not _is_government(str(source.get('url', ''))):
                errors.append(f'{chapter}: official history is not on a government domain')
            if not _states_full_date(str(source.get('quote', '')), date):
                errors.append(f'{chapter}: official history never prints the full date {date}')
            continue
        if not str(source.get('publicationDate', '')) or not str(source.get('quote', '')):
            errors.append(f'{chapter}: date source has no publication date or quote')
    if kind == 'reconciliation':
        current = [source for source in sources
                   if source.get('kind') == 'network_state'
                   and str(source.get('publicationDate', '')) <= date]
        if not current:
            errors.append(f'{chapter}: no network-state source published at or before {date}')
        return errors
    if kind == 'inference':
        # Nothing published on the day names the change, so the ledger has to
        # carry two dated official documents that pin it between them.
        dated = [source for source in sources if str(source.get('publicationDate', ''))
                 and str(source.get('quote', ''))]
        if len(dated) < 2:
            errors.append(f'{chapter}: an inference needs two dated official documents')
        if not any(str(source['publicationDate']) == date or _states_date(str(source['quote']), date)
                   for source in dated):
            errors.append(f'{chapter}: no document pins {date}')
        return errors
    if any(source.get('kind') in ('official_chronicle', 'official_history') for source in sources):
        return errors
    if kind == 'rename':
        # A rename chapter carries the whole line as it stood, so the section
        # rule does not apply; what it does have to show is the renamed station.
        renamed = [str(alias.get('from', '')) for alias in (ledger or {}).get('nameAliases', [])
                   if str(alias.get('chapterId', '')) == chapter]
        if not renamed:
            errors.append(f'{chapter}: rename chapter has no documented rename')
        for name in renamed:
            if name not in ' '.join(str(source.get('quote', '')) for source in sources):
                errors.append(f'{chapter}: no source names the renamed station {name}')
        return errors
    dated = [source for source in sources if source.get('kind') == 'opening_day'
             and str(source.get('publicationDate', ''))]
    if not dated:
        errors.append(f'{chapter}: no opening-day announcement')
        return errors
    for source in dated:
        publication = str(source['publicationDate'])
        lag = abs((datetime.date.fromisoformat(publication) - datetime.date.fromisoformat(date)).days)
        if lag > DATE_TOLERANCE_DAYS:
            errors.append(f'{chapter}: announcement published {publication}, {lag} days from {date}')
    # One of the announcements has to actually state the day; the others only
    # carry the section wording, so they need not repeat it.
    if not any(_states_date(str(source.get('quote', '')), date) for source in dated):
        errors.append(f'{chapter}: no announcement states {date}')
    return errors


# ---------------------------------------------------------------- entry point

def review_city(city_id, name, targets):
    ledger = read(name)
    rosters = {}
    for source_id, source in ledger.get('orderSources', {}).items():
        path = source['file']
        actual = digest(path)
        if actual != source.get('sha256'):
            raise SystemExit(f'{city_id}: {source_id} hash {actual} does not match the ledger')
        rosters.update(load_rosters(path))
    city = targets['cities'][city_id]
    milestones = {str(m.get('chapterId', '')): m for m in city.get('historicalMilestones', [])}
    ledger['_milestones'] = list(city.get('historicalMilestones', []))
    ledger['_increments'] = build_increments(ledger['_milestones'], ledger)
    rows = []
    errors = alias_errors(ledger, rosters) + later_station_errors(ledger)
    for entry in ledger.get('milestones', []):
        chapter_id = str(entry.get('chapterId', ''))
        milestone = milestones.get(chapter_id)
        issues = []
        if milestone is None:
            issues.append(f'{chapter_id}: no such milestone in the target list')
        else:
            if str(milestone.get('date', '')) != str(entry.get('date', '')):
                issues.append(f'{chapter_id}: ledger date differs from the target list')
            issues.extend(date_errors(entry, ledger))
            issues.extend(order_errors(milestone, entry, rosters, ledger))
        rows.append({**entry, 'verdict': 'verified' if not issues else 'unverified', 'issues': issues})
    covered = {str(entry.get('chapterId', '')) for entry in ledger.get('milestones', [])}
    for chapter_id in milestones:
        if chapter_id not in covered:
            rows.append({'chapterId': chapter_id, 'verdict': 'unverified',
                         'issues': [f'{chapter_id}: not covered by the two-source ledger']})
    verified = [row for row in rows if row['verdict'] == 'verified']
    status = 'verified' if len(verified) == len(rows) and rows and not errors else 'pending'
    return rows, verified, status, errors


def load_rosters(path):
    """Rosters keyed by the line label the roster publishes."""
    import official_rosters
    document = json.loads((ROOT / path).read_text(encoding='utf-8'))
    for city, (source, _) in official_rosters.SOURCES.items():
        if source == path:
            return official_rosters.LOADERS[city](document)
    raise SystemExit(f'{path}: no loader knows this roster shape')


def main():
    targets = read(TARGETS)
    combined = {'schemaVersion': 1, 'reviewedAt': '2026-10-29', 'cities': {}}
    changed = 0
    for city_id, name in ledgers().items():
        rows, verified, status, ledger_errors = review_city(city_id, name, targets)
        failed = [row for row in rows if row['verdict'] != 'verified']
        note = (f'两源复核{city_id}的{len(rows)}条历史里程碑：日期用带日期的官方公告，站序用官方逐线站表，'
                f'{len(verified)}条两项都对上。')
        if failed:
            note += '未通过：' + '；'.join(
                f'{row["chapterId"]}（{" / ".join(row["issues"][:2])}）' for row in failed[:4])
            note += f'。未通过项不标已核对，明细见 {OUT}。'
        if ledger_errors:
            note += '台账本身有问题：' + '；'.join(ledger_errors[:3]) + '。'
        combined['cities'][city_id] = {
            'milestones': rows, 'verifiedCount': len(verified),
            'unverifiedCount': len(failed), 'ledgerErrors': ledger_errors,
            'verdict': 'complete' if status == 'verified' else 'incomplete',
            'note': note,
        }
        city = targets['cities'][city_id]
        if city.get('historyReviewStatus') == status and city.get('historyReviewNote') == note:
            print(f'ALREADY_RECORDED {city_id} {len(verified)}/{len(rows)}')
            continue
        city['historyReviewStatus'] = status
        city['historyReviewNote'] = note
        changed += 1
        print(f'{"VERIFIED" if status == "verified" else "STILL_PENDING"} {city_id} {len(verified)}/{len(rows)}')
        for error in ledger_errors[:4]:
            print('  ! ', error)
        for row in failed[:8]:
            print('  -', row['chapterId'], '|', ' / '.join(row['issues'][:2]))
    write(OUT, combined)
    print('LEDGER', OUT)
    if changed:
        write(TARGETS, targets)
    else:
        print('ALREADY_RECORDED no history status changed')


if __name__ == '__main__':
    main()
