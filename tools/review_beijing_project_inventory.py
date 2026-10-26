"""Transcribe an independently published minimum project roster, not task data.

The annual key-project list is not the entire approved construction programme.
Keep that distinction and the broader inventory gate explicit.
"""
from repair_chengdu_historical_phases import read, write

SOURCE='https://fgw.beijing.gov.cn/fgwzwgk/2024zcwj/ghjhwb/qt/202602/W020260203349484131373.pdf'
ROWS=[
    (104,'bj-line19-north-phase2','轨道交通19号线二期工程（北延及北延支线）'),
    (105,'bj-yizhuang-taihu-infill','轨道交通亦庄线台湖车辆段增设站点工程'),
    (106,'bj-line15-guozhan-infill','轨道交通15号线新国展地区增设站点'),
    (107,'bj-yizhuang-connector','轨道交通亦庄线-5号线、10号线联络线'),
    (108,'bj-line12','轨道交通12号线'),
    (109,'bj-line22','轨道交通22号线（平谷线）工程北京段'),
    (110,'bj-line13-capacity','轨道交通13号线扩能提升工程'),
    (111,'bj-line3-phase1','轨道交通3号线一期'),
    (112,'bj-line1-branch','轨道交通1号线支线'),
    (113,'bj-m101-phase1','轨道交通M101线一期'),
    (114,'bj-line28','轨道交通28号线（CBD线）'),
    (115,'bj-new-airport','轨道交通新机场线北延'),
    (116,'bj-airport-wangjingnan-infill','轨道交通首都机场线增设望京南站工程'),
]

def main():
    roster=[dict(projectId=pid,officialName=name,source=SOURCE,sourcePublicationDate='2026-02-03',
                 pdfPage=9 if ordinal<=115 else 10,sourceOrdinal=ordinal,required=True)
            for ordinal,pid,name in ROWS]
    roster.append(dict(projectId='bj-r4-north-phase1',officialName='R4线一期北段',required=True,
        source='https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202606/t20260602_4681873.html',sourcePublicationDate='2026-06-02',
        note='年初重点工程名单之后开工，单独补入，不能用年度名单排除。'))
    data=read('data/official_targets_2026-10-01.json');bj=data['cities']['beijing']
    bj['sourceProjectInventory']=roster
    bj['inventoryReviewNote']='2026重点工程名单的13项轨道项目和6月开工R4必须逐项收录；这是独立的最小清单，并非所有有效批准项目已穷尽。11号线二期等更广范围继续核对，不据此将inventoryReviewStatus改为verified。'
    write('data/official_targets_2026-10-01.json',data)
    write('data/official_evidence/beijing2026_minimum_project_roster.json',dict(cutoff='2026-10-01',reviewedAt='2026-10-26',
        source=SOURCE,pdfSha256='204fff7c52396b9debe66e4db8f098f0453fbd7003e7016e2701b51abddb12ca',pdfPages=[9,10],
        rows=roster,scope='minimum_independently_published_inventory_not_all_approved_projects',
        note='人工逐行读取重点工程原表；项目身份与章节分开维护。R4来自6月独立开工公告。未把名单内其余铁路、公路计为地铁任务。'))

if __name__=='__main__':main()
