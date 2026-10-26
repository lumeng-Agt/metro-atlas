"""Independent transcription of the final EIA's metro interfaces and name chain.

Do not derive the answer from the chapter. Intercity/suburban railway interfaces
are recorded as excluded background, not silently called missing metro stations.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write

EIA='https://www.bii.com.cn/file/2025/03/03/1740974915275.pdf'
FIELD='https://finance.sina.com.cn/jjxw/2025-10-02/doc-infsmxpw6533299.shtml'
NAMING='https://yewu.ghzrzyw.beijing.gov.cn/zkdncms/cxghphgsdmgg/esSearchDetail/31f464cd7a73878d2e5efed190a8559e'
REV='2026.10.26.11'

# Engineering interchange names are matched with independently reviewed
# geographical identities. The current and future 13-line services coexist.
ROWS=[
 ('beishatan-15','北沙滩','beijing-s3','beijing-line15-15','beijing-s3'),
 ('xiaoying-changping','清河小营桥','beijing-s250','beijing-route-20','beijing-s250'),
 ('qinghe-13','清河','beijing-s96','beijing-line13-13','beijing-s96__line13-13'),
 ('qinghe-changping','清河','beijing-s96','beijing-route-20','beijing-s96__line20'),
 ('qinghe-capacity13A','清河','beijing-s96','beijing-capacity13A','beijing-s96__line13-13'),
 ('newlongze-capacity13A','新龙泽／龙泽西','beijing-open18-longzexi','beijing-capacity13A','beijing-open18-longzexi'),
 ('newlongze-capacity13B','新龙泽／龙泽西','beijing-open18-longzexi','beijing-capacity13B','beijing-open18-longzexi__capacity13B'),
 ('newlongze-18','新龙泽／龙泽西','beijing-open18-longzexi','beijing-line18-18','beijing-open18-longzexi'),
]

def main():
    definitions=[dict(id='future-transfer-bj19-'+key,name=name,complexId=sid,
        lineIds=['beijing-line19-19',line],stationInstanceIds=[sid+'__north19',body],
        transferKind='interchange',precision='schematic',source=EIA,
        sourceNote='最终环评表2-1-3明确地铁接口；工程名新龙泽经北郊农场桥关联正式龙泽西，不关联旧龙泽或还建龙泽。换乘结构为示意，不宣称已开放。')
        for key,name,sid,line,body in ROWS]
    targets=read('data/official_targets_2026-10-01.json')
    target=next(p for p in targets['cities']['beijing']['projects'] if p['id']=='bj-line19-north-phase2')
    target.update(transferDefinitions=definitions,transferReviewStatus='verified',
        transferReviewNote='按最终环评表2-1-3逐接口及独立命名链核对地铁范围；清河当前13、未来13A，以及新龙泽13A/13B和已开放18服务分别引用真实站体。市郊铁路与北部联络线记录为范围外背景，未冒充地铁换乘。')
    campaign=read('data/campaigns.json')
    plan=next(p for p in campaign['cities']['beijing']['futurePlans'] if p['id']=='bj-line19-north-build')
    by_id={d['id']:d for d in definitions}
    if set(by_id)!={p['id'] for p in plan['requiredTransfers']}:raise ValueError('Chapter interfaces differ from independent EIA transcription')
    for pair in plan['requiredTransfers']:
        # Refuse to turn an authoring discrepancy into a silent content repair.
        expected=by_id[pair['id']]
        for field in ['complexId','lineIds','stationInstanceIds']:
            if pair[field]!=expected[field]:raise ValueError(f'{pair["id"]}: {field} differs')
        pair.update(source=EIA,sourceNote=expected['sourceNote'])
    body='beijing-f19-lifescience-south__north19'
    plan['stationProfiles'][body]['form']='地下三层双岛四线'
    plan['stationProfiles'][body]['note']='最终环评表2-1-3为地下三层双岛四线；原作者误写二层已更正。显示埋深、矩形和展示车型仍为示意。'
    plan.update(scopeRevision=REV,requiresScopeRecheck=True)
    campaign['contentRevision']=REV
    campaign['contentRevisionNote']='19号线北延地铁接口逐组独立核对，区分新龙泽名称沿革和旧龙泽；纠正生命科学园南站公开结构层数。'
    spec=read('tools/project_specs/bj-line19-north.json')
    spec['transfers']=deepcopy(plan['requiredTransfers'])
    spec['plan']['stationProfiles']=deepcopy(plan['stationProfiles'])
    evidence=read('data/official_evidence/beijing19_north_review.json')
    evidence.update(transferReviewStatus='verified',metroTransferDefinitions=definitions,
        eiaInterfaceRows=[dict(station='北沙滩',lines=['15']),dict(station='清河小营桥',lines=['昌平']),
            dict(station='清河',lines=['13','昌平','怀密铁路']),
            dict(station='新龙泽',lines=['13A','13B','东北环市郊铁路']),
            dict(station='生命谷',lines=['东北环市郊铁路','北部联络线'])],
        excludedBackgroundInterfaces=[dict(station='清河',line='怀密铁路'),dict(station='新龙泽',line='东北环市郊铁路'),
            dict(station='生命谷',line='东北环市郊铁路'),dict(station='生命谷',line='北部联络线')],
        namingEvidence=[dict(source=FIELD,date='2025-10-02',publisher='北京日报',reporter='袁璐',
            sourceType='firsthand_construction_site_report_republished_by_sina',
            sha256='f910a1939e8a1c050625460d559590500019e7a177577dec2720727cdb0c2419',
            assertion='工程名新龙泽已定名北郊农场桥；13号线04标施工现场采访。'),
            dict(source=NAMING,effectiveDate='2025-12-25',approval='2025（昌）地名命字0016号',
                assertion='北郊农场桥更名龙泽西；沿规划回创路，不是旧龙泽或还建龙泽。',
                retainedRecord='res://data/official_evidence/beijing13_capacity_review.json')],
        current18Source='https://jtw.beijing.gov.cn/zmhd/jtdjt/202512/t20251224_4360655.html',
        profileCorrection=dict(station='生命科学园南',form='地下三层双岛四线',source=EIA,pdfPage=33),
        scopeNote='Metro project interfaces reviewed. Suburban/intercity railway interfaces remain documented background; approval does not mean future metro transfers are currently open.')
    for path,value in [('data/official_targets_2026-10-01.json',targets),('data/campaigns.json',campaign),
                       ('tools/project_specs/bj-line19-north.json',spec),('data/official_evidence/beijing19_north_review.json',evidence)]:write(path,value)
    print('BJ19: 8 independently defined metro pairings, railway scope explicit; no station relocation')

if __name__=='__main__':main()
