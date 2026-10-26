"""Review explicit map interchange symbols independently of campaign content.

The operator distance tables contain planned and stale stops. They establish
line membership only after the individually recorded corrections below; the
map's transfer symbol, rather than a crossing or shared name, is the evidence.
Current captures never by themselves certify all historic formation dates.
"""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
from audit_operator_transfers import audit_pairs

ROOT=Path(__file__).resolve().parents[1]
EVIDENCE=ROOT/'data/official_evidence/beijing_interchanges_reviewed2026-10-26.json'
ORDERS=ROOT/'data/official_evidence/beijing_operator_distance_tables_retrieved2026-10-25.json'
SOURCE='https://www.bjmoa.cn/viewPhoto_343.html'
IMAGE='https://www.bii.com.cn/file/2026/06/25/1782360280894.jpg'
FANGSHAN='https://www.bjfsh.gov.cn/zhxw/fsdt/202012/t20201231_40012134.shtml'
LINE14='https://www.mtr.bj.cn/service/line/line-14.html'
LINES={**{str(n):f'beijing-line{n}-{n}' for n in range(3,20)},
       '1':'beijing-lineearly0','2':'beijing-lineearly1','昌平':'beijing-route-20',
       '大兴机场':'beijing-route-21','房山':'beijing-route-22','首都机场':'beijing-route-23',
       '亦庄':'beijing-route-24','燕房':'beijing-lineyanfang'}
NAME_ALIASES={'清河站':'清河','木樨地（1号线）':'木樨地','木樨地（16号线）':'木樨地','苹果园（6号线）':'苹果园'}
ROSTER='''七里庄 14 9
三元桥 10 12 首都机场
东单 1 5
东四 5 6
东四十条 2 3
东坝北 12 3
东大桥 17 6
东直门 13 2 首都机场
丰台南路 16 9
丰台站 10 16
丽泽商务区 14 16
九龙山 14 7
二里沟 16 6
人民大学 12 4
光熙门 12 13
公主坟 10 1
六道口 15 昌平
六里桥 10 9
军事博物馆 1 9
前门 2 8
北京南站 14 4
北京西站 7 9
北土城 10 8
北太平庄 12 19
北新桥 5 首都机场
十里河 10 14 17
南锣鼓巷 6 8
双井 10 7
呼家楼 10 6
和平西桥 12 5
回龙观东大街 18 8
团结湖 10 3
国家图书馆 16 4 9
国贸 10 1
复兴门 1 2
大屯路东 15 5
大望路 14 1
大红门 10 8
大钟寺 12 13
天通苑 18 5
天通苑东 17 18
太阳宫 10 17
奥林匹克公园 15 8
安华桥 12 8
宋家庄 10 5 亦庄
宣武门 2 4
崇文门 2 5
工人体育场 17 3
平安里 19 4 6
建国门 1 2
惠新西街南口 10 5
慈寿寺 10 6
新宫 19 4
景风门 14 19
望京 14 15
望京西 13 15 17
朝阳公园 14 3
朝阳门 2 6
木樨地 16 1
朱辛庄 8 昌平
次渠 17 亦庄
永安里 17 1
永定门外 14 8
海淀黄庄 10 4
牡丹园 10 19
王府井 1 8
环球度假区 1 7
珠市口 7 8
白石桥南 6 9
知春路 10 13
磁器口 5 7
积水潭 19 2
立水桥 13 5
芍药居 10 13
花庄 1 7
苏州桥 12 16
苏州街 10 16
苹果园 1 6
草桥 10 19 大兴机场
菜市口 4 7
蒲黄榆 14 5
蓟门桥 12 昌平
西二旗 13 昌平
西单 1 4
西土城 10 昌平
西坝河 12 17
西局 10 14
西直门 13 2 4
西苑 16 4
角门西 10 4
车公庄 2 6
达官营 16 7
郭公庄 9 房山
金台路 14 6
金安桥 11 6
长春桥 10 12
阎村东 房山 燕房
雍和宫 2 5
霍营 13 8
马连洼 16 18
鼓楼大街 2 8
首经贸 10 房山
东管头南 16 房山
清河 13 昌平'''
OUTSIDE={
    '木樨地':'https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202401/t20240117_3537679.html',
    '大钟寺':'https://news.bjd.com.cn/2024/12/16/11004457.shtml',
}
LINE14_NAMES='善各庄 来广营 东湖渠 望京 阜通 望京南 将台 东风北桥 枣营 朝阳公园 金台路 大望路 九龙山 平乐园 北工大西门 十里河 方庄 蒲黄榆 景泰 永定门外 北京南站 景风门 西铁营 菜户营 丽泽商务区 东管头 西局 七里庄 大井 郭庄子 大瓦窑 园博园 张郭庄'.split()


