extends Control

const RANK_COLORS: Array[Color] = [
	Color(1.0, 0.85, 0.0),   # 金
	Color(0.75, 0.75, 0.8),  # 銀
	Color(0.8, 0.5, 0.2),    # 銅
	Color(0.6, 0.6, 0.7),    # 通常
]

@onready var rank_labels: Array[Label] = [
	$CenterContainer/VBoxContainer/Rank1,
	$CenterContainer/VBoxContainer/Rank2,
	$CenterContainer/VBoxContainer/Rank3,
	$CenterContainer/VBoxContainer/Rank4,
]
@onready var your_result_label: Label = $CenterContainer/VBoxContainer/YourResultLabel
@onready var menu_button: Button = $CenterContainer/VBoxContainer/MenuButton

func _ready() -> void:
	menu_button.pressed.connect(_on_menu_pressed)

	var rankings = GameState.final_rankings
	for i in range(4):
		if i < rankings.size():
			var r = rankings[i]
			var name_str: String = r.get("name", "???")
			var money: int = int(r.get("money", 0))
			var rank: int = int(r.get("rank", i + 1))
			rank_labels[i].text = "%d位: %s  %d円" % [rank, name_str, money]
			var color = RANK_COLORS[i] if i < RANK_COLORS.size() else RANK_COLORS[3]
			rank_labels[i].add_theme_color_override("font_color", color)
			rank_labels[i].visible = true
		else:
			rank_labels[i].visible = false

	# 自分の順位を表示
	var my_rank = -1
	for i in range(rankings.size()):
		if int(rankings[i].get("player_index", -1)) == GameState.player_index:
			my_rank = i + 1
			break
	if my_rank > 0:
		your_result_label.text = "あなたは %d位 でした！" % my_rank
	else:
		your_result_label.text = ""

func _on_menu_pressed() -> void:
	WebSocketClient.close()
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
