"""Record the independent re-read of every historical milestone citation.

Each milestone claims a dated opening with an ordered station list. This script
merges the per-city review ledgers, writes one combined ledger under `docs/`,
and records the per-city verdict.

A city is only `verified` when every one of its milestones was re-read and both
the date and the station order are confirmed by the cited document. Because the
review found real citation gaps, all five cities stay `pending` here; the note
names the failing chapters instead of hiding them behind a count.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEDGER = 'docs/history-review-2026-10-28.json'
SOURCES = (
    'data/official_evidence/history_review_shenzhen_shanghai_2026-10-28.json',
    'data/official_evidence/history_review_beijing_guangzhou_2026-10-28.json',
    'data/official_evidence/history_review_chengdu_2026-10-28.json',
)

CAUSE_LABEL = {
    'date': '日期不成立',
    'order': '站序无法逐站核对',
    'source': '来源打不开或非官方',
    'subsection': '建设子段指错',
}


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def write(name, value):
    path = ROOT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def classify(row):
    """Bucket one failure into the reason a reader cares about most."""
    issues = ' '.join(str(x) for x in row.get('issues', []))
    if row.get('readable') is False or row.get('httpStatus') not in (200, '200', None):
        if row.get('readable') is False:
            return 'source'
    if row.get('dateConfirmed') is False:
        return 'date'
    if '子段' in issues or 'constructionStationNames' in issues:
        return 'subsection'
    return 'order'


def city_note(city_id, rows):
    verified = [r for r in rows if r.get('verdict') == 'verified']
    failed = [r for r in rows if r.get('verdict') != 'verified']
    buckets = {}
    for row in failed:
        buckets.setdefault(classify(row), []).append(str(row.get('chapterId', '')))
    parts = [f'逐条重开来源复核{city_id}的{len(rows)}条历史里程碑，{len(verified)}条通过。']
    for key in ('source', 'date', 'subsection', 'order'):
        if key in buckets:
            names = '、'.join(buckets[key][:8])
            more = f' 等{len(buckets[key])}条' if len(buckets[key]) > 8 else ''
            parts.append(f'{CAUSE_LABEL[key]}{len(buckets[key])}条（{names}{more}）')
    if not failed:
        parts.append('全部通过。')
    else:
        parts.append('未通过项不标已核对，明细见 docs/history-review-2026-10-28.json。')
    return ''.join(parts)


def main():
    combined = {'schemaVersion': 1, 'reviewedAt': '2026-10-28', 'cities': {}}
    for name in SOURCES:
        for city_id, block in read(name).get('cities', {}).items():
            combined['cities'][city_id] = block

    # A city that has a two-source ledger is decided there, by a script that
    # recomputes every station-order alignment. Re-using the single-source
    # verdict here would silently undo that work.
    two_source = read('data/official_evidence/history_two_source_shenzhen_2026-10-29.json')
    covered = {str(two_source.get('city', ''))}

    targets = read('data/official_targets_2026-10-01.json')
    changed = 0
    for city_id, block in combined['cities'].items():
        rows = block.get('milestones', [])
        if not rows:
            continue
        if city_id in covered:
            print(f'DEFERRED {city_id} decided by tools/review_history_two_source.py')
            two_source_block = read('docs/history-two-source-2026-10-29.json')['cities'][city_id]
            block.update(two_source_block)
            block['decidedBy'] = 'tools/review_history_two_source.py'
            continue
        verified = [r for r in rows if r.get('verdict') == 'verified']
        status = 'verified' if len(verified) == len(rows) else 'pending'
        note = city_note(city_id, rows)
        block['verifiedCount'] = len(verified)
        block['unverifiedCount'] = len(rows) - len(verified)
        block['verdict'] = 'complete' if status == 'verified' else 'incomplete'
        block['note'] = note
        city = targets.get('cities', {}).get(city_id)
        if city is None:
            continue
        if city.get('historyReviewStatus') == status and city.get('historyReviewNote') == note:
            continue
        city['historyReviewStatus'] = status
        city['historyReviewNote'] = note
        changed += 1
        print(f'{"VERIFIED" if status == "verified" else "STILL_PENDING"} {city_id} '
              f'{len(verified)}/{len(rows)}')

    write(LEDGER, combined)
    print('LEDGER', LEDGER, 'cities', len(combined['cities']))
    if changed:
        write('data/official_targets_2026-10-01.json', targets)
    else:
        print('ALREADY_RECORDED no history review status changed')


if __name__ == '__main__':
    main()