def source_memberships(orders):
    names={}
    for line in orders['lines']:
        label=line['line'];number=label.removesuffix('号线').removesuffix('线')
        if label=='八通线':number='1'
        if label=='大兴线':number='4'
        if number not in LINES:continue
        names.setdefault(number,set()).update(NAME_ALIASES.get(n,n) for n in line['directions'][0]['stationNames'])
    # Explicitly reviewed stale table differences, never read from chapters.
    names['房山'].update('东管头南 首经贸 花乡东桥 白盆窑'.split())
    names['14']=set(LINE14_NAMES)
    return names


def documented_pairs(evidence):
    pairs=[];seen=set()
    for station in evidence['stations']:
        name=station['stationName'];lines=station['lineNumbers']
        if name in seen or len(set(lines))!=len(lines) or len(lines)<2:raise ValueError('Invalid or duplicate reviewed symbol')
        seen.add(name)
        for a,b in itertools.combinations(lines,2):pairs.append((name,*sorted((LINES[a],LINES[b]))))
    return sorted(pairs)


def evidence_errors(evidence,orders):
    names=source_memberships(orders);errors=[]
    if evidence.get('lineIds')!=LINES:errors.append('Line mapping changed')
    for row in evidence['stations']:
        for n in row['lineNumbers']:
            if row['stationName'] not in names.get(n,set()):errors.append(row['stationName']+': absent from independently reviewed line '+n)
        wanted='out_of_station' if row['stationName'] in OUTSIDE else 'interchange'
        if row.get('transferKind')!=wanted:errors.append(row['stationName']+': transfer type lost')
    # Completeness check is only for this manually reviewed map roster, not a
    # general rule that coincident names on arbitrary lines prove interchange.
    expected={}
    for number,stops in names.items():
        for name in stops:expected.setdefault(name,set()).add(number)
    expected={k:v for k,v in expected.items() if len(v)>1}
    actual={r['stationName']:set(r['lineNumbers']) for r in evidence['stations']}
    if expected!=actual:errors.append('Reviewed map roster differs from corrected source memberships: '+str({n:(sorted(expected.get(n,[])),sorted(actual.get(n,[]))) for n in expected.keys()|actual.keys() if expected.get(n)!=actual.get(n)}))
    try:documented_pairs(evidence)
    except (ValueError,KeyError):errors.append('Invalid map symbols')
    return errors


