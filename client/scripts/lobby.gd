extends Control

const PLAYER_COLORS: Array[Color] = [
	Color(0.2, 0.6, 1.0),   # 青
	Color(1.0, 0.3, 0.3),   # 赤
	Color(0.2, 0.9, 0.3),   # 緑
	Color(1.0, 0.8, 0.2),   # 黄
]

@onready var room_code_label: Label = $CenterContainer/VBoxContainer/RoomCodeLabel
@onready var player_labels: Array[Label] = [
	$CenterContainer/VBoxContainer/Player1,
	$CenterContainer/VBoxContainer/Player2,
	$CenterContainer/VBoxContainer/Player3,
	$CenterContainer/VBoxContainer/Player4,
]
@onready var player_count_label: Label = $CenterContainer/VBoxContainer/PlayerCount
@onready var start_button: Button = $CenterContainer/VBoxContainer/ButtonContainer/StartButton
@onready var leave_button: Button = $CenterContainer/VBoxContainer/ButtonContainer/LeaveButton
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	WebSocketClient.message_received.connect(_on_message)
	WebSocketClient.disconnected.connect(_on_disconnected)

	room_code_label.text = GameState.room_code
	start_button.visible = GameState.is_host
	_update_player_list(GameState.players)

func _on_message(data: Dictionary) -> void:
	var msg_type = data.get("type", "")
	match msg_type:
		"player_joined":
			GameState.players = data.get("players", [])
			_update_player_list(GameState.players)
		"player_left":
			GameState.players = data.get("players", [])
			_update_player_list(GameState.players)
		"host_changed":
			var new_host_index = int(data.get("new_host_index", 0))
			GameState.is_host = (GameState.player_index == new_host_index)
			start_button.visible = GameState.is_host
			_update_player_list(GameState.players)
			if GameState.is_host:
				status_label.text = "あなたがホストになりました"
		"game_started":
			GameState.board = data.get("board", [])
			GameState.players = data.get("players", [])
			GameState.current_player_index = int(data.get("first_player", 0))
			GameState.is_game_started = true
			get_tree().change_scene_to_file("res://scenes/game.tscn")
		"room_error":
			status_label.text = data.get("message", "エラー")

func _on_start_pressed() -> void:
	WebSocketClient.send_message({"type": "start_game"})
	start_button.disabled = true

func _on_leave_pressed() -> void:
	WebSocketClient.close()
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_disconnected() -> void:
	status_label.text = "サーバーから切断されました"
	await get_tree().create_timer(1.5).timeout
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _update_player_list(players: Array) -> void:
	for i in range(4):
		if i < players.size():
			var p = players[i]
			var name_str: String = p.get("name", "???")
			var is_host: bool = p.get("is_host", false)
			var suffix = " (ホスト)" if is_host else ""
			player_labels[i].text = "%d. %s%s" % [i + 1, name_str, suffix]
			player_labels[i].add_theme_color_override("font_color", PLAYER_COLORS[i])
		else:
			player_labels[i].text = "%d. 待機中..." % [i + 1]
			player_labels[i].add_theme_color_override("font_color", Color(0.4, 0.4, 0.5, 1))

	player_count_label.text = "%d/4 プレイヤー" % players.size()

	if GameState.is_host:
		start_button.disabled = players.size() < 2

func _exit_tree() -> void:
	if WebSocketClient.message_received.is_connected(_on_message):
		WebSocketClient.message_received.disconnect(_on_message)
	if WebSocketClient.disconnected.is_connected(_on_disconnected):
		WebSocketClient.disconnected.disconnect(_on_disconnected)
