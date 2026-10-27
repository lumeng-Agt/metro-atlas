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
                 added later stations at one end);
  subsequence    the group omits stations that the dated source says were not
                 open yet — each omitted name has to appear in that source;
  existing_lead  the group starts with through-running stations that belong to
                 another line's roster (Shenzhen line 8 runs through line 2's
                 莲塘) — each leading name has to exist in another roster.

Anything else is `unaligned` and the milestone stays unverified.
"""
import datetime
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEDGER_DIR = 'data/official_evidence'
CITY_LEDGERS = {
    'shenzhen': f'{LEDGER_DIR}/history_two_source_shenzhen_2026-10-29.json',
}
OUT = 'docs/history-two-source-2026-10-29.json'
TARGETS = 'data/official_targets_2026-10-01.json'


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def write(name, value):
    path = ROOT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def digest(name):
    return hashlib.sha256((ROOT / name).read_bytes()).hexdigest()


def _subsequence(seq, official):
    """Return (ok, skipped): seq in order inside official, plus the gaps."""
    position = 0
    skipped = []
    for name in seq:
        while position < len(official) and official[position] != name:
            skipped.append(official[position])
            position += 1
        if position >= len(official):
            return False, []
        position += 1
    return True, skipped + official[position:]


def alignment(names, official):
    if names == official or names == list(reversed(official)):
        return 'exact', {}
    size = len(names)
    for candidate in (names, list(reversed(names))):
        for start in range(len(official) - size + 1):
            if official[start:start + size] == candidate:
                return 'contiguous', {'start': start}
    ok, skipped = _subsequence(names, official)
    if ok:
        return 'subsequence', {'skipped': skipped}
    lead = []
    rest = list(names)
    while rest and rest[0] not in official:
        lead.append(rest.pop(0))
    if lead and rest:
        ok, skipped = _subsequence(rest, official)
        if ok:
            return 'existing_lead', {'lead': lead, 'skipped': skipped}
    return 'unaligned', {}


def order_errors(city, milestone, rosters):
    """Recompute every declared alignment against the official rosters."""
    errors = []
    declared = {row['groupId']: row for row in milestone.get('orders', [])}
    groups = city.get('groups', [])
    if len(declared) != len(groups):
        errors.append(f'{milestone["chapterId"]}: {len(groups)} groups but {len(declared)} alignments declared')
    for group in groups:
        group_id = str(group.get('id', ''))
        row = declared.get(group_id)
        if row is None:
            errors.append(f'{milestone["chapterId"]}: group {group_id} has no declared alignment')
            continue
        roster = rosters.get(row.get('line', ''))
        if not roster:
            errors.append(f'{milestone["chapterId"]}: no official roster for {row.get("line", "-")}')
            continue
        kind, detail = alignment(list(group.get('stationNames', [])), roster)
        if kind != row.get('expect'):
            errors.append(f'{milestone["chapterId"]}: {group_id} aligns as {kind}, ledger says {row.get("expect")}')
            continue
        if kind == 'subsequence':
            quote = ' '.join(str(source.get('quote', '')) for source in milestone.get('dateSources', []))
            missing = [name for name in detail['skipped'] if name not in quote]
            if missing:
                errors.append(f'{milestone["chapterId"]}: {group_id} omits {missing} with no dated statement')
        if kind == 'existing_lead':
            for name in detail['lead']:
                if not any(name in values for key, values in rosters.items() if key != row.get('line')):
                    errors.append(f'{milestone["chapterId"]}: {group_id} leads with {name}, which no other roster lists')
            quote = ' '.join(str(source.get('quote', '')) for source in milestone.get('dateSources', []))
            missing = [name for name in detail['skipped'] if name not in quote]
            if missing:
                errors.append(f'{milestone["chapterId"]}: {group_id} omits {missing} with no dated statement')
    return errors


def _short_date(date):
    return f'{int(date[5:7])}月{int(date[8:10])}日'


def date_errors(milestone):
    """A dated source has to be official, dated, and quote real text.

    A report published a few days after the opening is still a contemporaneous
    source, so a short lag is allowed when the quote names the day; a document
    from a later year is not.
    """
    errors = []
    chapter = milestone.get('chapterId', '')
    sources = milestone.get('dateSources', [])
    if not sources:
        return [f'{chapter}: no dated source']
    date = str(milestone.get('date', ''))
    short = _short_date(date)
    for source in sources:
        if not str(source.get('url', '')).startswith('https://'):
            errors.append(f'{chapter}: date source is not https')
        publication = str(source.get('publicationDate', ''))
        quote = str(source.get('quote', ''))
        if not publication or not quote:
            errors.append(f'{chapter}: date source has no publication date or quote')
            continue
        if publication <= date:
            continue
        lag = (datetime.date.fromisoformat(publication) - datetime.date.fromisoformat(date)).days
        if source.get('kind') != 'opening_day' or lag > 45 or (date not in quote and short not in quote):
            errors.append(f'{chapter}: source published {publication}, {lag} days after {date}')
    opening = [source for source in sources if source.get('kind') == 'opening_day']
    if opening:
        if not any(date in str(source.get('quote', '')) or short in str(source.get('quote', ''))
                   for source in opening):
            errors.append(f'{chapter}: opening-day quote never states {date}')
    elif any(source.get('kind') == 'two_source_inference' for source in sources):
        if len(sources) < 2:
            errors.append(f'{chapter}: an inference needs two dated documents')
    elif not any(source.get('kind') == 'network_state' for source in sources):
        errors.append(f'{chapter}: no source kind justifies the claimed date')
    return errors


def main():
    targets = read(TARGETS)
    combined = {'schemaVersion': 1, 'reviewedAt': '2026-10-29', 'cities': {}}
    changed = 0
    for city_id, name in CITY_LEDGERS.items():
        ledger = read(name)
        rosters = {}
        for source_id, source in ledger.get('orderSources', {}).items():
            path = source['file']
            actual = digest(path)
            if actual != source.get('sha256'):
                raise SystemExit(f'{city_id}: {source_id} hash {actual} does not match the ledger')
            rosters.update(read(path)['stationOrders'])
        city = targets['cities'][city_id]
        milestones = {str(m.get('chapterId', '')): m for m in city.get('historicalMilestones', [])}
        rows = []
        for entry in ledger.get('milestones', []):
            chapter_id = str(entry.get('chapterId', ''))
            milestone = milestones.get(chapter_id)
            errors = []
            if milestone is None:
                errors.append(f'{chapter_id}: no such milestone in the target list')
            else:
                if str(milestone.get('date', '')) != str(entry.get('date', '')):
                    errors.append(f'{chapter_id}: ledger date differs from the target list')
                errors.extend(date_errors(entry))
                errors.extend(order_errors(milestone, entry, rosters))
            verdict = 'verified' if not errors else 'unverified'
            rows.append({**entry, 'verdict': verdict, 'issues': errors})
        covered = {str(entry.get('chapterId', '')) for entry in ledger.get('milestones', [])}
        for chapter_id in milestones:
            if chapter_id not in covered:
                rows.append({'chapterId': chapter_id, 'verdict': 'unverified',
                             'issues': [f'{chapter_id}: not covered by the two-source ledger']})
        verified = [row for row in rows if row['verdict'] == 'verified']
        status = 'verified' if len(verified) == len(rows) and rows else 'pending'
        failed = [row for row in rows if row['verdict'] != 'verified']
        note = (f'两源复核{city_id}的{len(rows)}条历史里程碑：日期用带日期的官方公告，站序用官方逐线站表，'
                f'{len(verified)}条两项都对上。')
        if failed:
            note += '未通过：' + '；'.join(
                f'{row["chapterId"]}（{" / ".join(row["issues"][:2])}）' for row in failed[:4])
            note += f'。未通过项不标已核对，明细见 {OUT}。'
        combined['cities'][city_id] = {
            'milestones': rows, 'verifiedCount': len(verified),
            'unverifiedCount': len(failed), 'verdict': 'complete' if status == 'verified' else 'incomplete',
            'note': note,
        }
        if city.get('historyReviewStatus') == status and city.get('historyReviewNote') == note:
            print(f'ALREADY_RECORDED {city_id} {len(verified)}/{len(rows)}')
            continue
        city['historyReviewStatus'] = status
        city['historyReviewNote'] = note
        changed += 1
        print(f'{"VERIFIED" if status == "verified" else "STILL_PENDING"} {city_id} {len(verified)}/{len(rows)}')
        for row in failed[:6]:
            print('  -', row['chapterId'], '|', ' / '.join(row['issues'][:2]))
    write(OUT, combined)
    print('LEDGER', OUT)
    if changed:
        write(TARGETS, targets)
    else:
        print('ALREADY_RECORDED no history status changed')


if __name__ == '__main__':
    main()
