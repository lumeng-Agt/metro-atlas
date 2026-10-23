"""Read operator timetable station orders, independently of game chapters.

The public endpoint is linked by https://www.chengdurail.com/js/staCheck.js.
Retrieval is later than the cutoff. Dated opening notices remain necessary.
"""
import argparse
import hashlib
import json
from pathlib import Path

SOURCE = 'https://www.chengdurail.com/op/station-time'


def station_name(value):
    for note in ('（出闸换乘）', '(仅换乘)', '（仅换乘）'):
        value = value.replace(note, '')
    return value.strip()


def extract(data):
    result = {}
    for line in data['data']:
        if line['lineName'].startswith(('S', '蓉')):
            continue  # Separate background modes, not metro history completion.
        candidates = []
        for sub in line['subLine']:
            names = [station_name(s['stationName']) for s in sub['stationList']]
            if len(names) != len(set(names)):
                raise ValueError(f"{line['lineName']}: repeated stop in operator path")
            if names not in candidates and names[::-1] not in candidates:
                candidates.append(names)
        # Timetable short workings do not create additional physical branches.
        orders = [a for a in candidates if not any(set(a) < set(b) for b in candidates)]
        result[str(int(line['lineNo']))] = {'name': line['lineName'], 'orders': orders}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('raw', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    raw = args.raw.read_bytes()
    lines = extract(json.loads(raw))
    output = {'source': SOURCE, 'sourcePage': 'https://www.chengdurail.com/ckfw/smbcskb.htm',
              'retrievedAt': '2026-10-23', 'sha256': hashlib.sha256(raw).hexdigest(),
              'reviewStatus': 'current_station_order_crosscheck_only',
              'note': '独立读取运营方时刻表；去除换乘说明文字，短交路不另算分支。不能代替截止日和历史开放公告。7号线时刻表不重复首站，闭环须另按线路资料记录。',
              'lines': lines}
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for line, item in lines.items():
        print(line, [len(order) for order in item['orders']])


if __name__ == '__main__':
    main()
