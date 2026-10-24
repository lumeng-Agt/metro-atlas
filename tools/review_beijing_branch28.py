"""Independent engineering-name scopes, separate from final naming decisions."""
from repair_chengdu_historical_phases import read,write

BRANCH='https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202310/t20231009_3272556.html'
APPROVAL='https://fgw.beijing.gov.cn/fgwzwgk/ysqzzdgk/202401/t20240118_3538824.htm'
DRAWING='https://xinwen.bjd.com.cn/content/s688c78d3e4b0aabe0a046da1.html'
SCOPE28='https://www.beijing.gov.cn/ywdt/gzdt/202401/t20240106_3527804.html'


def main():
    official=read('data/official_targets_2026-10-01.json');bj=official['cities']['beijing']
    expected=[dict(id='bj-line1-branch',reviewStatus='verified',constructionOnly=True,source=BRANCH,
        sourcePublicationDate='2023-10-09',additionalSources=[APPROVAL],
        groups=[dict(id='beijing-lineearly0',scopeType='stations',allowReverse=True,
            stationNames='八角游乐园 体育场南街 园博园西门 张郭庄 西二区 后吕村 云岗 王佐 民族大学 青龙湖东'.split())],
        transfers=['future-transfer-bj1b-zhangguozhuang-14'],
        scopeNote='工程版本9座新站与1座既有改造站。命名公示与正式命名区分，11号线体育场南仅预留，不冒充已建设换乘。'),
        dict(id='bj-line28',reviewStatus='verified',constructionOnly=True,transferReviewStatus='pending',
            source=DRAWING,sourcePublicationDate='2025-08-01',additionalSources=[SCOPE28],
            groups=[dict(id='beijing-line28-28',scopeType='stations',allowReverse=True,stationNames=
                '东大桥 京广桥 光华路 核心区 大望路 北京东站 大郊亭 广渠路 广渠东路'.split())],
            stationNamingAliases={'核心区':'景辉街','北京东站':'茂兴西路'},
            scopeNote='独立转录2025一体化图的9站物理顺序，工程名保持原身份；图上景辉街和茂兴西路为别称，不自动改名。国铁北京东衔接不伪装成地铁换乘；光华路R4远期关系未制作，完整换乘审核保留失败。',
            transfers=['future-transfer-bj28-dongdaqiao','future-transfer-bj28-jingguangqiao-10',
                'future-transfer-bj28-dawanglu','future-transfer-bj28-dajiaoting-7',
                'future-transfer-bj28-dongdaqiao-22','future-transfer-bj28-jingguangqiao-22','future-transfer-bj28-dawanglu-14'])]
    ids={p['id'] for p in expected}
    bj['projects']=[p for p in bj['projects'] if p['id'] not in ids]+expected
    # An extension's authored direction can be reversed when it joins an
    # existing path. This accepts the same ordered physical scope, not a skip.
    for p in bj['projects']:
        if p['id'] in ['bj-new-airport','bj-line12','bj-line3-phase1']:
            for g in p['groups']:g['allowReverse']=True
    write('data/official_targets_2026-10-01.json',official)
    data=read('data/campaigns.json');plans=data['cities']['beijing']['futurePlans']
    plan=next(p for p in plans if p['id']=='bj-line28-build')
    for t in plan.get('requiredTransfers',[]):
        if t['id']=='future-transfer-bj28-dongdaqiao':
            t['sourceNote']='东大桥既有6/17与在建22/28组成枢纽；本项确认6/17/28，22/28另行明确确认，各站体独立。'
    write('data/campaigns.json',data)
    spec=read('tools/project_specs/bj-line28.json')
    for t in spec['transfers']:
        if t['id']=='future-transfer-bj28-dongdaqiao':t['sourceNote']=plan['requiredTransfers'][0]['sourceNote']
    write('tools/project_specs/bj-line28.json',spec)
    print('Beijing branch10 + line28 nine stops independently reviewed; unmade future interchange still fails')


if __name__=='__main__':main()
