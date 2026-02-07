extends RefCounted
class_name BoardData

# ボードの描画座標を計算するユーティリティ

const BOARD_OFFSET := Vector2(60, 80)
const SQUARE_SIZE := 50.0
const SQUARE_GAP := 12.0
const STEP := SQUARE_SIZE + SQUARE_GAP
const COLS_PER_ROW := 10
const ROW_HEIGHT := 90.0
const BRANCH_OFFSET_Y := 85.0

# マスのイベント種別に応じた色
const COLOR_START := Color(0.3, 0.7, 1.0)
const COLOR_GOAL := Color(1.0, 0.85, 0.0)
const COLOR_GAIN := Color(0.2, 0.8, 0.3)
const COLOR_LOSE := Color(0.9, 0.25, 0.25)
const COLOR_RANDOM := Color(0.9, 0.7, 0.2)
const COLOR_STEAL := Color(0.8, 0.3, 0.8)
const COLOR_BRANCH := Color(0.4, 0.8, 1.0)
const COLOR_EMPTY := Color(0.35, 0.35, 0.45)

static func compute_positions(board: Array) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	positions.resize(board.size())

	# メインルート前半 (0-10): 左→右
	for i in range(11):
		positions[i] = BOARD_OFFSET + Vector2(i * STEP, 0)

	# 山道コース (11-17): 右→左、1行下にオフセット
	var mountain_start_x = BOARD_OFFSET.x + 10 * STEP
	for i in range(7):
		var idx = 11 + i
		positions[idx] = Vector2(mountain_start_x - i * STEP, BOARD_OFFSET.y + BRANCH_OFFSET_Y)

	# 海道コース (18-24): 右→左、2行下にオフセット
	for i in range(7):
		var idx = 18 + i
		positions[idx] = Vector2(mountain_start_x - i * STEP, BOARD_OFFSET.y + BRANCH_OFFSET_Y * 2)

	# 合流〜ゴール (25-34): 左→右、3行下
	for i in range(10):
		var idx = 25 + i
		positions[idx] = BOARD_OFFSET + Vector2(i * STEP, BRANCH_OFFSET_Y * 3)

	return positions

static func get_square_color(square: Dictionary) -> Color:
	var stype: String = square.get("type", "normal")
	if stype == "start":
		return COLOR_START
	elif stype == "goal":
		return COLOR_GOAL
	elif stype == "branch":
		return COLOR_BRANCH

	var event = square.get("event")
	if event == null or not event is Dictionary:
		return COLOR_EMPTY

	var kind: String = event.get("kind", "")
	match kind:
		"gain_money":
			return COLOR_GAIN
		"lose_money":
			return COLOR_LOSE
		"random_money":
			return COLOR_RANDOM
		"steal_money":
			return COLOR_STEAL
		"goal_bonus":
			return COLOR_GOAL
		_:
			return COLOR_EMPTY