def make_evidence(image):
    return dict(source=SOURCE,mapSource=IMAGE,mapSha256=hashlib.sha256(image.read_bytes()).hexdigest(),retrievedAt='2026-10-26',
        mapDateNote='6月25日是附件路径日期，不擅自视为每个对象的开放日期；通运门等后续开放另用公告。',lineIds=LINES,
        orderEvidence='res://data/official_evidence/beijing_operator_distance_tables_retrieved2026-10-25.json',
        orderCorrections=[dict(line='房山',source=FANGSHAN,addedStations='东管头南 首经贸 花乡东桥 白盆窑'.split()),
                          dict(line='14',source=LINE14,stationNames=LINE14_NAMES,note='使用运营方当前站点页，不把距离表的红庙、南八里庄、陶然桥和高家园当作开放停站。')],
        stations=[dict(stationName=row.split()[0],lineNumbers=row.split()[1:],
                       transferKind='out_of_station' if row.split()[0] in OUTSIDE else 'interchange',
                       source=OUTSIDE.get(row.split()[0],SOURCE)) for row in ROSTER.splitlines()],
        scopeNote='25项地铁服务口径；S1磁浮、西郊及亦庄T1有轨另列，不计入本轮地铁主线配对。4号线大兴线、1号线八通线分别按贯通服务处理。',
        reviewNote='逐个读取运营图换乘符号。灰色标识是站内通道暂缓，不是完全无法换乘；木樨地和大钟寺保留明确出闸换乘。不同站名的龙泽西／龙泽和霍营东／霍营不伪造联系。')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--author-evidence',type=Path)
    parser.add_argument('--checkpoint',type=Path);parser.add_argument('--output',type=Path);args=parser.parse_args()
    if args.author_evidence:EVIDENCE.write_text(json.dumps(make_evidence(args.author_evidence),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    evidence=json.loads(EVIDENCE.read_text(encoding='utf-8'));errors=evidence_errors(evidence,json.loads(ORDERS.read_text(encoding='utf-8')))
    if errors:raise ValueError(errors)
    pairs=documented_pairs(evidence)
    if not args.checkpoint:print('BEIJING_INTERCHANGES',len(evidence['stations']),len(pairs));return 0
    checkpoint=args.checkpoint.resolve()
    if not checkpoint.is_relative_to(ROOT) or not checkpoint.relative_to(ROOT).parts[0].startswith('.tmp-remediation-'):parser.error('Only isolated replay checkpoints supported')
    raw=checkpoint.read_bytes();world=json.loads(raw)
    if world.get('cityId')!='beijing' or not args.output:parser.error('Beijing checkpoint and report path required')
    # Construction-preview 13A/13B services may deliberately reuse older
    # physical bodies. Their ownership is checked by their project rules, not
    # falsely reported as an invalid contact in this 25-service current audit.
    in_scope=set(LINES.values())
    outside=[c for c in world.get('transferConnections',[]) if not set(c.get('lineIds',[])).issubset(in_scope)]
    current={**world,'transferConnections':[c for c in world.get('transferConnections',[]) if c not in outside]}
    report=audit_pairs(current,pairs,evidence,NAME_ALIASES)
    report['outOfScopeConstructionConnectionIds']=[c['id'] for c in outside]
    expected_kinds={(row['stationName'],tuple(sorted([LINES[n] for n in row['lineNumbers']]))):row['transferKind'] for row in evidence['stations']}
    stations={s.get('stationInstanceId',s['id']):s for s in world.get('stations',[])}
    for connection in world.get('transferConnections',[]):
        if connection.get('status','active')!='active':continue
        for instance in connection.get('stationInstanceIds',[]):
            name=stations.get(instance,{}).get('name');name=NAME_ALIASES.get(name,name)
            key=(name,tuple(sorted(connection.get('lineIds',[]))))
            if key in expected_kinds and connection.get('transferKind','interchange')!=expected_kinds[key]:
                report['invalidConnections'].append(dict(id=connection['id'],reason='wrong in-station/out-of-station transfer type'));break
    report.update(checkpointSha256=hashlib.sha256(raw).hexdigest(),evidenceSha256=hashlib.sha256(EVIDENCE.read_bytes()).hexdigest())
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('BEIJING_TRANSFER',report['matchedPairs'],'/',report['expectedPairs'],'matched;',len(report['invalidConnections']),'invalid')
    for row in report['missingPairs']:print(row)
    return int(bool(report['missingPairs'] or report['invalidConnections']))


if __name__=='__main__':raise SystemExit(main())
