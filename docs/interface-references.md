# 界面参考记录

## 0.19公共交通地理底图

参考方向为[高德地理地图的公共交通入口](https://amap-pc-ssr.amap.com/ssr/search)。固定本地对照范围为上海徐汇周边中心31.1947,121.4376，城市z12／街区z15／建站z17，原生画面1600×980；对应 `map-0.19-city`、`map-0.19-blocks`、`map-0.19-station` 截图。配色、道路描边、水系、建筑与交通符号统一由 `map_style.gd` 管理。

2026-10-17尝试查看官方交互地图，内置浏览器两次超时，桌面浏览器操作随后因无法可靠确认地址而被工具中止。三档高德官方截图没有归档，不能将本地渲染标注为高德截图、像素级复刻或已完成官方画面对照。下列历史游戏参考仍保留为先前版本的记录。

地图采用本地OSM数据，不请求高德瓦片。水系改为蓝色、街区浅灰、道路白色加描边、主路淡黄色、普通建筑灰蓝，主要地名优先于普通楼名。现代地图与历史故事的边界在游戏署名中始终可见。

查看日期：2026-10-16。下列链接指向各自官方页面，设计取舍据页面内容记录。Godot 实际渲染的本地对照图按文件名标注尺寸；参考网页截图和原始网页视口宽度本轮未能归档，因此不将本地截图标作第三方页面截图。

| 参考 | 官方页面 | 查看日期 | 原网页截图／宽度 | 对本项目的启发 | 本地对照图尺寸 |
| --- | --- | --- | --- | --- | --- |
| Mini Metro | [Dinosaur Polo Club · Mini Metro](https://dinopoloclub.com/games/mini-metro/) | 2026-10-16 | 未归档；原网页宽度未记录 | 线路和站点必须压过地图背景；网络状态需要快速辨认。 | [规划页，1600×980](redesign-ui-preview-1600x980.png) |
| NIMBY Rails | [Steam · NIMBY Rails](https://store.steampowered.com/app/1134710/NIMBY_Rails/) | 2026-10-16 | 未归档；原网页宽度未记录 | 以真实地理为主要施工画布，精细参数应按需出现。 | [宽屏规划页，1920×1080](redesign-ui-preview-1920x1080.png) |
| Linear UI redesign | [Linear · How we redesigned the Linear UI](https://linear.app/now/how-we-redesigned-the-linear-ui) | 2026-10-16 | 未归档；原网页宽度未记录 | 中性色界面、可折叠侧栏、清楚的面板层级与一致的对齐。 | [主菜单，1600×980](redesign-menu-preview-1600x980.png) |

同一组 Godot 渲染图还包括[新城开局](redesign-new-city-1600x980.png)、[统计](redesign-stats-preview-1600x980.png)、[命名存档](redesign-save-center-preview-1600x980.png)、[教学焦点](redesign-tutorial-preview-1600x980.png)和[1366×768 规划视口](redesign-ui-preview-1366x768.png)。

页面参考用于确定方向；本产品的颜色、控件、版面和状态细节以 [设计系统](../.interface-design/system.md) 为准。实现截图在检查后直接更新，不替换已有的历史预览文件。
