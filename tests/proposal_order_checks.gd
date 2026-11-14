extends SceneTree

## The proposal comparison must reward serving the published stations in the
## published order, must not invent stations, and must never claim surveying
## accuracy or ridership.

const ProposalScoring = preload("res://scripts/proposal_scoring.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _run() -> void:
	var published: Array = ["a", "b", "c", "d", "e"]
	# Serving every station in the published order is the best possible result.
	var perfect := ProposalScoring.compare_order(published, published, [])
	_check(int(perfect.score) == 100, "the published order scores 100, got %d" % int(perfect.score))
	_check(float(perfect.orderRatio) == 1.0, "the published order has full order agreement")
	_check(int(perfect.served) == 5, "the published order serves every station")
	_check((perfect.missedStationIds as Array).is_empty(), "the published order misses nothing")
	# Serving every station in reverse loses the order points.
	var reversed_ids: Array = published.duplicate()
	reversed_ids.reverse()
	var backwards := ProposalScoring.compare_order(reversed_ids, published, [])
	# A fully reversed pick has no order agreement at all. Anything above zero
	# here would let a player collect order points for getting it exactly wrong.
	_check(float(backwards.orderRatio) == 0.0, "a reversed order has no order agreement, got %.2f" % float(backwards.orderRatio))
	_check(int(backwards.score) < 60, "a reversed order does not reach a pass, got %d" % int(backwards.score))
	_check(str(backwards.grade) == "偏离较多", "a reversed order is graded as divergent, got %s" % str(backwards.grade))
	_check(int(backwards.served) == 5, "a reversed order still serves every station")
	# The same must hold on the shortest possible line: two stations picked the
	# wrong way round are still the wrong way round.
	var two_published: Array = ["a", "b"]
	var two_backwards := ProposalScoring.compare_order(["b", "a"], two_published, [])
	_check(float(two_backwards.orderRatio) == 0.0, "a two-station reversal has no order agreement")
	_check(int(two_backwards.score) < 60, "a two-station reversal does not reach a pass, got %d" % int(two_backwards.score))
	var two_forwards := ProposalScoring.compare_order(["a", "b"], two_published, [])
	_check(int(two_forwards.score) == 100, "a two-station line in order scores 100, got %d" % int(two_forwards.score))
	# Serving half the stations halves the coverage share.
	var half := ProposalScoring.compare_order(["a", "b"], published, [])
	_check(int(half.served) == 2, "a partial proposal serves what it picked")
	_check(int(half.score) < 60, "a partial proposal scores below a pass, got %d" % int(half.score))
	_check((half.missedStationIds as Array).size() == 3, "a partial proposal reports the stations it missed")
	# Unknown ids are ignored rather than counted.
	var unknown := ProposalScoring.compare_order(["a", "zzz", "b"], published, [])
	_check(int(unknown.served) == 2, "an unknown station is not counted as served")
	# Duplicates are counted once.
	var dupes := ProposalScoring.compare_order(["a", "a", "b"], published, [])
	_check(int(dupes.served) == 2, "a duplicate station is counted once")
	# An empty proposal earns nothing.
	var empty := ProposalScoring.compare_order([], published, [])
	_check(int(empty.score) == 0, "an empty proposal scores zero")
	_check(float(empty.orderRatio) == 0.0, "an empty proposal has no order agreement")
	# Interchanges are checked against what the player actually served. The
	# argument is station ids: matching a station name against an id list would
	# silently report every interchange as missed.
	var transfers := ProposalScoring.compare_order(["a", "b", "c"], published, ["a", "e"])
	_check((transfers.transfersHit as Array).has("a"), "a served interchange counts as hit")
	_check((transfers.transfersMissed as Array).has("e"), "an unserved interchange is reported missed")
	# Serving every station and every interchange is a full score, not a partial
	# one: a missed interchange share would show up as a score below 100.
	var all_transfers := ProposalScoring.compare_order(published, published, published)
	_check(int(all_transfers.score) == 100, "serving every interchange scores 100, got %d" % int(all_transfers.score))
	_check((all_transfers.transfersMissed as Array).is_empty(), "serving every interchange misses none")
	_check((all_transfers.transfersHit as Array).size() == 5, "every interchange is reported hit")
	# The notice never claims accuracy it does not have.
	_check(str(perfect.notice).contains("不代表测绘精度"), "the notice disclaims surveying accuracy")
	_check(str(perfect.notice).contains("不评估客流"), "the notice disclaims ridership")
	# Grades follow the documented thresholds.
	_check(ProposalScoring.grade(90.0) == "贴合公开方案", "a high score is graded as close")
	_check(ProposalScoring.grade(70.0) == "走向基本一致", "a middle score is graded as consistent")
	_check(ProposalScoring.grade(20.0) == "偏离较多", "a low score is graded as divergent")
	print("PASS: %d proposal scoring checks" % checks if failures.is_empty() else "FAIL: %d checks, %d failures: %s" % [checks, failures.size(), " | ".join(failures)])
	quit(0 if failures.is_empty() else 1)
