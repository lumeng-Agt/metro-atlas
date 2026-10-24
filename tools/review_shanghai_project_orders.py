"""Independently transcribe published 19/22/23 project station orders.

Unreviewed transfer coverage remains an explicit failure, not a declaration
that the city inventory is complete. No expected order is read from chapters.
"""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REVISION='2026.10.24.12'
SOURCE23='https://www.shanghai.gov.cn/gwk/search/content/2d9b25a3bed24964a3739c117926ed58'
SOURCE22='https://www.shanghai.gov.cn/nw15343/20260827/4e90432266924139b00ebfdd685e548b.html'
SOURCE19='https://czj.sh.gov.cn/cmsres/e7/e77ab5e3a70c4a6c91ddac3f3c15485e/0747d825d3f48135737cc1ffa61b2fc9.pdf'


def read(path):return json.loads((ROOT/path).read_text(encoding='utf-8'))
def write(path,value):(ROOT/path).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def main():
    data=read('data/campaigns.json');official=read('data/official_targets_2026-10-01.json')
    city=data['cities']['shanghai'];plans={p['id']:p for p in city['futurePlans']}
    p=plans['sh-line22-chongming-build']
    new_transfer={'id':'future-transfer-sh22-jinji-9','name':'金吉路','complexId':'shanghai-f22-jinjilu',
        'stationInstanceIds':['shanghai-f22-jinjilu__line9-9','shanghai-f22-jinjilu'],
        'lineIds':['shanghai-line9-9','shanghai-line22-22'],'precision':'schematic','source':SOURCE22,
        'sourceNote':'浦东新区政府2026-08-27逐站说明明确金吉路与9号线换乘；使用截止日9号线独立站体，不再以旧地图库缺站为由省略。'}
    p['requiredTransfers']=[t for t in p['requiredTransfers'] if t['id']!=new_transfer['id']]+[new_transfer]
    p.update(source=SOURCE22,sourceTitle='浦东新区政府：22号线8站及金吉路、申江路换乘',
        sourcePublicationDate='2026-08-27',sourceCheckedAt='2026-10-24',
        scopeRevision=REVISION,requiresScopeRecheck=True,
        description='复现崇明线8站，在金吉路、申江路分别建立与既有9、12号线的独立站体换乘。截止日处于调试建设阶段，成果仅记为规划建设完成；不虚构长兴岛其他线路已经建成。')
    plans['sh-line23-phase1-build']['sourceTitle']='上海市住房和城乡建设管理委员会：23号线一期初步设计批复（沪建综规〔2021〕744号）'
    targets=[
        {'id':'sh-line23-phase1','reviewStatus':'verified','constructionOnly':True,
         'source':SOURCE23,'sourcePublicationDate':'2022-09-27','effectiveDocumentDate':'2021-11-22',
         'sourceCheckedAt':'2026-10-24',
         'groups':[{'id':'shanghai-line23-23','scopeType':'stations','stationNames':
            '闵行开发区 文井路 华宁路 金平路 东川路 沪金高速 紫竹高新区 江川东路 紫龙路 放鹤路 吴泾北 墨江路 澄江路 龙吴路 景联路 华泾路 徐浦大桥 龙瑞路 上海植物园 龙启路 龙漕路 上海体育场'.split()}],
         'transfers':['sh-future-transfer-line23-dongchuan','sh-future-transfer-line23-zizhu',
                      'sh-future-transfer-line23-longcao','sh-future-transfer-line23-stadium'],
         'scopeNote':'批复逐站列明22座均为新建地下车站；复用的是站区身份而非共用旧线路站体。实际几何为近似参考。'},
        {'id':'sh-line22-chongming','reviewStatus':'verified','constructionOnly':True,
         'source':SOURCE22,'sourcePublicationDate':'2026-08-27','sourceCheckedAt':'2026-10-24',
         'groups':[{'id':'shanghai-line22-22','scopeType':'stations','stationNames':
                    '金吉路 申江路 高宝路 凌空北路 长兴岛 陈家镇 东滩 裕安'.split()}],
         'transfers':['future-transfer-sh22-jinji-9','future-transfer-sh22-shenjiang-12'],
         'scopeNote':'截止日前政府调试报道逐站列明8站和两个既有地铁换乘，不以调试列车当作历史开通。'},
        {'id':'sh-line19','reviewStatus':'verified','transferReviewStatus':'pending', 'constructionOnly':True,
         'source':SOURCE19,'sourcePublicationDate':'2026-03-20','sourceCheckedAt':'2026-10-24',
         'groups':[{'id':'shanghai-line19-19','scopeType':'stations','stationNames':
                    '虹建路 联曹路 华泾西 华泾路 三林南 凌兆新村 东方体育中心 德州路 后滩 世博大道 世博 华丰路 南码头路 塘桥 潍坊路 商城路 浦东南路 提篮桥 周家嘴路 海伦路 甜爱路 上海外国语大学 凉城路 广灵四路 车站北路 虹湾路 一二八纪念路 呼玛路 江杨南路 泰和路 兰岗路 铁山路 铁通路 宝山站'.split()}],
         'transfers':['future-transfer-sh19-huajingxi-15','future-transfer-sh19-lingzhao-8',
             'future-transfer-sh19-sportcenter','future-transfer-sh19-houtan-7','future-transfer-sh19-shibodadao-13',
             'future-transfer-sh19-tangqiao-4','future-transfer-sh19-shangcheng-9','future-transfer-sh19-pudongnan-2',
             'future-transfer-sh19-tilanqiao-12','future-transfer-sh19-hailun'],
         'scopeNote':'财政局公开项目说明逐站列明34站，报告署2026-03-20。现有10项换乘须实际建成；完整18项换乘及规划交叉的时期核对仍单独留作失败项，不能用站序核对替代。'}]
    rows=official['cities']['shanghai']['projects'];ids={t['id'] for t in targets}
    rows[:]=[p for p in rows if p['id'] not in ids]+targets
    data['contentRevision']=REVISION
    data['contentRevisionNote']='补齐上海19/22/23独立站序核对，补建崇明线金吉路9号线换乘；19号线完整换乘范围尚未放行。'
    write('data/campaigns.json',data);write('data/official_targets_2026-10-01.json',official)
    print('Independent station orders: 34 + 8 + 22; Jinji interchange added; full 19 transfers pending')


if __name__=='__main__':main()
