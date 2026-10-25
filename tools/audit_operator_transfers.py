"""Compare public operator interchange pairs with an actual isolated replay.

Independent of campaign tasks. Current operator data is not by itself dated
cutoff evidence, so this diagnostic never grants complete-delivery status.
"""
import argparse
import hashlib
import itertools
import json
from pathlib import Path

from review_guangzhou_operator_cutoff import MAPPING

ROOT=Path(__file__).resolve().parents[1]
EVIDENCE=ROOT/'data/official_evidence/guangzhou_operator_orders_retrieved2026-10-25.json'
LINES={**MAPPING,3:'guangzhou-line3-3',4:'guangzhou-line3-3',
       14:'guangzhou-line14-14',17:'guangzhou-line14-14',
       31:'guangzhou-line12-12',33:'guangzhou-line12-12'}


def expected_pairs(evidence):
    pairs=set()
    for line in evidence['lines']:
        own=LINES[line['operatorLineId']]
        for item in line['interchanges']:
            for operator_id in item['operatorLineIds']:
                other=LINES.get(operator_id)
                # Same-line branches and services outside the explicit metro
                # scope are not independent interchanges for this audit.
                if other and own!=other:
                    pairs.add((item['stationName'],*sorted((own,other))))
    return sorted(pairs)


def audit(world,evidence):
    by_instance={s.get('stationInstanceId',s['id']):s for s in world.get('stations',[])}
    served=set()
    for route in world.get('routes',[]):
        if route.get('retired') or not route.get('open'):continue
        for direction in route.get('directions',[]):
            served.update((route.get('historicalLineId'),sid) for sid in direction.get('stationIds',[]))
    present=set();invalid=[];non_open=[]
    for connection in world.get('transferConnections',[]):
        if connection.get('status','active')!='active':continue
        lines=connection.get('lineIds',[]);instances=connection.get('stationInstanceIds',[])
        if len(lines)!=len(instances) or len(lines)<2:
            invalid.append(dict(id=connection.get('id'),reason='invalid pairing'));continue
        for a,b in itertools.combinations(range(len(lines)),2):
            sa=by_instance.get(instances[a],{});sb=by_instance.get(instances[b],{})
            if not sa or not sb or instances[a]==instances[b]:
                invalid.append(dict(id=connection.get('id'),reason='missing or shared physical body'));continue
            if any(s.get('stationLineId')!=line for s,line in [(sa,lines[a]),(sb,lines[b])]):
                invalid.append(dict(id=connection.get('id'),reason='body belongs to another physical line'));continue
            if any((line,s['id']) not in served for s,line in [(sa,lines[a]),(sb,lines[b])]):
                non_open.append(dict(id=connection.get('id'),reason='construction relationship has no current open service'));continue
            if sa.get('name')==sb.get('name'):
                present.add((sa['name'],*sorted((lines[a],lines[b]))))
    expected=expected_pairs(evidence)
    missing=[dict(station=name,lineIds=[a,b]) for name,a,b in expected if (name,a,b) not in present]
    return dict(kind='operator-transfer-diagnostic',city=world.get('cityId'),
                operatorRetrievedAt=evidence['retrievedAt'],source=evidence['source'],
                expectedPairs=len(expected),matchedPairs=len(expected)-len(missing),
                missingPairs=missing,invalidConnections=invalid,nonOpenConnections=non_open,
                completeDeliveryCertified=False,
                note='Operator query proves current pair claims only. Cutoff dates and historical formation still require their dated evidence.')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checkpoint',type=Path);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();checkpoint=args.checkpoint.resolve()
    if not checkpoint.is_relative_to(ROOT) or not checkpoint.relative_to(ROOT).parts[0].startswith('.tmp-remediation-'):
        parser.error('Only explicit isolated replay checkpoints are supported')
    raw=checkpoint.read_bytes();world=json.loads(raw)
    if world.get('cityId')!='guangzhou':parser.error('This evidence covers Guangzhou only')
    report=audit(world,json.loads(EVIDENCE.read_text(encoding='utf-8')))
    report.update(checkpointSha256=hashlib.sha256(raw).hexdigest(),evidenceSha256=hashlib.sha256(EVIDENCE.read_bytes()).hexdigest())
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('OPERATOR_TRANSFER',report['matchedPairs'],'/',report['expectedPairs'],'matched;',len(report['invalidConnections']),'invalid')
    return 1 if report['missingPairs'] or report['invalidConnections'] else 0


if __name__=='__main__':raise SystemExit(main())
