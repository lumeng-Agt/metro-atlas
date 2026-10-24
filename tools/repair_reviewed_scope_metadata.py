"""Keep phase metadata consistent with already independently checked scopes."""
from repair_chengdu_historical_phases import read, write

REVISION = '2026.10.24.31'
FACTS = [
    ('shanghai','shanghai-line8-8','2012-09-28','https://news.sina.com.cn/o/2012-09-26/145925258090.shtml',None),
    ('shanghai','shanghai-line9-9','2017-12-30','https://www.cnr.cn/shanghai/tt/20171227/t20171227_524078638.shtml',None),
    ('shenzhen','shenzhen-line10-11','2022-10-28','https://www.szmc.net/home/xinwenzhongxin/gongsixinwen/202210/101706.html',None),
    ('guangzhou','guangzhou-line3-3','2006-12-30','https://news.sina.cn/sa/2006-12-27/detail-ikknscsk1576612.d.html','天河客运站 五山 华师 岗顶 石牌桥 体育西路'.split()),
    ('guangzhou','guangzhou-line14-14','2017-12-28','https://www.cnr.cn/gd/gdkx/20171227/t20171227_524077892.shtml','新和 红卫 新南 枫下 知识城 何棠下 旺村 汤村 镇龙北 镇龙'.split()),
    ('guangzhou','guangzhou-line18-15','2021-09-28','https://www.cnr.cn/gd/guangdongyaowen/20210928/t20210928_525617567.shtml',None),
    ('chengdu','chengdu-line27-15','2024-12-19','https://news.chengdu.cn/2024/1218/2459886.shtml',None),
    ('chengdu','chengdu-line4-4','2017-06-02','https://static.sse.com.cn/bond/bridge2/disclosure/announcement/c/202606/9dbefc_20260618_SLKT.pdf',None),
    ('chengdu','chengdu-line5-5','2019-12-27','https://static.sse.com.cn/bond/bridge2/disclosure/announcement/c/202606/9dbefc_20260618_SLKT.pdf',None),
]


def main():
    data=read('data/campaigns.json');official=read('data/official_targets_2026-10-01.json')
    gz=official['cities']['guangzhou']['cutoffNetwork']['groups']
    if not any(g.get('historicalLineId',g['id'])=='guangzhou-line18-15' for g in gz):
        gz.append(dict(id='guangzhou-line18-15',historicalLineId='guangzhou-line18-15',scopeType='stations',
            stationNames='万顷沙 横沥 番禺广场 南村万博 沙溪 龙潭 磨碟沙 冼村'.split(),allowReverse=True))
    for cid,line_id,date,source,pattern in FACTS:
        matches=[g for g in official['cities'][cid]['cutoffNetwork']['groups']
                 if g.get('historicalLineId',g['id'])==line_id and (pattern is None or g['stationNames']==pattern)]
        assert matches,(cid,line_id)
        for group in matches:
            group.update(lastPhysicalOpeningDate=date,lastPhysicalOpeningSource=source,
                physicalOpeningNote='此字段只核对该站序分支的物理站范围齐备时间；更名、短交路和线路运行方式分别检查。')
    # These are source-authored two-end/branch extension ranges, not whole
    # modern snapshots. Add the metadata the range validator requires, after
    # proving that the genuinely new stations form one contiguous run.
    ids={'chengdu-network-milestone-2017-12-26','chengdu-historical-milestone-2018-03-18',
         'chengdu-network-milestone-2018-12-26','chengdu-opening-eight27-2024'}
    built={}
    for chapter in sorted(data['cities']['chengdu']['chapters'],key=lambda c:c['date']):
        for group in chapter.get('lineGroups',[]):
            line=group['historicalLineId'];order=group['stationIds'];previous=built.setdefault(line,set())
            if chapter['id'] in ids and previous:
                new=[i for i,s in enumerate(order) if s not in previous]
                assert new and new==list(range(new[0],new[-1]+1)),group['taskId']
                group.update(constructionScope='new_contiguous_range', sourceStationIds=order.copy(),
                    sourceStationInstances=group.get('stationInstances',{}).copy(),
                    constructionScopeNote='已核对来源中的本期连续扩建范围，包含既有端站接头；不是现代全线的重新建设。')
            previous.update(order)
    data.update(contentRevision=REVISION,contentRevisionNote='明确已核验分支各自的物理开放终点日期，补齐成都两端及支线扩建范围元数据；未核验内容仍不能取得完整交付资格。')
    write('data/campaigns.json',data);write('data/official_targets_2026-10-01.json',official)
    print('Reviewed physical-opening dates are per service pattern; existing dated extension ranges explicitly identified')


if __name__=='__main__':main()
