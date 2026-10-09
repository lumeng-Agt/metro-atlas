class_name OnboardingController
extends RefCounted

const MISSIONS := {
	"shanghai": {
		"id": "shanghai-neighborhood-commute-v1",
		"originId": "shanghai-tutorial-jingui",
		"destinationId": "shanghai-d17",
		"theme": "金桂小区到北蔡中学的早间出行",
		"reason": "花木街道内一处有名称的住宅小区在早高峰产生前往学校的游戏需求。先理解这条出行，再决定车站和线路放在哪里。"
	},
	"beijing": {
		"id": "beijing-neighborhood-commute-v1",
		"originId": "beijing-d5",
		"destinationId": "beijing-tutorial-cnu",
		"theme": "玲珑花园到首都师范大学的早间出行",
		"reason": "居民需要前往校园。教学地点来自 OpenStreetMap 地点资料，客流为游戏设定。"
	},
	"guangzhou": {
		"id": "guangzhou-neighborhood-commute-v1",
		"originId": "guangzhou-tutorial-zhongshan-housing",
		"destinationId": "guangzhou-d14",
		"theme": "中山四路住宅楼到中山二路小学的早间出行",
		"reason": "附近居住点和小学之间存在短程出行需求。两处地点已选在同一片街区。"
	},
	"shenzhen": {
		"id": "shenzhen-neighborhood-commute-v1",
		"originId": "shenzhen-tutorial-xililantian",
		"destinationId": "shenzhen-d4",
		"theme": "西丽蓝天到南山科技创新中心的通勤",
		"reason": "西丽街道内的住宅小区在早间产生前往科技就业区的游戏需求。建议位置只是选址参考，不是规定线位。"
	},
	"chengdu": {
		"id": "chengdu-neighborhood-commute-v1",
		"originId": "chengdu-tutorial-yulinmingju",
		"destinationId": "chengdu-d19",
		"theme": "玉林名居2期到成都南站的接驳出行",
		"reason": "玉林片区一处命名住宅区有前往铁路枢纽的游戏需求。先观察地点关系，再自行决定如何接入枢纽。"
	}
}

static func mission(city_id: String) -> Dictionary:
	return MISSIONS.get(city_id, MISSIONS["shanghai"]).duplicate(true)

static func create_state(city_id: String, mode: String, completed_once: bool) -> Dictionary:
	var selected := mission(city_id)
	var is_blank := mode == "blank"
	return {
		"version": 1,
		"missionId": str(selected.get("id", "")),
		"originId": str(selected.get("originId", "")),
		"destinationId": str(selected.get("destinationId", "")),
		"active": is_blank and not completed_once,
		"step": 0,
		"completed": false,
		"skipped": false,
		"viewingCity": false,
		"originStationId": "",
		"destinationStationId": "",
		"observationStarted": false,
		"observationStartMinute": -1,
		"observedTargetArrivals": 0,
		"observedTargetServed": 0,
		"lastError": ""
	}
