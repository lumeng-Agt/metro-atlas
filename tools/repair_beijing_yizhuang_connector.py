"""Author the reviewed connector corridor and a non-operating through preview.

The engineering scope comes from the final EIA and approved project, not from
the chapter. Coordinate samples follow licensed roads/rail references and
remain explicitly approximate. Existing operating routes are never replaced.
"""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
EIA='https://www.bii.com.cn/file/2025/10/21/1761030868162.pdf'
APPROVAL='https://fgw.beijing.gov.cn/fgwzwgk/ysqzzdgk/202510/t20251020_4232624.htm'
START='https://xinwen.bjd.com.cn/content/s6a1f9897d5de97bd745f150c.html'
FIVE='天通苑北 天通苑 天通苑南 立水桥 立水桥南 北苑路北 大屯路东 惠新西街北口 惠新西街南口 和平西桥 和平里北街 雍和宫 北新桥 张自忠路 东四 灯市口 东单 崇文门 磁器口 天坛东门 蒲黄榆 刘家窑 宋家庄'.split()
YIZHUANG='肖村 小红门 旧宫 亦庄桥 亦庄文化园 万源街 荣京东街 荣昌东街 同济南路 经海路 次渠南 次渠 亦庄火车站'.split()


def read(p):return json.loads(p.read_text(encoding='utf-8'))
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def main():
    city=next(c for c in read(ROOT/'data/cities.json')['cities'] if c['id']=='beijing')
    geography={s['id']:s for s in city['stations']}
    config=read(ROOT/'data/campaigns.json')['cities']['beijing']
    cutoff=next(c for c in config['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    def stop(line,name):
        group=next(g for g in cutoff['lineGroups'] if g['historicalLineId']==line)
        id_=next(s for s in group['stationIds'] if group.get('stationNames',{}).get(s,geography[s]['name'])==name)
        return id_,group.get('stationInstances',{}).get(id_,id_)
    song,song_body=stop('beijing-line5-5','宋家庄')
    xiao,xiao_body=stop('beijing-route-24','肖村')
    # Public final EIA pp19–20 describes the eastern-side corridor, unlike an
    # early plan that used the depot. These are approximate game waypoints.
    endpoints=[dict(id='bj-yz-song-five-existing',name='宋家庄5号线既有接头',stationId=song,stationInstanceId=song_body,side='outward'),
               dict(id='bj-yz-turnback-north',name='折返区间北接口（非车站）',latlng=[39.83912,116.43272],toleranceM=80,depthM=-15),
               dict(id='bj-yz-turnback-south',name='折返区间南接口（非车站）',latlng=[39.83665,116.43272],toleranceM=80,depthM=-15),
               dict(id='bj-yz-xiaocun-existing',name='肖村亦庄线既有接头',stationId=xiao,stationInstanceId=xiao_body,side='outward')]
    sections=[dict(fromId=endpoints[0]['id'],toId=endpoints[1]['id'],points=[geography[song]['latlng'],[39.84440,116.42794],[39.84428,116.43194],[39.84371,116.43215],[39.84160,116.43260],endpoints[1]['latlng']],corridorToleranceM=120),
              dict(fromId=endpoints[1]['id'],toId=endpoints[2]['id'],points=[endpoints[1]['latlng'],endpoints[2]['latlng']],corridorToleranceM=100),
              dict(fromId=endpoints[2]['id'],toId=endpoints[3]['id'],points=[endpoints[2]['latlng'],[39.83660,116.43648],[39.83662,116.44067],[39.83645,116.44180],[39.83525,116.44270],geography[xiao]['latlng']],corridorToleranceM=120)]
    note='按已批准的肖村—宋家庄改造范围，复现两端改造接头、中间新建和折返区间走廊，不新增客运站。线路沿宋家庄车辆基地东侧及郭家庄路附近；坐标仅为许可地理参照的近似走廊，不是施工中心线，折返配线和埋深为示意。原亦庄线宋家庄段和现状服务保留，未来贯通仅生成未开放的线路关系。10号线跨线预留不计为已建直连；同台换乘结构仍需单独核对。'
    group=dict(taskId='project:bj-yizhuang-connector:track',taskKind='engineering_track',coverageGroupId='bj-yizhuang-connector-engineering',name='亦庄—5号线联络轨道',historicalLineId='beijing-yizhuang-five-connector',color='#BA5B35',stationIds=[song,xiao],stationInstances={song:song_body,xiao:xiao_body},source=EIA,toleranceM=100,alignmentPrecision='corridor_only',precisionNote=note,engineeringEndpoints=endpoints,engineeringSegments=sections,officialLengthM=2700)
    ids=[];instances={};names={}
    for line,order in [('beijing-line5-5',FIVE),('beijing-route-24',YIZHUANG)]:
        for name in order:
            id_,body=stop(line,name);ids.append(id_);instances[id_]=body;names[id_]=name
    service=dict(taskId='project:bj-yizhuang-connector:through',coverageGroupId='bj-yizhuang-five-through',historicalLineId='beijing-yizhuang-five-through',name='5号线—亦庄线未来贯通关系',color='#BA5B35',stationIds=ids,stationInstances=instances,stationNames=names,toleranceM=100,alignmentPrecision='corridor_only',precisionNote=note,constructionVariant=True,source=EIA)
    chapter=dict(id='bj-yizhuang-connector-build',projectIds=['bj-yizhuang-connector'],title='亦庄联络工程 · 改造接头与未来贯通',date='2026-10-01',status='under_construction',projectType='approved_and_under_construction',required=True,exactAlignment='corridor_only',sourceType='official_final_eia_and_project_approval',source=EIA,sourceTitle='亦庄线至5号线、10号线联络工程最终环评及可研批复',sourcePublicationDate='2025-10-21',sourceCheckedAt='2026-10-25',description=note,additionalSources=[APPROVAL,START],operationType='through_connection',operationGuide='先预览工程轨道，保留现状车站和服务；再检查以宋家庄5号线站体衔接肖村的未来贯通关系。完成仅表示规划建设完成，不是现实开通。')
    # Independently transcribed service orders are checked against actual paths,
    # not produced from the chapter's stationIds or preview world.
    expected=dict(id='bj-yizhuang-connector',reviewStatus='verified',transferReviewStatus='pending',source=EIA,sourcePublicationDate='2025-10-21',sourceCheckedAt='2026-10-25',constructionOnly=True,evidenceNote='最终环评第19—20页与可研批复：全长约2.7公里、无新增站、5号线贯通，原亦庄宋家庄—肖村改作出入段线；10号线跨线预留。当前任务校验实体走廊和未来贯通路径，同台结构尚未审核，不解除交付门槛。',groups=[dict(id='bj-yizhuang-connector-engineering',scopeType='engineering',taskKind='engineering_track',stationIds=[song,xiao],engineeringEndpoints=endpoints,engineeringSegments=sections),dict(id='bj-yizhuang-five-through',historicalLineId='beijing-yizhuang-five-through',stationNames=FIVE+YIZHUANG,bodyLineAliases=['beijing-line5-5','beijing-route-24'],bodyLineAliasEvidence=EIA)])
    write(ROOT/'tools/engineering_specs/bj-yizhuang-connector.json',dict(cityId='beijing',contentRevision='2026.10.25.11',chapter=chapter,construction=group,plannedServices=[service],officialTarget=expected))
    pdf=ROOT/'.tmp-remediation-sources/bj-yizhuang-eia202510.pdf'
    write(ROOT/'data/official_evidence/beijing_yizhuang_connector_review.json',dict(source=EIA,projectApproval=APPROVAL,constructionStart=START,retrievedAt='2026-10-25',sha256=hashlib.sha256(pdf.read_bytes()).hexdigest(),bytes=pdf.stat().st_size,locators=['最终环评19—20页线路及既有线变化','PDF27页走向说明','PDF30页10号线跨线预留'],scopeNote=note,licensedReference=dict(license='OpenStreetMap ODbL',crs='WGS84',ways=[127022171,152595432,814609386],purpose='既有5号线接头、基地东边界与郭家庄路走廊核对；不宣称测绘精度')))
    print('AUTHORED_SPEC bj-yizhuang-connector; existing services are not changed')


if __name__=='__main__':main()
