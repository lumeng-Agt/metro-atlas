"""Add the omitted source-documented 17/28 interchange at Dongdaqiao.

The 6/28 pair is not a three-line 6/17/28 link. Each physical pairing must
be explicit. Long-term R1/R4 and railway interfaces remain separately pending.
"""
from repair_chengdu_historical_phases import read,write
REVISION='2026.10.25.19'
SOURCE='https://zdb.beijing.gov.cn/zdxmjs/gdjtjs/202504/t20250401_4051485.html'
PAIR=dict(id='future-transfer-bj28-dongdaqiao-17',name='东大桥',complexId='beijing-s333',
          stationInstanceIds=['beijing-s333__line17-17','beijing-s333__line28-28'],
          lineIds=['beijing-line17-17','beijing-line28-28'],precision='schematic',source=SOURCE,
          sourceNote='重大项目办原文明确东大桥17／28换乘；各线站体独立，不用已有6／28关系冒充三线联系。')
def main():
    data=read('data/campaigns.json');baseline=read('data/network_baselines_2026-10-01.json');official=read('data/official_targets_2026-10-01.json');spec=read('tools/project_specs/bj-line28.json')
    plan=next(p for p in data['cities']['beijing']['futurePlans'] if p['id']=='bj-line28-build')
    for rows in [plan['requiredTransfers'],spec['transfers']]:
        rows[:]=[t for t in rows if t['id']!=PAIR['id']]+[PAIR.copy()]
        for transfer in rows:
            if transfer['id']=='future-transfer-bj28-dongdaqiao':transfer['sourceNote']='本项仅确认6／28两线站体；17／28、22／28各有独立配对，不能由一对推断其他联系。'
    plan.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    spec['plan'].update(scopeRevision=REVISION,contentRevision=REVISION,requiresScopeRecheck=True)
    expected=next(p for p in official['cities']['beijing']['projects'] if p['id']=='bj-line28')
    if PAIR['id'] not in expected['transfers']:expected['transfers'].append(PAIR['id'])
    expected.update(transferReviewStatus='pending',transferReviewNote='已补东大桥遗漏的17／28独立联系；R1、R4远期预留及国铁／市郊背景接口尚未完成分层审查，不解除整项目门槛。')
    expected.setdefault('additionalSources',[])
    if SOURCE not in expected['additionalSources']:expected['additionalSources'].append(SOURCE)
    for doc in [data,baseline]:doc['contentRevision']=REVISION
    data['contentRevisionNote']='补齐东大桥17／28独立换乘；8组明确地铁配对，远期预留与铁路接口仍分开审核。'
    write('data/campaigns.json',data);write('data/network_baselines_2026-10-01.json',baseline);write('data/official_targets_2026-10-01.json',official);write('tools/project_specs/bj-line28.json',spec)
    print('Beijing28: explicit 17/28 pair added; complete interchange review remains pending')
if __name__=='__main__':main()
