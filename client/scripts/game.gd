extends Node2D

const PLAYER_COLORS: Array[Color] = [
	Color(0.2, 0.6, 1.0),   # 青
	Color(1.0, 0.3, 0.3),   # 赤
	Color(0.2, 0.9, 0.3),   # 緑
	Color(1.0, 0.8, 0.2),   # 黄
]

const TOKEN_RADIUS := 12.0
const TOKEN_OFFSETS: Array[Vector2] = [
	Vector2(-10, -10), Vector2(10, -10),
	Vector2(-10, 10), Vector2(10, 10),
]

# UI参照
@onready var turn_label: Label = $UILayer/TopBar/TurnLabel
@onready var player_info_labels: Array[Label] = [
	$UILayer/PlayerInfoPanel/PlayerInfo1,
	$UILayer/PlayerInfoPanel/PlayerInfo2,
	$UILayer/PlayerInfoPanel/PlayerInfo3,
	$UILayer/PlayerInfoPanel/PlayerInfo4,
]
@onready var dice_button: Button = $UILayer/DiceButton
@onready var dice_result_label: Label = $UILayer/DiceResultLabel
@onready var event_popup: PanelContainer = $UILayer/EventPopup
@onready var event_text: Label = $UILayer/EventPopup/EventVBox/EventText
@onready var event_amount_label: Label = $UILayer/EventPopup/EventVBox/EventAmountLabel
@onready var event_ok_button: Button = $UILayer/EventPopup/EventVBox/EventOKButton
@onready var branch_popup: PanelContainer = $UILayer/BranchPopup
@onready var branch_button1: Button = $UILayer/BranchPopup/BranchVBox/BranchButton1
@onready var branch_button2: Button = $UILayer/BranchPopup/BranchVBox/BranchButton2
@onready var countdown_label: Label = $UILayer/CountdownLabel

# ボードデータ
var board: Array = []
var square_positions: Array[Vector2] = []

# プレイヤー表示位置（アニメーション用）
var display_positions: Array[Vector2] = []
var target_positions: Array[Vector2] = []

# 移動アニメーション
var is_animating: bool = false
var anim_player_index: int = -1
var anim_path: Array = []
var anim_step: int = 0
var anim_timer: float = 0.0
const ANIM_STEP_DURATION := 0.35

# サイコロアニメーション
var dice_animating: bool = false
var dice_anim_timer: float = 0.0
var dice_final_value: int = 0

func _ready() -> void:
	# ボードデータ取得
	board = GameState.board
	square_positions = BoardData.compute_positions(board)

	# プレイヤー表示位置を初期化
	_init_display_positions()

	# UIイベント接続
	dice_button.pressed.connect(_on_dice_pressed)
	event_ok_button.pressed.connect(_on_event_ok_pressed)
	branch_button1.pressed.connect(func(): _on_branch_choice(0))
	branch_button2.pressed.connect(func(): _on_branch_choice(1))

	# WebSocket
	WebSocketClient.message_received.connect(_on_message)
	WebSocketClient.disconnected.connect(_on_disconnected)

	# 初期UI
	_update_player_info()
	_update_turn_label()
	dice_button.visible = GameState.is_my_turn()
	dice_result_label.text = ""
	event_popup.visible = false
	branch_popup.visible = false
	countdown_label.text = ""

func _process(delta: float) -> void:
	# サイコロアニメーション
	if dice_animating:
		dice_anim_timer += delta
		if dice_anim_timer < 1.0:
			# ランダム数字を高速表示
			dice_result_label.text = str(randi_range(1, 6))
		else:
			dice_result_label.text = str(dice_final_value)
			dice_animating = false

	# 移動アニメーション
	if is_animating:
		anim_timer += delta
		if anim_timer >= ANIM_STEP_DURATION:
			anim_timer = 0.0
			if anim_step < anim_path.size():
				var square_idx: int = int(anim_path[anim_step])
				if square_idx >= 0 and square_idx < square_positions.size():
					var sq_center = _get_square_center(square_idx)
					display_positions[anim_player_index] = sq_center + TOKEN_OFFSETS[anim_player_index]
					queue_redraw()
				anim_step += 1
			else:
				is_animating = false

	queue_redraw()

func _draw() -> void:
	# 背景
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.05, 0.05, 0.12))

	if board.is_empty() or square_positions.is_empty():
		return

	# 接続線を描画
	_draw_connections()

	# マスを描画
	for i in range(board.size()):
		_draw_square(i)

	# プレイヤートークンを描画
	_draw_tokens()

