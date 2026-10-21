#!/usr/bin/env python3
"""Build the cutoff-date network inventory from the bundled map relations.

The generated inventory intentionally keeps official operating scope and OSM
map geometry as separate evidence. It is not a substitute for historical
station-by-station opening events.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


CITY_SOURCES: dict[str, dict[str, Any]] = {
    "shanghai": {
        "name": "上海",
        "officialRouteCount": 18,
        "countBasis": "截至2026年4月公开运营表列出1—18号线；市域机场线、磁浮及浦江线另计。",
        "sources": [
            {"title": "上海地铁全网首末班车时刻表（2026年4月）", "url": "https://www.shanghai.gov.cn/nw17239/20260413/d8e14c16213246eba8fac7c23b2b04af.html", "supports": "运营线路清单。"},
            {"title": "轨交18号线二期今开通", "url": "https://www.shanghai.gov.cn/nw4411/20251227/b69b7008d2e647f7a3cab7e160ffe225.html", "supports": "18号线二期开通范围；江杨南路站暂未开放。"},
        ],
        "officialStationCount": None,
        "stationCountBasis": "官方不同材料对站点总数采用运营站、线网站或轨道交通综合口径；本基准不把这些数字与OSM去重站点数直接相减。",
        "recentMilestones": [
            {"id": "shanghai-2025-12-27-line18-phase2", "date": "2025-12-27", "title": "18号线二期宝山段开通初期运营", "routeIds": ["shanghai-r18"], "source": "https://www.shanghai.gov.cn/nw4411/20251227/b69b7008d2e647f7a3cab7e160ffe225.html"},
        ],
        "excludedStations": {"shanghai-r18": [{"name": "江杨南路", "reason": "截至截止日仍暂不同步开通", "source": "https://www.shanghai.gov.cn/nw4411/20251227/b69b7008d2e647f7a3cab7e160ffe225.html"}]},
        "projects": [
            {"id": "sh-line19", "name": "19号线", "projectType": "under_construction", "status": "在建", "source": "https://www.shanghai.gov.cn/nw4411/20260806/dede926ed5044859b3f542fe8e003b0a.html", "sourceTitle": "轨道交通19号线进度上新", "note": "2026年8月官方进度报道确认土建施工仍在推进；不计入2026-10-01已开通路网。"},
            {"id": "sh-line20-phase1", "name": "20号线一期", "projectType": "under_construction", "status": "在建", "source": "https://www.shanghai.gov.cn/nw17239/20260819/5103cdd705c64ae78eb3bbfee10cb1e4.html", "sourceTitle": "轨道交通20号线首台盾构顺利始发", "note": "2026年8月官方报道确认一期施工及盾构始发。"},
            {"id": "sh-line20-east", "name": "20号线东延伸", "projectType": "under_construction_or_planned", "status": "十五五建设方向", "source": "https://www.shanghai.gov.cn/nw12344/20260210/86c10a3ea525407e84d4d7354c8fcb4e.html", "sourceTitle": "上海市国民经济和社会发展第十五个五年规划纲要", "note": "规划提出加快建设20号线等，未发布可供逐站复现的完整地理蓝图。", "playabilityStatus": "policy_only_not_playable", "playabilityNote": "十五五建设方向，仅有规划层面表述，未发布逐站工程蓝图。"},
            {"id": "sh-line21", "name": "21号线一期及东延伸", "projectType": "under_construction", "status": "在建", "source": "https://www.shanghai.gov.cn/nw48306/20250123/db8109b860ae4c5cbcc0ae9e22504f67.html", "sourceTitle": "2025年上海市重大工程清单", "note": "列入重大工程在建项目；按项目分期呈现，非市域铁路。"},
            {"id": "sh-line23-phase1", "name": "23号线一期", "projectType": "under_construction", "status": "在建", "source": "https://www.shanghai.gov.cn/nw48306/20250123/db8109b860ae4c5cbcc0ae9e22504f67.html", "sourceTitle": "2025年上海市重大工程清单", "note": "重大工程清单列为在建，规划范围为上海体育场站—闵行开发区站。"},
            {"id": "sh-line15-south", "name": "15号线南延伸", "projectType": "under_construction", "status": "在建", "source": "https://www.shanghai.gov.cn/nw48306/20250123/db8109b860ae4c5cbcc0ae9e22504f67.html", "sourceTitle": "2025年上海市重大工程清单", "note": "重大工程清单列为在建；终点范围依据公开项目名称，不将其作为已开通站点。"},
            {"id": "sh-line13-west-east", "name": "13号线西延伸、东延伸", "projectType": "under_construction", "status": "在建", "source": "https://www.shanghai.gov.cn/nw4411/20250724/478b3e2e1ac44d248d1b31022f234b5b.html", "sourceTitle": "浦东多个重大工程项目火热推进", "note": "官方建设进展将两段均列入实施项目；具体站位须按各段批复及工程资料分别建模。"},
            {"id": "sh-line12-west", "name": "12号线西延伸", "projectType": "under_construction_or_planned", "status": "规划建设方向", "source": "https://www.shanghai.gov.cn/nw12344/20260210/86c10a3ea525407e84d4d7354c8fcb4e.html", "sourceTitle": "上海市国民经济和社会发展第十五个五年规划纲要", "note": "列入规划推进方向；本地尚无经核对的可玩站点蓝图。", "playabilityStatus": "policy_only_not_playable", "playabilityNote": "规划建设方向，未发布逐站工程蓝图。"},
            {"id": "sh-line22-chongming", "name": "22号线（崇明线）", "projectType": "under_construction", "status": "在建", "source": "https://www.shanghai.gov.cn/nw15343/20250724/478b3e2e1ac44d248d1b31022f234b5b.html", "sourceTitle": "浦东多个重大工程项目火热推进", "note": "官方报道确认车站土建施工；市域线/城际属性与市区地铁分开统计。"},
        ],
    },
    "beijing": {
        "name": "北京",
        "officialRouteCount": 30,
        "countBasis": "北京市政府2025年12月报道口径：运营线路30条、车站539座；含线路／区段运营统计口径。",
        "sources": [
            {"title": "三条地铁新线开通首日", "url": "https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202512/t20251228_4370895.html", "supports": "2025年12月开通的17号线中段、18号线、6号线南延，以及30条运营线路统计。"},
            {"title": "2026年北京市轨道交通建设安排", "url": "https://www.beijing.gov.cn/ywdt/gzdt/202601/t20260122_4455138.html", "supports": "2026年平谷线（22号线）计划及已开通网络里程口径。"},
        ],
        "officialStationCount": 539,
        "stationCountBasis": "北京市政府2025-12-27报道的运营车站数；2026-01王京西站另有开通事件，统计时点不同。该数与OSM去重站点数口径不完全相同。",
        "recentMilestones": [
            {"id": "beijing-2025-12-27-openings", "date": "2025-12-27", "title": "17号线中段、18号线、6号线南延开通", "routeIds": ["beijing-r17", "beijing-r18", "beijing-r6"], "source": "https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202512/t20251228_4370895.html"},
            {"id": "beijing-2026-01-31-wangjingxi", "date": "2026-01-31", "title": "17号线望京西站开通，形成三线换乘", "routeIds": ["beijing-r17"], "source": "https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202601/t20260130_4477003.html"},
        ],
        "excludedStations": {},
        "projects": [
            {"id": "bj-line22", "name": "轨道交通22号线（平谷线）", "projectType": "under_construction", "status": "在建", "source": "https://zdb.beijing.gov.cn/zdxmjs/gdjtjs/202608/t20260825_4836149.html", "sourceTitle": "京冀首条跨省地铁进入空载试运行", "note": "2026年8月仍在空载试运行，按截止日不计入已开通路网；线路跨北京与河北三河。"},
            {"id": "bj-m101-phase1", "name": "M101线一期", "projectType": "under_construction", "status": "在建", "source": "https://zdb.beijing.gov.cn/zfxxgk/zfxxgkzl/fdzdgknr/ghxx/202606/t20260611_4696243.html", "sourceTitle": "北京市重大项目办2026年一季度重点任务进展", "note": "2026年一季度车站、区间和停车场均已开始施工。"},
            {"id": "bj-line3-phase1", "name": "3号线一期（管庄路西口—曹各庄北）", "projectType": "approved_and_under_construction", "status": "建设计划项目", "source": "https://www.beijing.gov.cn/ywdt/gzdt/202602/t20260203_4486799.html", "sourceTitle": "2026年北京市轨道交通建设计划", "note": "列入2026年全面推进的9条（段）项目；站序和工程范围需以项目正式资料入库。"},
            {"id": "bj-line12", "name": "12号线东坝北—东坝北街段", "projectType": "approved_and_under_construction", "status": "建设计划项目", "source": "https://www.beijing.gov.cn/ywdt/gzdt/202602/t20260203_4486799.html", "sourceTitle": "2026年北京市轨道交通建设计划", "note": "列入2026年建设计划的线路段。"},
            {"id": "bj-line28", "name": "28号线", "projectType": "approved_and_under_construction", "status": "建设计划项目", "source": "https://www.beijing.gov.cn/ywdt/gzdt/202602/t20260203_4486799.html", "sourceTitle": "2026年北京市轨道交通建设计划", "note": "列入2026年建设计划；暂不将线路目录当作逐站可玩蓝图。"},
            {"id": "bj-line13-capacity", "name": "13号线扩能提升工程", "projectType": "approved_and_under_construction", "status": "建设计划项目", "source": "https://www.beijing.gov.cn/ywdt/gzdt/202602/t20260203_4486799.html", "sourceTitle": "2026年北京市轨道交通建设计划", "note": "属于既有线扩能改造工程，不作为一条新运营线路重复计数。", "playabilityStatus": "engineering_works_only", "playabilityNote": "13号线扩能提升工程为既有线拆分改造（13A/13B），不是一条有独立站序的新线；本地不重建既有13号线，按扩能工程条目单列。"},
            {"id": "bj-line1-branch", "name": "1号线支线", "projectType": "approved_and_under_construction", "status": "建设计划项目", "source": "https://www.beijing.gov.cn/ywdt/gzdt/202602/t20260203_4486799.html", "sourceTitle": "2026年北京市轨道交通建设计划", "note": "列入2026年建设计划；本地逐站参考几何尚未建立。"},
            {"id": "bj-new-airport", "name": "新机场线（草桥—丽泽商务区）", "projectType": "approved_and_under_construction", "status": "建设计划项目", "source": "https://www.beijing.gov.cn/ywdt/gzdt/202602/t20260203_4486799.html", "sourceTitle": "2026年北京市轨道交通建设计划", "note": "列入2026年建设计划，需与机场快线既有线身份区分。"},
            {"id": "bj-yizhuang-connector", "name": "亦庄线至5号线、10号线联络工程", "projectType": "approved_and_under_construction", "status": "建设计划项目", "source": "https://www.beijing.gov.cn/ywdt/gzdt/202602/t20260203_4486799.html", "sourceTitle": "2026年北京市轨道交通建设计划", "note": "为联络工程，不单独计作新线路；目前没有可供逐站复现的公开地图目标。", "playabilityStatus": "engineering_works_only", "playabilityNote": "亦庄线至5号线、10号线的联络工程，不新增运营车站，按工程条目单列。"},
        ],
    },
    "guangzhou": {
        "name": "广州",
        "officialRouteCount": None,
        "countBasis": "官方2025年度服务质量评价的20条（段）口径排除广佛线和2025年新开通段，不能直接当作2026年10月全网总数。",
        "sources": [
            {"title": "2025年度广州城市轨道交通服务质量评价结果公布", "url": "https://jtj.gz.gov.cn/xwdt/gzdt/content/post_10694346.html", "supports": "官方评价线路口径和排除项；另列截至2025年底运营里程。"},
            {"title": "广州地铁十三号线二期和十四号线二期上新", "url": "https://jtj.gz.gov.cn/ggjt/zfxx/csggjt/gdjt/content/post_10464308.html", "supports": "2025年新线区段及仍在建设的延伸段。"},
        ],
        "officialStationCount": None,
        "stationCountBasis": "市交通局评价统计为线路／区段受评项，并非全网去重车站数；本基准不换算为独立站点总数。",
        "recentMilestones": [
            {"id": "guangzhou-2025-06-29-lines10-12", "date": "2025-06-29", "title": "10号线首通段及12号线东、西段开通", "routeIds": ["guangzhou-r10", "guangzhou-r12"], "source": "https://kjj.gz.gov.cn/xwlb/yw/content/post_10336574.html"},
            {"id": "guangzhou-2025-09-29-lines11-13-14", "date": "2025-09-29", "title": "11号线广州东站及13、14号线新段开通", "routeIds": ["guangzhou-r11", "guangzhou-r13", "guangzhou-r14"], "source": "https://zfcj.gz.gov.cn/zjdt/zjxw/content/mpost_10472692.html"},
        ],
        "excludedStations": {},
        "projects": [
            {"id": "gz-line12-mid", "name": "12号线中段", "projectType": "under_construction", "status": "在建", "source": "https://jtj.gz.gov.cn/xwdt/gzdt/content/post_10694346.html", "sourceTitle": "2025年度广州城市轨道交通服务质量评价结果", "note": "2026年度工作明确持续推进中段建设；未列入已开通范围。"},
            {"id": "gz-line13-phase2-west", "name": "13号线二期西段（朝阳—天河公园）", "projectType": "under_construction", "status": "在建", "source": "https://jtj.gz.gov.cn/hdjl/czc/content/post_10789115.html", "sourceTitle": "广州市交通运输局关于13号线二期西段的情况", "note": "官方公布约25.3公里、19座车站；截至2026年7月仍在建设筹备。"},
            {"id": "gz-line8-north-branch", "name": "8号线北延段支线（江府—纪念堂）", "projectType": "approved_project", "status": "批准建设项目", "source": "https://sthjj.gz.gov.cn/attachment/7/7228/7228124/8784545.pdf", "sourceTitle": "8号线北延段支线工程环境影响报告", "note": "公开环评明确站点与走廊，但本地尚未把官方站序、坐标和版本化蓝图完整整理为可玩任务。"},
        ],
    },
    "shenzhen": {
        "name": "深圳",
        "officialRouteCount": 17,
        "countBasis": "深圳市交通运输局线路页单列1—14、16、20号线及6号线支线；13号线北延于2026-06-28开通，均计入截止日。线路编号与支线分别计数。",
        "sources": [
            {"title": "深圳地铁线路信息（含沿途站点）", "url": "https://jtys.sz.gov.cn/ydmh/jtcx/dtcx_180970/dtxl/content/post_12601090.html", "supports": "1—14、16、20号线及6号线支线的线路／站序清单。"},
            {"title": "地铁13号线二期北延段6月28日开通运营", "url": "https://jtys.sz.gov.cn/ydmh/jtzx/zyhy_1510/content/post_12867344.html", "supports": "13号线北延段实际开通日期、11座车站及与一期贯通。"},
        ],
        "officialStationCount": 452,
        "stationCountBasis": "深圳市交通运输局2026-06-29通车报道公布的全网车站数；与OSM去重站点和线路站次的统计口径需进一步对齐。",
        "recentMilestones": [
            {"id": "shenzhen-2004-12-28-first-network", "date": "2004-12-28", "title": "首期十字网络开通：1号线罗湖—世界之窗、4号线福民—少年宫", "routeIds": ["shenzhen-r1", "shenzhen-r4"], "source": "https://www.szmc.net/szmc_m/home/xinweenzhongxin/gonggaoxinwen/202412/104600.html"},
            {"id": "shenzhen-2009-09-28-line1-extension", "date": "2009-09-28", "title": "1号线增加白石洲、高新园、深大三站", "routeIds": ["shenzhen-r1"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10280298.html"},
            {"id": "shenzhen-2010-12-28-lines2-3", "date": "2010-12-28", "title": "2号线一期与3号线一期开通", "routeIds": ["shenzhen-r2", "shenzhen-r3"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10280298.html"},
            {"id": "shenzhen-2011-06-15-line1-airport", "date": "2011-06-15", "title": "1号线向西延至机场东", "routeIds": ["shenzhen-r1"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10280298.html"},
            {"id": "shenzhen-2011-06-16-line4-qinghu", "date": "2011-06-16", "title": "4号线延至清湖", "routeIds": ["shenzhen-r4"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10280298.html"},
            {"id": "shenzhen-2011-06-22-line5", "date": "2011-06-22", "title": "5号线一期前海湾—黄贝岭开通", "routeIds": ["shenzhen-r5"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10280298.html"},
            {"id": "shenzhen-2011-06-28-lines2-3-extensions", "date": "2011-06-28", "title": "2号线延至新秀、3号线延至益田", "routeIds": ["shenzhen-r2", "shenzhen-r3"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10280298.html"},
            {"id": "shenzhen-2016-06-28-line11", "date": "2016-06-28", "title": "11号线福田枢纽—碧头开通", "routeIds": ["shenzhen-r12"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10280298.html"},
            {"id": "shenzhen-2016-10-28-lines7-9", "date": "2016-10-28", "title": "7号线与9号线一期开通，线网进入新一轮成网阶段", "routeIds": ["shenzhen-r8", "shenzhen-r10"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10280298.html"},
            {"id": "shenzhen-2019-09-28-line5-phase2", "date": "2019-09-28", "title": "5号线二期赤湾—前海湾开通", "routeIds": ["shenzhen-r5"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10280298.html"},
            {"id": "shenzhen-2019-12-08-line9-west", "date": "2019-12-08", "title": "9号线西延至前湾", "routeIds": ["shenzhen-r10"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10280298.html"},
            {"id": "shenzhen-2020-08-18-lines6-10", "date": "2020-08-18", "title": "6号线、10号线开通，运营网络跨入十线阶段", "routeIds": ["shenzhen-r6", "shenzhen-r11"], "source": "https://jtys.sz.gov.cn/gkmlpt/content/8/8012/post_8012970.html"},
            {"id": "shenzhen-2020-10-28-lines2-3-4-8", "date": "2020-10-28", "title": "2、3、4、8号线多个延伸段集中开通", "routeIds": ["shenzhen-r2", "shenzhen-r3", "shenzhen-r4", "shenzhen-r9"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10280298.html"},
            {"id": "shenzhen-2021-12-28-line20", "date": "2021-12-28", "title": "20号线一期机场北—会展城开通", "routeIds": ["shenzhen-r17"], "source": "https://jtys.sz.gov.cn/jtzx/wycx/dtcx/cxtx/content/post_9488300.html"},
            {"id": "shenzhen-2022-10-28-lines11-14", "date": "2022-10-28", "title": "14号线开通，11号线福田—岗厦北段投入运营", "routeIds": ["shenzhen-r15", "shenzhen-r12"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10280298.html"},
            {"id": "shenzhen-2022-11-28-line6-branch-line12", "date": "2022-11-28", "title": "6号线支线与12号线开通", "routeIds": ["shenzhen-r7", "shenzhen-r13"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10280298.html"},
            {"id": "shenzhen-2022-12-28-line16", "date": "2022-12-28", "title": "16号线开通", "routeIds": ["shenzhen-r16"], "source": "https://jtys.sz.gov.cn/ydmh/jtzx/zyhy_1510/content/post_10359461.html"},
            {"id": "shenzhen-2023-12-27-line8-phase2", "date": "2023-12-27", "title": "8号线二期延至小梅沙", "routeIds": ["shenzhen-r9"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_11072547.html"},
            {"id": "shenzhen-2024-12-28-five-openings", "date": "2024-12-28", "title": "3号线四期、7号线二期、11号线二期、12号线二期与13号线南段开通", "routeIds": ["shenzhen-r3", "shenzhen-r8", "shenzhen-r12", "shenzhen-r13", "shenzhen-r14"], "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/gqdt/content/post_11930882.html"},
            {"id": "shenzhen-2025-09-28-line16-phase2-branch6-phase2", "date": "2025-09-28", "title": "16号线二期与6号线支线二期开通", "routeIds": ["shenzhen-r16", "shenzhen-r7"], "source": "https://www.sz.gov.cn/cn/xxgk/bmtx/content/post_12415878.html"},
            {"id": "shenzhen-2025-12-28-lines5-8-11-13", "date": "2025-12-28", "title": "5号线西延、8号线三期、11号线红岭南段及13号线一期北段开通", "routeIds": ["shenzhen-r5", "shenzhen-r9", "shenzhen-r12", "shenzhen-r14"], "source": "https://www.sz.gov.cn/cn/xxgk/bmtx/content/post_12576035.html"},
            {"id": "shenzhen-2026-06-28-line13-north", "date": "2026-06-28", "title": "13号线二期北延段开通并与一期贯通", "routeIds": ["shenzhen-r14"], "source": "https://jtys.sz.gov.cn/ydmh/jtzx/zyhy_1510/content/post_12867344.html"},
        ],
        "excludedStations": {},
        "projects": [
            {"id": "sz-line15", "name": "15号线", "projectType": "under_construction", "status": "在建", "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/bmdt/content/post_12637191.html", "sourceTitle": "织密地铁网络 赋能城市高质量发展", "note": "深圳市政府报道列入五期持续推进项目；交通局2026年仍发布区间施工进度。"},
            {"id": "sz-line17-phase1", "name": "17号线一期", "projectType": "under_construction", "status": "在建", "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/bmdt/content/post_12637191.html", "sourceTitle": "织密地铁网络 赋能城市高质量发展", "note": "深圳市政府确认持续推进，未计入截止日已开通线网。"},
            {"id": "sz-line19-phase1", "name": "19号线一期", "projectType": "under_construction", "status": "在建", "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/bmdt/content/post_12637191.html", "sourceTitle": "织密地铁网络 赋能城市高质量发展", "note": "深圳市政府确认五期建设项目；公布的政策里程目标不替代工程站序图。"},
            {"id": "sz-line20-phase2", "name": "20号线二期", "projectType": "under_construction", "status": "在建", "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/bmdt/content/post_12637191.html", "sourceTitle": "织密地铁网络 赋能城市高质量发展", "note": "深圳市政府确认持续推进。"},
            {"id": "sz-line22-phase1", "name": "22号线一期", "projectType": "under_construction", "status": "在建", "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/bmdt/content/post_12637191.html", "sourceTitle": "织密地铁网络 赋能城市高质量发展", "note": "深圳市政府确认持续推进。"},
            {"id": "sz-line25-phase1", "name": "25号线一期", "projectType": "under_construction", "status": "在建", "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/bmdt/content/post_12637191.html", "sourceTitle": "织密地铁网络 赋能城市高质量发展", "note": "深圳市政府确认持续推进；以一期正式工程范围为准。"},
            {"id": "sz-line27-phase1", "name": "27号线一期", "projectType": "under_construction", "status": "在建", "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/bmdt/content/post_12637191.html", "sourceTitle": "织密地铁网络 赋能城市高质量发展", "note": "深圳市政府确认持续推进。"},
            {"id": "sz-line29-phase1", "name": "29号线一期", "projectType": "under_construction", "status": "在建", "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/bmdt/content/post_12637191.html", "sourceTitle": "织密地铁网络 赋能城市高质量发展", "note": "深圳市政府确认持续推进。"},
            {"id": "sz-line32-phase1", "name": "32号线一期", "projectType": "under_construction", "status": "在建", "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/bmdt/content/post_12637191.html", "sourceTitle": "织密地铁网络 赋能城市高质量发展", "note": "深圳市政府确认持续推进；按城市轨道交通范围纳入。"},
            {"id": "sz-line13-phase2-south", "name": "13号线二期南延段", "projectType": "approved_plan", "status": "十五五规划目标", "source": "https://www.sz.gov.cn/zfgb/2026/gb1420/content/post_12894205.html", "sourceTitle": "深圳市国民经济和社会发展第十五个五年规划纲要", "note": "规划提出建成13号线二期南北延；北延已于2026-06-28开通，此处只登记其余规划范围，不把整段重复算作未建。", "playabilityStatus": "policy_only_not_playable", "playabilityNote": "十五五规划提出的13号线二期南北延：北延已于2026-06-28开通，南段（深圳湾口岸—后海）已包含在13号线既有运营站序中；没有新的逐站工程蓝图。"},
            {"id": "sz-fifth-phase-plan", "name": "城市轨道交通第五期建设规划（项目库）", "projectType": "approved_plan", "status": "已批建设规划", "source": "https://www.sz.gov.cn/cn/xxgk/zfxxgj/zwdt/content/post_10089296.html", "sourceTitle": "地铁五期13条线路规划公布", "note": "规划包含13个项目；只有逐项目工程范围和 stationOrder 完成核对后才转为可玩建设任务。", "playabilityStatus": "policy_only_not_playable", "playabilityNote": "五期建设规划项目库，属规划集合而非单一工程。"},
        ],
    },
    "chengdu": {
        "name": "成都",
        "officialRouteCount": 16,
        "countBasis": "运营集团2026年公开债券文件按地铁线路列出1—10、13、17—19、27、30号线；市域铁路、有轨电车另计。",
        "sources": [
            {"title": "成都轨道交通集团2026年债券募集说明书", "url": "https://static.sse.com.cn/bond/bridge2/disclosure/announcement/c/202606/9dbefc_20260618_SLKT.pdf", "supports": "2026年运营线路及项目类别。"},
            {"title": "成都轨道交通13号线、30号线开通", "url": "https://www.crecg.com/web/xwzx61/gsyw87/2025121815543222258/index.html", "supports": "2025年12月两条线路开通节点。"},
        ],
        "officialStationCount": None,
        "stationCountBasis": "债券文件用于核对线路清单与类别，不在本基准中混用线路站次与去重车站数。",
        "recentMilestones": [
            {"id": "chengdu-2025-12-16-lines13-30", "date": "2025-12-16", "title": "13号线一期、30号线一期同步开通", "routeIds": ["chengdu-r11", "chengdu-r16"], "source": "https://www.crecg.com/web/xwzx61/gsyw87/2025121815543222258/index.html"},
        ],
        "excludedStations": {},
        "projects": [
            {"id": "cd-line18-phase3", "name": "18号线三期（火车北站—火车南站）", "projectType": "under_construction", "status": "在建", "source": "https://news.chengdu.cn/2026/0608/6a261116cfd50212c36c1923.shtml", "sourceTitle": "全线铺轨已完成83%！18号线三期又有新进展", "note": "截至2026年6月官方报道仍在铺轨与机电施工；按截止日不计入已开通网络。成都—眉山、成德市域铁路按本游戏范围另列。"},
            {"id": "cd-fifth-phase-consultation", "name": "第五期建设规划（2024—2029）初步方案", "projectType": "public_consultation", "status": "征求意见／未见国家批复", "source": "https://m.xjgjxk.com/shiping/show.php?itemid=1891", "sourceTitle": "成都市城市轨道交通第五期建设规划第二次环评公示（转载）", "note": "包含5号线三期、9号线二期、10号线四期、12号线一期、16号线一期、18号线四期、20号线一期、22号线一期、23号线一期和27号线二期；这是环评征求意见方案，不作为已批建设蓝图。", "playabilityStatus": "policy_only_not_playable", "playabilityNote": "第五期建设规划初步方案征求意见，尚未进入工程实施。"},
        ],
    },
}


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def build(cities_doc: dict[str, Any], campaigns_doc: dict[str, Any]) -> dict[str, Any]:
    output: dict[str, Any] = {
        "schemaVersion": 2,
        "cutoffDate": "2026-10-01",
        "compiledAt": "2026-10-20",
        "scope": "城市地铁与跨城地铁线路；市域铁路、磁浮、有轨电车及机场专线按各城官方口径另列。",
        "dataPolicy": "官方来源用于确认公开线路口径及已登记的开通节点；各线逐站开通范围和站序尚未全部对照。离线OSM关系仅提供地图对象与可分发几何，不能单独证明历史开通日期或逐站顺序。地图站点覆盖不等于历史章节可玩覆盖。",
        "cities": {},
    }
    for city in cities_doc.get("cities", []):
        city_id = str(city.get("id", ""))
        if city_id not in CITY_SOURCES:
            raise ValueError(f"Missing source definition for {city_id}")
        metadata = CITY_SOURCES[city_id]
        rows: list[dict[str, Any]] = []
        exclusions = metadata.get("excludedStations", {})
        for line in city.get("lines", []):
            route_id = str(line.get("id", ""))
            station_ids = [str(value) for value in line.get("stationIds", [])]
            if not station_ids:
                for direction in line.get("directions", []):
                    if direction.get("stationIds"):
                        station_ids = [str(value) for value in direction["stationIds"]]
                        break
            removed: list[dict[str, str]] = []
            for item in exclusions.get(route_id, []):
                # Only a station that is actually on this route can be excluded
                # for being unopened; a same-named station on a future project
                # must not leak into the operating route inventory.
                match = next((str(station.get("id", "")) for station in city.get("stations", []) if str(station.get("name", "")) == item["name"] and str(station.get("id", "")) in station_ids), "")
                if match:
                    removed.append({"stationId": match, "name": item["name"], "reason": item["reason"], "source": item["source"]})
            excluded_ids = {entry["stationId"] for entry in removed}
            route_ref = str(line.get("ref", line.get("name", "")))
            rows.append({
                "mapRouteId": route_id,
                "ref": route_ref,
                "name": str(line.get("name", route_ref)),
                "cutoffStatus": "open_at_cutoff",
                "stationOrderSource": "Bundled OpenStreetMap subway relation order; city official station sequence and phase-by-phase opening scope have not yet been reconciled for every route",
                "mapStationCount": len(station_ids),
                "cutoffStationIds": [value for value in station_ids if value not in excluded_ids],
                "excludedStations": removed,
                "routeRelations": line.get("osmRelationIds", []),
            })
        campaign = campaigns_doc.get("cities", {}).get(city_id, {})
        milestones = []
        playable_dates = {str(ch.get("date", "")): str(ch.get("id", "")) for ch in campaign.get("chapters", [])}
        playable_by_id = {str(ch.get("id", "")): ch for ch in campaign.get("chapters", [])}
        def chapter_targets(chapter_id: str) -> list[dict[str, Any]]:
            chapter = playable_by_id.get(chapter_id, {})
            groups = []
            for index, group in enumerate(chapter.get("lineGroups", [])):
                target = {
                    "taskId": str(group.get("taskId", f"line:{chapter_id}:{index}")),
                    "historicalLineId": str(group.get("historicalLineId", group.get("id", ""))),
                    "name": str(group.get("name", "历史线路段")),
                    "stationIds": [str(value) for value in group.get("stationIds", [])],
                }
                # Incremental construction targets need their original route
                # order to survive a baseline rebuild. Without these fields,
                # the next generator pass treats an already shortened range
                # as a fresh whole-route snapshot and keeps appending :range-N
                # to task IDs.
                for field in [
                    "stationInstances", "stationNames", "constructionScope",
                    "constructionScopeNote", "sourceStationIds",
                    "sourceStationInstances", "sourceStationNames",
                ]:
                    if field in group:
                        target[field] = group[field]
                groups.append(target)
            return groups
        for event in campaign.get("historicalEvents", []):
            chapter_id = playable_dates.get(str(event.get("date", "")), "")
            milestones.append({
                "id": str(event.get("id", "")),
                "date": str(event.get("date", "")),
                "title": str(event.get("title", "")),
                "status": str(event.get("status", "")),
                "source": str(event.get("source", "")),
                "chapterId": chapter_id,
                "targetLineGroups": chapter_targets(chapter_id),
            })
        milestones.extend({**row, "chapterId": playable_dates.get(str(row.get("date", "")), ""), "status": "opened_or_completed", "targetLineGroups": chapter_targets(playable_dates.get(str(row.get("date", "")), ""))} for row in metadata.get("recentMilestones", []))
        # Keep the existing playable chapter events in the same chronological
        # ledger as the source-index events. Some early sample chapters were
        # never entered in historicalEvents, so add them explicitly.
        event_dates = {str(row.get("date", "")) for row in milestones}
        for chapter in campaign.get("chapters", []):
            # Generated cutoff-route tasks are a playable safety net, not
            # historical opening evidence. Turning one into a dated event
            # used to make an entire modern line appear to have opened on an
            # unrelated chapter date (and could duplicate later extensions).
            if str(chapter.get("chapterScope", "")) in {"cutoff_route_completion", "cutoff_reconciliation"}:
                continue
            chapter_date = str(chapter.get("date", ""))
            if not chapter_date or chapter_date in event_dates:
                continue
            milestones.append({
                "id": "chapter-milestone-" + str(chapter.get("id", "")),
                "date": chapter_date,
                "title": str(chapter.get("title", "历史节点")),
                "status": "playable_sample",
                "source": str(chapter.get("source", "")) or str((chapter.get("sources") or [{}])[0].get("url", "")),
                "chapterId": str(chapter.get("id", "")),
                "routeIds": [str(value) for value in chapter.get("routeMilestoneIds", [])],
                "targetLineGroups": chapter_targets(str(chapter.get("id", ""))),
            })
        milestones.sort(key=lambda value: value["date"])
        # Chapters are intervals between meaningful network milestones, not
        # one chapter for every planning memo or station. Planning/revision
        # events remain inside the next network-changing chapter interval.
        milestone_chapters: list[dict[str, Any]] = []
        previous_date = ""
        grouped: dict[str, list[dict[str, Any]]] = {}
        for row in milestones:
            grouped.setdefault(str(row["date"]), []).append(row)
        anchor_dates = []
        for milestone_date in sorted(grouped):
            rows_at_date = grouped[milestone_date]
            is_anchor = any(
                row.get("chapterId")
                or str(row.get("status", "")) in {"opened_or_completed", "opened_or_operated", "trial_operation", "built_not_publicly_operated"}
                for row in rows_at_date
            )
            if is_anchor: anchor_dates.append(milestone_date)
        for milestone_date in anchor_dates:
            anchor_rows = grouped[milestone_date]
            interval_rows = [row for row in milestones if previous_date < str(row.get("date", "")) <= milestone_date]
            ids = sorted({str(row.get("chapterId", "")) for row in interval_rows if row.get("chapterId")})
            source_rows = [{"title": str(row.get("title", "")), "url": str(row.get("source", ""))} for row in interval_rows if row.get("source")]
            target_groups_by_id: dict[str, dict[str, Any]] = {}
            for row in interval_rows:
                for group in row.get("targetLineGroups", []):
                    target_groups_by_id[str(group.get("taskId", ""))] = group
            milestone_chapters.append({
                "id": f"{city_id}-milestone-{milestone_date}",
                "periodStartExclusive": previous_date,
                "periodEndInclusive": milestone_date,
                "title": " / ".join(dict.fromkeys(str(row.get("title", "历史节点")) for row in anchor_rows)),
                "eventIds": [str(row.get("id", "")) for row in interval_rows],
                "events": [{"id": str(row.get("id", "")), "date": str(row.get("date", "")), "title": str(row.get("title", "")), "status": str(row.get("status", "")), "source": str(row.get("source", "")), "routeIds": row.get("routeIds", []), "targetLineGroups": row.get("targetLineGroups", [])} for row in interval_rows],
                "chapterIds": ids,
                "playableChapterId": ids[0] if ids else "",
                "contentStatus": "playable_sample" if ids else "content_missing",
                "routeIds": sorted({str(route_id) for row in interval_rows for route_id in row.get("routeIds", [])}),
                "chapterTargetGroups": list(target_groups_by_id.values()),
                "chapterTargetStationIds": sorted({station_id for group in target_groups_by_id.values() for station_id in group.get("stationIds", [])}),
                "sources": source_rows,
            })
            previous_date = milestone_date
        cutoff_rows = [row for row in milestones if previous_date < str(row.get("date", "")) <= "2026-10-01"]
        milestone_chapters.append({
            "id": f"{city_id}-milestone-cutoff-2026-10-01",
            "periodStartExclusive": previous_date,
            "periodEndInclusive": "2026-10-01",
            "title": "核对截至2026年10月1日的现状路网",
            "eventIds": [str(row.get("id", "")) for row in cutoff_rows],
            "events": [{"id": str(row.get("id", "")), "date": str(row.get("date", "")), "title": str(row.get("title", "")), "status": str(row.get("status", "")), "source": str(row.get("source", "")), "routeIds": row.get("routeIds", []), "targetLineGroups": row.get("targetLineGroups", [])} for row in cutoff_rows],
            "chapterIds": [],
            "playableChapterId": "",
            "contentStatus": "network_reconciliation_missing",
            "routeIds": sorted({str(route_id) for row in cutoff_rows for route_id in row.get("routeIds", [])}),
            "chapterTargetGroups": [],
            "chapterTargetStationIds": [],
            "targetMapRouteIds": [row["mapRouteId"] for row in rows],
            "sources": [{"title": str(source.get("title", "")), "url": str(source.get("url", ""))} for source in metadata["sources"]],
        })
        # Playability is derived from the campaign's validated blueprints, not
        # hand-edited into the inventory. A project counts as playable only when
        # its plan declares blueprint_ready, has a usable alignment grade and a
        # line group whose stations all exist on this city's map.
        city_station_ids = {str(station.get("id", "")) for station in city.get("stations", [])}
        ready_project_ids: set[str] = set()
        for plan in campaign.get("futurePlans", []):
            if str(plan.get("dataStatus", "")) != "blueprint_ready":
                continue
            if str(plan.get("exactAlignment", "")) not in {"station_areas", "corridor_only", "verified_alignment"}:
                continue
            groups = plan.get("lineGroups", [])
            if not isinstance(groups, list) or not groups:
                continue
            ready = True
            for group in groups:
                ids = [str(value) for value in group.get("stationIds", [])]
                if len(ids) < 2 or float(group.get("toleranceM", 0) or 0) <= 0:
                    ready = False
                    break
                if not set(ids).issubset(city_station_ids):
                    ready = False
                    break
            if ready:
                ready_project_ids.update(str(value) for value in plan.get("projectIds", []))
        project_rows = []
        for project in metadata.get("projects", []):
            row = dict(project)
            if str(row.get("id", "")) in ready_project_ids:
                row["playabilityStatus"] = "playable_build_task"
            else:
                row.setdefault("playabilityStatus", "registered_geometry_and_playable_task_pending")
            row.setdefault("sourceCheckedAt", "2026-10-20")
            row.setdefault("statusAtCutoff", row.get("status", "项目状态待核实"))
            project_rows.append(row)
        output["cities"][city_id] = {
            "name": metadata["name"],
            "mapSnapshotDate": cities_doc.get("generatedAt", "unknown"),
            "officialRouteCount": metadata.get("officialRouteCount"),
            "officialStationCount": metadata.get("officialStationCount"),
            "stationCountBasis": metadata.get("stationCountBasis", ""),
            "countBasis": metadata["countBasis"],
            "sources": metadata["sources"],
            "projectsAtCutoff": project_rows,
            "documentedMilestones": milestones,
            "documentedMilestoneCount": len(milestones),
            "milestoneChapters": milestone_chapters,
            "milestoneChapterCount": len(milestone_chapters),
            "mapRouteEntryCount": len(rows),
            "mapRouteStopOccurrenceCount": sum(row["mapStationCount"] for row in rows),
            "mapUniqueStationCount": len({station for row in rows for station in row["cutoffStationIds"]}),
            "routes": rows,
            "milestoneRule": "章节边界只对应有来源的实际开通、试运营、建成节点或现有可玩里程碑；规划和修订事件保留在相邻区间，不独立构成建设章节。本清单只给截止日目标，历史逐期任务必须由开通事件台账生成，不能把当前整条线路倒灌到首开年份。",
        }
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cities", type=Path, default=Path("data/cities.json"))
    parser.add_argument("--campaigns", type=Path, default=Path("data/campaigns.json"))
    parser.add_argument("--out", type=Path, default=Path("data/network_baselines_2026-10-01.json"))
    args = parser.parse_args()
    data = build(load(args.cities), load(args.campaigns))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: {"mapRoutes": value["mapRouteEntryCount"], "mapStations": value["mapUniqueStationCount"], "officialRoutes": value["officialRouteCount"]} for key, value in data["cities"].items()}, ensure_ascii=False))


if __name__ == "__main__":
    main()
