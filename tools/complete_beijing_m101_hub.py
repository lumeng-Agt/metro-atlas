"""Build explicit M101/6/22 hub relationships, not a shared station body.

The 2024 municipal account names Line6 and M101 at the Line22 city-subcenter
interchange. The M101 EIA treats the same hub as a seven-line interchange.
Longer-term and railway interfaces require their own separate review.
"""
from repair_chengdu_historical_phases import read,write
REVISION='2026.10.25.20'
SOURCE='https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202407/t20240717_3751316.html'
EIA='https://www.bii.com.cn/Portals/0/AttachUpload/pdf/2023052616063981.pdf'
PAIRS=[dict(id='future-transfer-bj-m101-hub-'+label,name='城市副中心枢纽',complexId='beijing-s322',
            stationInstanceIds=['beijing-f101-fuzhongxin',body],lineIds=['beijing-line-m101',line],precision='schematic',source=SOURCE,
            sourceNote='同一交通枢纽的独立站体联系，通道为示意；不移动北运河东或M101站体，不共用站厅或轨道。')
       for label,body,line in [('line6','beijing-s322','beijing-line6-6'),('line22','beijing-s322__line22-22','beijing-line22-22')]]
def main():
    data=read('data/campaigns.json');baseline=read('data/network_baselines_2026-10-01.json');official=read('data/official_targets_2026-10-01.json');spec=read('tools/project_specs/bj-m101-phase1.json')
    city=data['cities']['beijing'];plan=next(p for p in city['futurePlans'] if p['id']=='bj-m101-phase1-build')
    city.setdefault('stationComplexAliases',{})['beijing-f101-fuzhongxin']='beijing-s322'
    city.setdefault('stationComplexAliasSources',{})['beijing-f101-fuzhongxin']=dict(source=SOURCE,additionalSource=EIA,sourceCheckedAt='2026-10-25',note='同一副中心交通枢纽的逻辑身份；各线物理站体、工程名称、位置与站端全部独立保留。')
    ids={p['id'] for p in PAIRS}
    for rows in [plan['requiredTransfers'],spec['transfers']]:rows[:]=[t for t in rows if t['id'] not in ids]+[p.copy() for p in PAIRS]
    plan.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    spec['plan'].update(scopeRevision=REVISION,contentRevision=REVISION,requiresScopeRecheck=True)
    expected=next(p for p in official['cities']['beijing']['projects'] if p['id']=='bj-m101-phase1')
    expected['transfers']=list(dict.fromkeys(expected.get('transfers',[])+[p['id'] for p in PAIRS]))
    expected.update(transferReviewStatus='pending',transferReviewNote='已补城市副中心6／22独立联系；环评6处换乘站还涉及M102、M103、M104、R1、区域快线及铁路预留，全量分层审查尚未完成，不能仅凭14站通过视为项目完整。')
    if SOURCE not in expected.setdefault('additionalSources',[]):expected['additionalSources'].append(SOURCE)
    for doc in [data,baseline]:doc['contentRevision']=REVISION
    data['contentRevisionNote']='M101城市副中心枢纽补6／22独立换乘，保留各线物理站体；其余远期预留仍保留审核失败。'
    write('data/campaigns.json',data);write('data/network_baselines_2026-10-01.json',baseline);write('data/official_targets_2026-10-01.json',official);write('tools/project_specs/bj-m101-phase1.json',spec)
    print('M101: two explicit hub pairings; full future-reserve review remains pending')
if __name__=='__main__':main()
