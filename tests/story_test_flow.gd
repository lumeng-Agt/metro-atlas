extends RefCounted
const Story=preload("res://scripts/story_session.gd")

## Test navigation uses the same confirmations as the player. No chapter
## index, completed-event flag or prebuilt world is inserted to skip prefaces.
static func reach_first_construction(app:Control) -> bool:
	while app.saves_in_flight>0:await app.get_tree().process_frame
	for _event in range(20):
		var chapter:=Story.chapter(app.world)
		if not bool(chapter.get("eventOnly",false)):return not chapter.is_empty()
		app._begin_chapter();app._check();app._commit_chapter()
		if str(app.world.storyState.stage)!="outcome":return false
		while app.saves_in_flight>0:await app.get_tree().process_frame
		app._next()
		while app.saves_in_flight>0:await app.get_tree().process_frame
	return false
