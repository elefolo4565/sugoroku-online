extends Node

# 接続情報
var player_index: int = -1
var player_name: String = ""
var room_code: String = ""
var is_host: bool = false

# ゲーム状態（サーバーから同期）
var players: Array = []
var board: Array = []
var current_player_index: int = 0
var turn_phase: String = "idle"
var is_game_started: bool = false

# 結果
var final_rankings: Array = []

func reset() -> void:
	player_index = -1
	player_name = ""
	room_code = ""
	is_host = false
	players = []
	board = []
	current_player_index = 0
	turn_phase = "idle"
	is_game_started = false
	final_rankings = []

func is_my_turn() -> bool:
	return current_player_index == player_index