func _draw_connections() -> void:
	for i in range(board.size()):
		var square = board[i]
		var from_center = _get_square_center(i)
		var next_arr = square.get("next", [])
		for next_idx in next_arr:
			var ni: int = int(next_idx)
			if ni >= 0 and ni < square_positions.size():
				var to_center = _get_square_center(ni)
				draw_line(from_center, to_center, Color(0.3, 0.3, 0.4), 2.0)

func _draw_square(index: int) -> void:
	var pos = square_positions[index]
	var square = board[index]
	var color = BoardData.get_square_color(square)
	var sq_size = BoardData.SQUARE_SIZE

	# 現在のプレイヤーの位置をハイライト
	var is_current_pos = false
	if GameState.players.size() > GameState.current_player_index:
		var current_p = GameState.players[GameState.current_player_index]
		if int(current_p.get("position", -1)) == index:
			is_current_pos = true

	# マス描画
	var rect = Rect2(pos, Vector2(sq_size, sq_size))
	draw_rect(rect, color)
	if is_current_pos:
		draw_rect(rect, Color(1, 1, 1, 0.3), false, 3.0)

	# マス番号
	var stype: String = square.get("type", "normal")
	var label_text: String
	if stype == "start":
		label_text = "S"
	elif stype == "goal":
		label_text = "G"
	elif stype == "branch":
		label_text = "?"
	else:
		label_text = str(index)

	var font = ThemeDB.fallback_font
	var font_size = 14
	var text_size = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = pos + Vector2((sq_size - text_size.x) / 2, (sq_size + text_size.y) / 2 - 2)
	draw_string(font, text_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1))

func _draw_tokens() -> void:
	for i in range(display_positions.size()):
		if i >= GameState.players.size():
			break
		var p = GameState.players[i]
		if p.get("disconnected", false):
			continue
		var pos = display_positions[i]
		var color = PLAYER_COLORS[i] if i < PLAYER_COLORS.size() else Color.WHITE
		# 外枠
		draw_circle(pos, TOKEN_RADIUS + 2, Color(0, 0, 0, 0.5))
		# トークン
		draw_circle(pos, TOKEN_RADIUS, color)
		# ゴール済みマーク
		if p.get("finished", false):
			draw_circle(pos, TOKEN_RADIUS + 2, Color(1, 1, 1, 0.5), false, 2.0)

func _get_square_center(index: int) -> Vector2:
	if index < 0 or index >= square_positions.size():
		return Vector2.ZERO
	return square_positions[index] + Vector2(BoardData.SQUARE_SIZE / 2, BoardData.SQUARE_SIZE / 2)

func _init_display_positions() -> void:
	display_positions.clear()
	for i in range(GameState.players.size()):
		var p = GameState.players[i]
		var pos_idx: int = int(p.get("position", 0))
		var center = _get_square_center(pos_idx)
		display_positions.append(center + TOKEN_OFFSETS[i])

# ============================
# サーバーメッセージ処理
# ============================
func _on_message(data: Dictionary) -> void:
	var msg_type = data.get("type", "")
	match msg_type:
		"turn_start":
			_handle_turn_start(data)
		"dice_result":
			_handle_dice_result(data)
		"player_moving":
			_handle_player_moving(data)
		"branch_choice_request":
			_handle_branch_choice_request(data)
		"event_triggered":
			_handle_event_triggered(data)
		"player_finished":
			_handle_player_finished(data)
		"game_over":
			_handle_game_over(data)
		"player_disconnected":
			_handle_player_disconnected(data)

func _handle_turn_start(data: Dictionary) -> void:
	GameState.current_player_index = int(data.get("current_player", 0))
	GameState.players = data.get("players", GameState.players)
	_sync_display_positions()
	_update_player_info()
	_update_turn_label()
	dice_button.visible = GameState.is_my_turn()
	dice_result_label.text = ""
	event_popup.visible = false
	branch_popup.visible = false

func _handle_dice_result(data: Dictionary) -> void:
	dice_final_value = int(data.get("value", 1))
	dice_animating = true
	dice_anim_timer = 0.0
	dice_button.visible = false

func _handle_player_moving(data: Dictionary) -> void:
	var pi: int = int(data.get("player_index", 0))
	var path = data.get("path", [])
	if path.is_empty():
		return
	anim_player_index = pi
	anim_path = path
	anim_step = 0
	anim_timer = 0.0
	is_animating = true

func _handle_branch_choice_request(data: Dictionary) -> void:
	if not GameState.is_my_turn():
		return
	var options = data.get("options", [])
	if options.size() >= 2:
		branch_button1.text = options[0].get("label", "ルート1")
		branch_button2.text = options[1].get("label", "ルート2")
	branch_popup.visible = true

