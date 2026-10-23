"""Read a published official fare workbook, without reading playable tasks.

Extraction is an evidence aid: fare tables may omit unopened stations or use
different names. Review the resulting station orders before promoting a target.
"""
import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}


def extract(path):
    with zipfile.ZipFile(path) as archive:
        shared = [''.join(e.itertext()) for e in ET.fromstring(archive.read('xl/sharedStrings.xml'))]
        sheet = ET.fromstring(archive.read('xl/worksheets/sheet1.xml'))
    cells = {}
    for cell in sheet.findall('.//s:c', NS):
        value = cell.find('s:v', NS)
        if value is not None:
            cells[cell.attrib['r']] = shared[int(value.text)] if cell.get('t') == 's' else value.text
    # Column A has merged line labels; C contains the corresponding station.
    line = None
    groups = {}
    for row in sheet.findall('.//s:row', NS):
        number = row.attrib['r']
        label = cells.get('A' + number, '')
        if re.fullmatch(r'\d+(?:支)?号线', label):
            line = label
        name = cells.get('C' + number, '').strip()
        if line and name and name != '站名':
            groups.setdefault(line, []).append(name)
    return groups


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('workbook', type=Path)
    parser.add_argument('--source', required=True)
    parser.add_argument('--publication-date', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = dict(source=args.source, sourcePublicationDate=args.publication_date,
                  sha256=hashlib.sha256(args.workbook.read_bytes()).hexdigest(),
                  extractionStatus='needs_review', stationOrders=extract(args.workbook))
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({line:len(stations) for line, stations in result['stationOrders'].items()}, ensure_ascii=False))


if __name__ == '__main__':
    import sys
    sys.stdout.reconfigure(encoding='utf-8')
    main()
