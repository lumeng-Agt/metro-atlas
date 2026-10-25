"""Extract public operator station orders, without reading game chapters.

Usage: python tools/import_gzmtr_station_orders.py <captured-json> --output <file>
The anonymous read-only endpoint is linked by Guangzhou Metro's passenger
service map. Capture date is not an opening date or a publication date.
"""
import argparse
import hashlib
import json
from pathlib import Path

SOURCE = 'https://apis.gzmtr.com/app-map/metroweb/linestation'
LANDING = 'https://cs.gzmtr.com/ckfw/'
MAP_APP = 'https://wx.gzmtr.com:50443/#/index?language=Cn'
# Explicit scope: existing game includes the two Foshan metro services, but
# not APM, trams or regional rail. Branches retain separate operator IDs.
LINE_IDS = {1,2,3,4,5,6,7,8,10,11,12,13,14,16,17,18,19,21,23,30,31,32,33}
NORMALIZATIONS = {'虫雷 岗':'𧒽岗','庆盛（南沙北站）':'庆盛'}


def extract(payload):
    if payload.get('success') is not True or not isinstance(payload.get('businessObject'),list):
        raise ValueError('Operator request did not succeed or is not a station-order response')
    result=[];seen=set()
    for line in payload['businessObject']:
        line_id=line['lineId']
        if line_id not in LINE_IDS:continue
        if line_id in seen:raise ValueError('Duplicate operator line identity')
        seen.add(line_id)
        stops=sorted(line['stations'],key=lambda s:int(s['orderNum']))
        if len(stops)<2 or len({int(s['orderNum']) for s in stops})!=len(stops):raise ValueError('Missing or duplicated stop order')
        if len({s['stationId'] for s in stops})!=len(stops):raise ValueError('Duplicated physical stop in operator path')
        raw=[s['stationName'] for s in stops]
        if any(not isinstance(n,str) or not n.strip() for n in raw):raise ValueError('Empty operator stop name')
        result.append(dict(operatorLineId=line_id,lineCode=line['lineShowCode'],lineName=line['lineName'],
                           rawStationNames=raw,stationNames=[NORMALIZATIONS.get(n,n) for n in raw],
                           operatorStationIds=[s['stationId'] for s in stops],
                           interchanges=[dict(stationName=NORMALIZATIONS.get(s['stationName'],s['stationName']),
                                              operatorLineIds=[p['lineId'] for p in s.get('hcLines',[]) if p['lineId']!=line_id]) for s in stops if s.get('isHuanCheng')]))
    if seen!=LINE_IDS:raise ValueError('Known operator scope missing: '+str(LINE_IDS-seen))
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('capture',type=Path)
    parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    raw=args.capture.read_bytes();lines=extract(json.loads(raw.decode('utf-8')))
    result=dict(schemaVersion=1,source=SOURCE,sourceLanding=LANDING,sourceMap=MAP_APP,
                retrievedAt='2026-10-25',captureSha256=hashlib.sha256(raw).hexdigest(),
                extractionStatus='operator_order_reviewed_opening_dates_pending',
                normalizationNotes={'虫雷 岗':'运营方用拆字表示𧒽，不视为另一车站或改名。','庆盛（南沙北站）':'括号标识衔接铁路站；本游戏车站简称庆盛，原文完整保留。'},
                scopeNote='现行匿名查询结果不是截止日开通证据；排除有轨、APM及市域铁路，不把未来时点的新对象提前加入。',lines=lines)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('GZMTR_OPERATOR_ORDERS',len(lines),'paths; opening dates remain separately unverified')


if __name__=='__main__':main()
