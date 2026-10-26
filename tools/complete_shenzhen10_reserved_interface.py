"""Author the one sourced terminal interface without inventing a through line."""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write

REVISION='2026.10.26.1'
PLAN='https://www.szmc.net/shentiejianshe/ditieguihua/202604/105774.html'
RELATION='https://www.lg.gov.cn/bmzz/phjdb/csjs/dljs/content/post_1609620.html'


def main():
    data=read('data/campaigns.json');baseline=read('data/network_baselines_2026-10-01.json');official=read('data/official_targets_2026-10-01.json')
    city=data['cities']['shenzhen'];plan=next(p for p in city['futurePlans'] if p['id']=='sz-line10-east-build')
    target=next(p for p in official['cities']['shenzhen']['projects'] if p['id']=='sz-line10-east-shenzhen')
    pair=dict(id='sz10-huanggekeng-reserved-16',name='黄阁坑',complexId='shenzhen-s379',
              lineIds=['shenzhen-line10-11','shenzhen-line16-16'],stationInstanceIds=['shenzhen-s379__line10-11','shenzhen-s379__line16-16'],
              status='reserved',precision='schematic',source=PLAN,reservationEvidence=RELATION,
              sourceNote='2026五期图核对深圳段及黄阁坑终点；2019政府说明只佐证与16号线衔接，不沿用旧全线范围。',
              note='五期仅建设深莞边界两侧深圳段；黄阁坑预留10／16号线接口，不计入已开放换乘，不补造中间东莞段。')
    plan['requiredTransfers']=[pair];plan.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    # The independent scope repeats the explicitly reviewed identity and type,
    # rather than deriving completeness from a generic engineering category.
    target['reservedTransfers']=[deepcopy(pair)];target['transferReviewStatus']='verified'
    for group in target['groups']:group['historicalLineId']='shenzhen-line10-11'
    target['evidenceNote']='官方五期图为深圳段2.9公里、黄阁坑单一新站及终点规划换乘；2019政府说明佐证接入16号线的关系，不沿用其9.8公里旧全线范围。两个深圳工程区段与预留站体分别检查，不虚构贯通、换乘开放或未来日期。'
    spec=read('tools/engineering_specs/sz-line10-east-shenzhen.json')
    spec.update(contentRevision=REVISION,reservedTransfers=[deepcopy(pair)],officialTarget=deepcopy(target))
    for document in (data,baseline):
        if tuple(map(int,REVISION.split('.')))>=tuple(map(int,document.get('contentRevision','0').split('.'))):document['contentRevision']=REVISION
    if data['contentRevision']==REVISION:data['contentRevisionNote']='广州赤岗恢复2026补站；深圳10东黄阁坑增加实际预留换乘操作，保持工程与开放网络分离。五城独立全量审核仍未通过。'
    write('data/campaigns.json',data);write('data/network_baselines_2026-10-01.json',baseline);write('data/official_targets_2026-10-01.json',official)
    write('tools/engineering_specs/sz-line10-east-shenzhen.json',spec)
    print('SZ10 terminal reservation authored; no active interchange or Dongguan through route')


if __name__=='__main__':main()
