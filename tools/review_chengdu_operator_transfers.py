"""Extract explicit transfers separately from shared-running station rows."""
import argparse,hashlib,json,re
from pathlib import Path
from audit_operator_transfers import audit_pairs

ROOT=Path(__file__).resolve().parents[1]
EVIDENCE=ROOT/'data/official_evidence/chengdu_interchanges_retrieved2026-10-23.json'
LINES={'01':'chengdu-line1','02':'chengdu-line2-2','03':'chengdu-line3-3','04':'chengdu-line4-4','05':'chengdu-line5-5',
       '06':'chengdu-line6-6','07':'chengdu-line7-7','08':'chengdu-line8-8','09':'chengdu-line9-9','10':'chengdu-line10-10',
       '13':'chengdu-line13-11','17':'chengdu-line17-12','18':'chengdu-line18-13','19':'chengdu-line19-14',
       '27':'chengdu-line27-15','30':'chengdu-line30-16'}
ALIASES={'双流机场2航站楼东':'双流机场2航站楼'}
AIRPORT_GUIDE='https://www.thepaper.cn/newsDetail_forward_32247108'
SHARED_SOURCE='https://www.chengdurail.com/info/1331/52042.htm'


def normalized_name(name):
    return re.sub(r'[（(](?:出闸换乘|仅换乘)[）)]$','',name)


def extract(payload):
    if payload.get('code')!=0 or not isinstance(payload.get('data'),list):raise ValueError('Failed operator response')
    scope=[l for l in payload['data'] if l.get('lineNo') in LINES]
    if {l['lineNo'] for l in scope}!=set(LINES) or len(scope)!=len(LINES):raise ValueError('Missing or duplicated in-scope operator line')
    index={};rows=[];shared={}
    for line in scope:
        own=line['lineNo'];count=0
        for branch in line.get('subLine',[]):
            for station in branch.get('stationList',[]):
                count+=1
                name=station.get('stationName','');codes=station.get('stationCodes',[])
                claims=station.get('transferLines','').split(',')
                if not name or not station.get('stationNo') or not codes or set(claims)!={c.get('lineNo') for c in codes}:raise ValueError('Invalid physical station or transfer-code metadata')
                clean=normalized_name(name)
                if own not in claims:
                    # The operator displays an 18-owned physical stop inside
                    # Line 19's timetable: it is not a new 18/19 walking link.
                    owner=next((c['lineNo'] for c in codes if str(station['stationNo']).startswith(c['lineNo'])),None)
                    if own!='19' or owner!='18':raise ValueError('Unreviewed cross-line station ownership')
                    shared[(own,station['stationNo'])]=dict(serviceLineId=LINES[own],physicalLineId=LINES[owner],stationName=clean,operatorStationNo=station['stationNo'],source=SHARED_SOURCE)
                    continue
                own_codes=[c['stationCode'] for c in codes if c['lineNo']==own]
                if len(own_codes)!=1:raise ValueError('Ambiguous own-line station code')
                key=(own,own_codes[0])
                if key in index and index[key]!=clean:raise ValueError('One physical operator code has different station names')
                index[key]=clean;rows.append((own,clean,codes))
        if count==0:raise ValueError('Empty operator line')
    pairs={}
    for own,name,codes in rows:
        for code in codes:
            other=code['lineNo']
            if other==own or other not in LINES:continue
            peer=index.get((other,code['stationCode']))
            if peer is None:raise ValueError('Referenced interchange body absent from peer timetable')
            members=sorted([(LINES[own],name),(LINES[other],peer)])
            a,b=members;key=(a[0],a[1],b[0],b[1])
            if name!=peer and {name,peer}!={'双流机场2航站楼','双流机场2航站楼东'}:raise ValueError('Different-name transfer requires explicit review')
            pairs[key]=dict(stationName=ALIASES.get(name,name),lineIds=[a[0],b[0]],stationNamesByLine=dict(members),
                            kind='out_of_station' if name!=peer else 'interchange_unspecified')
    # The dated operator guide explicitly adds 30 -> 10 out-of-gate transfer;
    # the old timetable's Line 10 row only lists 19. Do not silently infer the
    # extra pair from two connected walking links.
    a=(LINES['10'],'双流机场2航站楼');b=(LINES['30'],'双流机场2航站楼东')
    if ('10',a[1]) in [(line,name) for (line,_code),name in index.items()] and ('30',b[1]) in [(line,name) for (line,_code),name in index.items()]:
        pairs[(a[0],a[1],b[0],b[1])]=dict(stationName='双流机场2航站楼',lineIds=[a[0],b[0]],stationNamesByLine=dict([a,b]),kind='out_of_station',source=AIRPORT_GUIDE,sourcePublicationDate='2025-12-24')
    return dict(pairs=[pairs[k] for k in sorted(pairs)],sharedRunningStops=[shared[k] for k in sorted(shared)])


def make_evidence(path):
    raw=path.read_bytes();previous=json.loads((ROOT/'data/official_evidence/chengdu_operator_orders_retrieved2026-10-23.json').read_text(encoding='utf-8'))
    if hashlib.sha256(raw).hexdigest()!=previous['sha256']:raise ValueError('Operator capture does not match recorded source hash')
    result=extract(json.loads(raw))
    return dict(source=previous['source'],sourcePage=previous['sourcePage'],retrievedAt=previous['retrievedAt'],
                sourceSha256=previous['sha256'],**result,
                nameAnnotationsNote='保留出闸换乘和仅换乘的原文语义；规范站名不包含这些提示。双流机场两侧保持不同物理站名，仅共用诊断站区名。',
                scopeNote='S3及蓉2有轨主支线不纳入本轮地铁主线配对。18／19共线四站单列共享运行事实，不生成四条虚假的步行换乘。',
                note='现行接口并非截止日和历史开放日期证明；共线实体迁移及各时期形成时间仍须另外验收。')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--capture',type=Path)
    parser.add_argument('--checkpoint',type=Path);parser.add_argument('--output',type=Path);args=parser.parse_args()
    if args.capture:EVIDENCE.write_text(json.dumps(make_evidence(args.capture),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    evidence=json.loads(EVIDENCE.read_text(encoding='utf-8'))
    if not args.checkpoint:print('CHENGDU_TRANSFER_REQUIREMENTS',len(evidence['pairs']),'SHARED_STOPS',len(evidence['sharedRunningStops']));return 0
    checkpoint=args.checkpoint.resolve()
    if not checkpoint.is_relative_to(ROOT) or not checkpoint.relative_to(ROOT).parts[0].startswith('.tmp-remediation-'):parser.error('Only isolated replay checkpoints supported')
    raw=checkpoint.read_bytes();world=json.loads(raw)
    if world.get('cityId')!='chengdu' or not args.output:parser.error('Chengdu checkpoint and output required')
    pairs=[(p['stationName'],*p['lineIds']) for p in evidence['pairs']]
    report=audit_pairs(world,pairs,evidence,ALIASES)
    report.update(checkpointSha256=hashlib.sha256(raw).hexdigest(),evidenceSha256=hashlib.sha256(EVIDENCE.read_bytes()).hexdigest(),
                  sharedRunningStops=evidence['sharedRunningStops'],sharedGeometryCertified=False)
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('CHENGDU_TRANSFER',report['matchedPairs'],'/',report['expectedPairs'],'matched;',len(report['invalidConnections']),'invalid')
    for row in report['missingPairs']:print(row)
    return int(bool(report['missingPairs'] or report['invalidConnections']))


if __name__=='__main__':raise SystemExit(main())
