extends Control

@onready var name_edit: LineEdit = $CenterContainer/VBoxContainer/NameContainer/NameLineEdit
@onready var create_button: Button = $CenterContainer/VBoxContainer/CreateButton
@onready var code_edit: LineEdit = $CenterContainer/VBoxContainer/JoinContainer/CodeLineEdit
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinContainer/JoinButton
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

var _pending_action: String = ""

func _ready() -> void:
	create_button.pressed.connect(_on_create_pressed)
	join_button.pressed.connect(_on_join_pressed)
	status_label.text = ""
	# コード入力を大文字に変換
	code_edit.text_changed.connect(func(new_text: String):
		code_edit.text = new_text.to_upper()
		code_edit.caret_column = code_edit.text.length()
	)

func _on_create_pressed() -> void:
	var player_name = _get_player_name()
	if player_name.is_empty():
		status_label.text = "名前を入力してください"
		return
	_pending_action = "create"
	_set_buttons_disabled(true)
	status_label.text = "サーバーに接続中..."
	WebSocketClient.connected.connect(_on_connected, CONNECT_ONE_SHOT)
	WebSocketClient.disconnected.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	WebSocketClient.connect_to_server()

func _on_join_pressed() -> void:
	var player_name = _get_player_name()
	if player_name.is_empty():
		status_label.text = "名前を入力してください"
		return
	var code = code_edit.text.strip_edges().to_upper()
	if code.length() != 5:
		status_label.text = "ルームコードは5文字です"
		return
	_pending_action = "join"
	_set_buttons_disabled(true)
	status_label.text = "サーバーに接続中..."
	WebSocketClient.connected.connect(_on_connected, CONNECT_ONE_SHOT)
	WebSocketClient.disconnected.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	WebSocketClient.connect_to_server()

func _on_connected() -> void:
	if WebSocketClient.disconnected.is_connected(_on_connection_failed):
		WebSocketClient.disconnected.disconnect(_on_connection_failed)
	WebSocketClient.message_received.connect(_on_message, CONNECT_ONE_SHOT)
	var player_name = _get_player_name()
	GameState.player_name = player_name
	if _pending_action == "create":
		WebSocketClient.send_message({"type": "create_room", "name": player_name})
	elif _pending_action == "join":
		var code = code_edit.text.strip_edges().to_upper()
		WebSocketClient.send_message({"type": "join_room", "code": code, "name": player_name})

func _on_message(data: Dictionary) -> void:
	var msg_type = data.get("type", "")
	match msg_type:
		"room_created":
			GameState.room_code = data.get("code", "")
			GameState.player_index = 0
			GameState.is_host = true
			GameState.players = data.get("players", [])
			get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		"room_joined":
			GameState.room_code = data.get("code", "")
			GameState.player_index = int(data.get("player_index", 0))
			GameState.is_host = false
			GameState.players = data.get("players", [])
			get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		"room_error":
			status_label.text = data.get("message", "エラーが発生しました")
			_set_buttons_disabled(false)
			WebSocketClient.close()

func _on_connection_failed() -> void:
	if WebSocketClient.connected.is_connected(_on_connected):
		WebSocketClient.connected.disconnect(_on_connected)
	status_label.text = "接続に失敗しました"
	_set_buttons_disabled(false)

func _get_player_name() -> String:
	var n = name_edit.text.strip_edges()
	if n.is_empty():
		return ""
	return n

func _set_buttons_disabled(disabled: bool) -> void:
	create_button.disabled = disabled
	join_button.disabled = disabled
