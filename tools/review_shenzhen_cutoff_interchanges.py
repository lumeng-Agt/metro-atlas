"""Independently transcribed interchange identities from the official map.

This roster does not read campaign data. The 2026-06 fare-table station
orders establish the named lines; the transport bureau's network map is
checked for interchange symbols, rather than treating every intersection
or similarly named station as a transfer. Historical formation dates are
not inferred from this current diagram.
"""
import argparse,hashlib,itertools,json
from pathlib import Path
from audit_operator_transfers import audit_pairs

ROOT=Path(__file__).resolve().parents[1]
SOURCE='https://jtys.sz.gov.cn/jtzx/wycx/dtcx/dtxl/content/post_12601089.html'
IMAGE='https://jtys.sz.gov.cn/img/4/4457/4457528/12601089.jpg'
LINES={'1':'shenzhen-line1','2':'shenzhen-line2-2','3':'shenzhen-line3-3','4':'shenzhen-line4',
       '5':'shenzhen-line5-5','6':'shenzhen-line6-6','6支':'shenzhen-line6-7','7':'shenzhen-line7-8',
       '8':'shenzhen-line8-9','9':'shenzhen-line9-10','10':'shenzhen-line10-11','11':'shenzhen-line11-12',
       '12':'shenzhen-line12-13','13':'shenzhen-line13-14','14':'shenzhen-line14-15',
       '16':'shenzhen-line16-16','20':'shenzhen-line20-17'}
ROSTER='''老街 1 3
大剧院 1 2 5
科学馆 1 6
岗厦 1 10
会展中心 1 4
购物公园 1 3
车公庙 1 7 9 11
世界之窗 1 2
深大 1 13
桃园 1 12
前海湾 1 5 11
宝安中心 1 5
机场东 1 12
赤湾 2 5
海上世界 2 12
后海 2 11 13
科苑 2 13
安托山 2 7
景田 2 9
福田 2 3 11
市民中心 2 4
岗厦北 2 10 11 14
华强北 2 7
湖贝 2 5
黄贝岭 2 5
石厦 3 7
少年宫 3 4
莲花村 3 10
华新 3 7
通新岭 3 6
红岭 3 9
田贝 3 7
布吉 3 5 14
大运 3 14 16
双龙 3 16
福田口岸 4 10
福民 4 7 10
上梅林 4 9
深圳北站 4 5 6
红山 4 6
前湾 5 9
灵芝 5 12
留仙洞 5 13
西丽 5 7
五和 5 10
太安 5 7
八卦岭 6 7
银湖 6 9
上屋 6 13
凤凰城 6 13
光明 6 6支
公明广场 6 13
松岗 6 11 12
光明城 6支 13
华强南 7 11
黄木岗 7 14
红岭北 7 9
南油 9 12
粤海门 9 13
红树湾南 9 11
孖岭 9 10
红岭南 9 11
南山 11 12
机场北 11 20
福永 11 12
国展 12 20
国展北 12 20
坪山围 14 16'''
EVIDENCE=ROOT/'data/official_evidence/shenzhen_interchanges_reviewed2026-10-26.json'


def make_evidence(image_path):
    stations=[]
    for row in ROSTER.splitlines():
        name,*lines=row.split();stations.append(dict(stationName=name,lineNumbers=lines))
    return dict(source=SOURCE,retrievedAt='2026-10-26',mapSource=IMAGE,
                mapSha256=hashlib.sha256(image_path.read_bytes()).hexdigest(),
                sourcePublicationDate='2026-01-14',
                dateNote='页面标注1月14日，但13号线北延已画入，说明附件后续更新；不能以该页面日期证明全部历史形成时间。',
                stationOrderEvidence='res://data/official_evidence/shenzhen_2026-06-28_station_orders.json',
                reviewNote='逐个对照换乘符号；同一枢纽的多线拆为线路对。莲塘为2／8贯通边界，不增加两套独立站体或换乘任务；铁路、有轨和云巴不混入地铁配对。',
                lineIds=LINES,stations=stations)


def documented_pairs(evidence):
    pairs=[];seen=set()
    for station in evidence['stations']:
        lines=station['lineNumbers'];name=station['stationName']
        if name in seen or len(set(lines))!=len(lines) or len(lines)<2:raise ValueError('duplicate or invalid interchange roster')
        seen.add(name)
        for a,b in itertools.combinations(lines,2):pairs.append((name,*sorted((evidence['lineIds'][a],evidence['lineIds'][b]))))
    return sorted(pairs)


def evidence_errors(evidence,orders):
    """Cross-check the reviewed symbols against the separate fare-table roster.

    Only this individually reviewed map declares that the shared station names
    below are interchanges. Do not reuse this rule to infer other cities' links.
    """
    aliases={'6支号线':'6支'};by_name={};errors=[]
    for label,names in orders['stationOrders'].items():
        number=aliases.get(label,label.removesuffix('号线'))
        if number not in LINES:errors.append('unmapped official line: '+label);continue
        for name in names:by_name.setdefault(name,set()).add(number)
    expected={name:lines for name,lines in by_name.items() if len(lines)>1}
    actual={row['stationName']:set(row['lineNumbers']) for row in evidence['stations']}
    if evidence.get('lineIds')!=LINES:errors.append('external line identity mapping differs')
    for name,lines in expected.items():
        if actual.get(name)!=lines:errors.append(name+': reviewed interchange line roster differs')
    for name in actual.keys()-expected.keys():errors.append(name+': interchange is absent from independently extracted official station orders')
    try:documented_pairs(evidence)
    except (ValueError,KeyError):errors.append('invalid or duplicate reviewed map symbols')
    return errors


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--author-evidence',type=Path)
    parser.add_argument('--checkpoint',type=Path);parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    if args.author_evidence:EVIDENCE.write_text(json.dumps(make_evidence(args.author_evidence),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    evidence=json.loads(EVIDENCE.read_text(encoding='utf-8'));pairs=documented_pairs(evidence)
    errors=evidence_errors(evidence,json.loads((ROOT/'data/official_evidence/shenzhen_2026-06-28_station_orders.json').read_text(encoding='utf-8')))
    if errors:raise ValueError(errors)
    if not args.checkpoint:print('SHENZHEN_INTERCHANGES',len(evidence['stations']),len(pairs));return 0
    checkpoint=args.checkpoint.resolve()
    if not checkpoint.is_relative_to(ROOT) or not checkpoint.relative_to(ROOT).parts[0].startswith('.tmp-remediation-'):parser.error('Only isolated replay checkpoints are supported')
    raw=checkpoint.read_bytes();world=json.loads(raw)
    if world.get('cityId')!='shenzhen' or not args.output:parser.error('Shenzhen checkpoint and output required')
    report=audit_pairs(world,pairs,evidence,{'深圳北':'深圳北站'})
    report.update(checkpointSha256=hashlib.sha256(raw).hexdigest(),evidenceSha256=hashlib.sha256(EVIDENCE.read_bytes()).hexdigest())
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('SHENZHEN_TRANSFER',report['matchedPairs'],'/',report['expectedPairs'],'matched;',len(report['invalidConnections']),'invalid')
    for row in report['missingPairs']:print(row)
    return int(bool(report['missingPairs'] or report['invalidConnections']))


if __name__=='__main__':raise SystemExit(main())
