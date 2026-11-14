---
version: 1
slug: "scripts-story-app-gd"
primary_target: "scripts/story_app.gd"
related_targets: []
---

# 建设工作台 · surface brief

Scope: `scripts/story_app.gd` 建设工作台（Operate 模式）。
Audience: 想亲手复现一段真实地铁建设史的玩家，坐在 Windows 桌面前，一次连续玩 30–60 分钟。
Job: 从地图复现当前历史阶段，随时知道下一步做什么、检查结果如何。
Constraints: 18px 正文、至少 15px 辅助字、44px 按钮；1366×768 起；地图至少 360px 高；确认区固定。

## Direction contract

THESIS: 界面是一张正在绘制的施工图，每个 UI 元素都是图上的标注而不是按钮；拒绝「每个信息块套一个方框」的通用工具界面。

OWN-WORLD: 描图纸白 #FAFAF7 作底，墨线 #1A1A1A 承载文字，辅助线 #8C8C8C 标注，站牌绿 #1B5E4F 只给当前动作，校对朱红 #C4553B 只给差异与错误。组件语言是引线、编号圈、尺寸线、图框标题栏——没有填充方块，没有圆角卡片。

STORY: 玩家一眼看出「这是图纸，我在图上作业」；标注指向对象，编号给出顺序，尺寸线划出工具区；不需要学习就知道点哪里。

FIRST VIEWPORT: 顶栏是一行编号标注（① 故事 ② 撤销 ③ 存档 ④ 菜单），无背景无边框；地图占满中部，底色与纸面同系 #F4F4EE；左下角是带标题栏的图框（章节名 / 里程碑 / 展开箭头），只有顶部一条墨线；底栏是尺寸线分隔的工具区（选择 ─ 车站 ─ 铺轨 ─ 图层），当前工具用站牌绿加粗。

FORM: 我的第 4 个方向「施工图标注」。seed: 35dd664a92dae292

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.
