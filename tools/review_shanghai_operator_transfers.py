"""Read interchange bitmasks using the public operator's own decoder format.

The source is the independently captured timetable, not campaign definitions.
This current diagnostic alone cannot certify historical formation dates.
"""
import argparse,hashlib,itertools,json,re
from pathlib import Path
from audit_operator_transfers import audit_pairs

ROOT=Path(__file__).resolve().parents[1]
EVIDENCE=ROOT/'data/official_evidence/shanghai_interchanges_retrieved2026-10-23.json'
LINES={str(i):'shanghai-line1' if i==1 else f'shanghai-line{i}-{i}' for i in range(1,19)}
SOURCE='https://service.shmetro.com/czxx/index.htm'
DECODER='https://service.shmetro.com/skin/js/metrostations.js'


def decode_lines(code):
    if not isinstance(code,str) or not re.fullmatch(r'[0-9A-Fa-f]+-.+',code):raise ValueError('Invalid operator interchange bitmask')
    mask=int(code.split('-',1)[0],16)
    if mask<=0:raise ValueError('Empty operator interchange bitmask')
    return [str(i) for i in range(1,57) if mask & (1<<(i-1))]


def extract(payloads):
    if set(payloads)!=set(LINES):raise ValueError('All eighteen in-scope operator lines required')
    stops={};claims={}
    for line,rows in payloads.items():
        if not isinstance(rows,list) or not rows:raise ValueError('Empty operator line')
        stops[line]=set()
        for row in rows:
            if str(row.get('line'))!=line or not row.get('name') or not row.get('stat_id'):raise ValueError('Mixed or invalid line row')
            lines=decode_lines(row.get('station_code'))
            if line not in lines:raise ValueError('The station mask omits its own line')
            name=row['name'];stops[line].add(name)
            key=(name,line)
            if key in claims and claims[key]!=lines:raise ValueError('Inconsistent duplicate direction metadata')
            claims[key]=lines
    pairs=set()
    for (name,own),lines in claims.items():
        for other in lines:
            if other not in LINES or other==own:continue
            if name not in stops[other] or own not in claims.get((name,other),[]):raise ValueError('Unilateral or differently named interchange claim')
            pairs.add((name,*sorted((LINES[own],LINES[other]))))
    return [dict(stationName=n,lineIds=[a,b]) for n,a,b in sorted(pairs)]


def make_evidence(folder,decoder):
    previous=json.loads((ROOT/'data/official_evidence/shanghai_operator_orders_retrieved2026-10-23.json').read_text(encoding='utf-8'))
    payloads={};hashes={}
    for line in LINES:
        raw=(folder/f'line-{line}.json').read_bytes();digest=hashlib.sha256(raw).hexdigest()
        if previous['lines'][line]['sha256']!=digest:raise ValueError('Timetable capture differs from separately recorded source hash')
        payloads[line]=json.loads(raw);hashes[line]=dict(source=previous['lines'][line]['source'],sha256=digest)
    script=decoder.read_bytes()
    if b'getExchangeLine(station_code)' not in script or b'parseInt(ex_code, 16)' not in script:raise ValueError('Operator decoder format not inspected')
    return dict(source=SOURCE,retrievedAt='2026-10-23',decoderSource=DECODER,decoderRetrievedAt='2026-10-26',
                decoderSha256=hashlib.sha256(script).hexdigest(),lineSources=hashes,pairs=extract(payloads),
                scopeNote='本轮既定主线1—18号线；浦江、磁浮和市域线另列。仅排除这些范围外编号，不把未知未来线路当作已开放换乘。',
                note='运营方以station_code连字符前的十六进制位掩码标出换乘线；按其公开getExchangeLine方法解析，并逐站检查对侧运营表对称声明。共线、站外换乘的现实结构与历史日期仍需另外分层核对。')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture-folder',type=Path);parser.add_argument('--decoder-file',type=Path)
    parser.add_argument('--checkpoint',type=Path);parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    if args.capture_folder:
        if not args.decoder_file:parser.error('Inspected decoder file required')
        EVIDENCE.write_text(json.dumps(make_evidence(args.capture_folder,args.decoder_file),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    evidence=json.loads(EVIDENCE.read_text(encoding='utf-8'))
    if not args.checkpoint:print('SHANGHAI_OPERATOR_PAIRS',len(evidence['pairs']));return 0
    checkpoint=args.checkpoint.resolve()
    if not checkpoint.is_relative_to(ROOT) or not checkpoint.relative_to(ROOT).parts[0].startswith('.tmp-remediation-'):parser.error('Only isolated replay checkpoints supported')
    raw=checkpoint.read_bytes();world=json.loads(raw)
    if world.get('cityId')!='shanghai' or not args.output:parser.error('Shanghai checkpoint and output required')
    pairs=[(p['stationName'],*p['lineIds']) for p in evidence['pairs']]
    report=audit_pairs(world,pairs,evidence,{'新天地':'一大会址·新天地','黄陂南路':'一大会址·黄陂南路'})
    report.update(checkpointSha256=hashlib.sha256(raw).hexdigest(),evidenceSha256=hashlib.sha256(EVIDENCE.read_bytes()).hexdigest())
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('SHANGHAI_TRANSFER',report['matchedPairs'],'/',report['expectedPairs'],'matched;',len(report['invalidConnections']),'invalid')
    for row in report['missingPairs']:print(row)
    return int(bool(report['missingPairs'] or report['invalidConnections']))


if __name__=='__main__':raise SystemExit(main())