func _handle_event_triggered(data: Dictionary) -> void:
	GameState.players = data.get("players", GameState.players)
	_sync_display_positions()
	_update_player_info()

	var event = data.get("event", {})
	var text: String = event.get("text", "")
	var actual_amount: int = int(event.get("actual_amount", 0))
	var money_before: int = int(data.get("money_before", 0))
	var money_after: int = int(data.get("money_after", 0))

	event_text.text = text
	if actual_amount > 0:
		event_amount_label.text = "+%d円" % actual_amount
		event_amount_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))
	elif actual_amount < 0:
		event_amount_label.text = "%d円" % actual_amount
		event_amount_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		event_amount_label.text = "±0円"
		event_amount_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	event_ok_button.visible = GameState.is_my_turn()
	event_popup.visible = true

func _handle_player_finished(data: Dictionary) -> void:
	var pi: int = int(data.get("player_index", 0))
	var finish_order: int = int(data.get("finish_order", 0))
	var bonus: int = int(data.get("bonus", 0))

	# プレイヤー情報更新
	if pi < GameState.players.size():
		GameState.players[pi]["finished"] = true
		GameState.players[pi]["finish_order"] = finish_order
		GameState.players[pi]["money"] = int(data.get("money_after", GameState.players[pi].get("money", 0)))
	_update_player_info()

	# ゴール通知をターンラベルに表示
	var pname: String = ""
	if pi < GameState.players.size():
		pname = GameState.players[pi].get("name", "???")
	turn_label.text = "%s がゴール！ (%d位, +%d円)" % [pname, finish_order, bonus]

func _handle_game_over(data: Dictionary) -> void:
	GameState.final_rankings = data.get("rankings", [])
	# 少し待ってから結果画面へ
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/result.tscn")

func _handle_player_disconnected(data: Dictionary) -> void:
	var pi: int = int(data.get("player_index", 0))
	if pi < GameState.players.size():
		GameState.players[pi]["disconnected"] = true
	_update_player_info()
	turn_label.text = "%s が切断されました" % GameState.players[pi].get("name", "???")

# ============================
# UI操作
# ============================
func _on_dice_pressed() -> void:
	dice_button.visible = false
	WebSocketClient.send_message({"type": "roll_dice"})

func _on_event_ok_pressed() -> void:
	event_popup.visible = false
	WebSocketClient.send_message({"type": "event_ack"})

func _on_branch_choice(choice: int) -> void:
	branch_popup.visible = false
	WebSocketClient.send_message({"type": "branch_choice", "choice": choice})

func _on_disconnected() -> void:
	turn_label.text = "サーバーから切断されました"
	dice_button.visible = false
	await get_tree().create_timer(2.0).timeout
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# ============================
# ヘルパー
# ============================
func _update_player_info() -> void:
	for i in range(4):
		if i < GameState.players.size():
			var p = GameState.players[i]
			var name_str: String = p.get("name", "???")
			var money: int = int(p.get("money", 0))
			var finished: bool = p.get("finished", false)
			var disconnected: bool = p.get("disconnected", false)
			var color = PLAYER_COLORS[i] if i < PLAYER_COLORS.size() else Color.WHITE
			var suffix = ""
			if disconnected:
				suffix = " [切断]"
			elif finished:
				suffix = " [ゴール]"
			var arrow = "▶ " if i == GameState.current_player_index else "  "
			player_info_labels[i].text = "%s%s: %d円%s" % [arrow, name_str, money, suffix]
			player_info_labels[i].add_theme_color_override("font_color", color)
			player_info_labels[i].visible = true
		else:
			player_info_labels[i].visible = false

func _update_turn_label() -> void:
	if GameState.current_player_index < GameState.players.size():
		var p = GameState.players[GameState.current_player_index]
		var name_str: String = p.get("name", "???")
		if GameState.is_my_turn():
			turn_label.text = "  あなたのターン (%s)" % name_str
			turn_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		else:
			turn_label.text = "  %sのターン" % name_str
			turn_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))

func _sync_display_positions() -> void:
	# GameStateの位置からトークン表示位置を同期
	while display_positions.size() < GameState.players.size():
		display_positions.append(Vector2.ZERO)
	for i in range(GameState.players.size()):
		if is_animating and i == anim_player_index:
			continue
		var p = GameState.players[i]
		var pos_idx: int = int(p.get("position", 0))
		var center = _get_square_center(pos_idx)
		display_positions[i] = center + TOKEN_OFFSETS[i]

func _exit_tree() -> void:
	if WebSocketClient.message_received.is_connected(_on_message):
		WebSocketClient.message_received.disconnect(_on_message)
	if WebSocketClient.disconnected.is_connected(_on_disconnected):
		WebSocketClient.disconnected.disconnect(_on_disconnected)
