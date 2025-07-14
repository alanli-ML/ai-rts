# GameManager.gd
extends Node

# Game states
enum GameState {
	MENU,
	LOBBY,
	LOADING,
	IN_GAME,
	PAUSED,
	GAME_OVER
}

var current_state: GameState = GameState.MENU
var previous_state: GameState = GameState.MENU

# Game data
var current_map: String = ""
var player_count: int = 0
var match_time: float = 0.0
var game_config: Dictionary = {}

# Unit registry
var unit_registry: Dictionary = {}  # unit_id -> Unit
var units_by_team: Dictionary = {}  # team_id -> Array[Unit]

# Player data
var player_data: Dictionary = {}  # player_id -> Dictionary

# Signals
signal state_changed(new_state: GameState)
signal game_started()
signal game_ended(winner: int)
signal match_time_updated(time: float)

func _ready() -> void:
	Logger.info("GameManager", "GameManager initialized")
	
	# Initialize unit tracking
	units_by_team[1] = []
	units_by_team[2] = []
	
	# Connect to EventBus
	EventBus.unit_spawned.connect(_on_unit_spawned)
	EventBus.unit_died.connect(_on_unit_died)

func _process(delta: float) -> void:
	if current_state == GameState.IN_GAME:
		match_time += delta
		match_time_updated.emit(match_time)

func change_state(new_state: GameState) -> void:
	if new_state == current_state:
		return
	
	previous_state = current_state
	current_state = new_state
	
	Logger.info("GameManager", "Game state changed from %s to %s" % [GameState.keys()[previous_state], GameState.keys()[current_state]])
	state_changed.emit(current_state)
	
	# Handle state transitions
	match current_state:
		GameState.IN_GAME:
			_start_game()
		GameState.GAME_OVER:
			_end_game()

func _start_game() -> void:
	match_time = 0.0
	Logger.info("GameManager", "Game started")
	game_started.emit()

func _end_game() -> void:
	Logger.info("GameManager", "Game ended")
	# Determine winner logic would go here
	game_ended.emit(1)  # Placeholder winner

func get_current_state() -> GameState:
	return current_state

func get_match_time() -> float:
	return match_time

func get_match_time_formatted() -> String:
	var minutes = int(match_time) / 60
	var seconds = int(match_time) % 60
	return "%02d:%02d" % [minutes, seconds]

# Unit management functions
func register_unit(unit: Variant) -> void:
	if not unit or not unit.has_method("get"):
		Logger.error("GameManager", "Invalid unit registration attempt")
		return
	
	var unit_id = unit.unit_id
	var team_id = unit.team_id
	
	# Add to registry
	unit_registry[unit_id] = unit
	
	# Add to team tracking
	if not units_by_team.has(team_id):
		units_by_team[team_id] = []
	units_by_team[team_id].append(unit)
	
	Logger.debug("GameManager", "Registered unit %s for team %d" % [unit_id, team_id])

func unregister_unit(unit: Variant) -> void:
	if not unit:
		return
	
	var unit_id = unit.unit_id
	var team_id = unit.team_id
	
	# Remove from registry
	unit_registry.erase(unit_id)
	
	# Remove from team tracking
	if units_by_team.has(team_id):
		units_by_team[team_id].erase(unit)
	
	Logger.debug("GameManager", "Unregistered unit %s from team %d" % [unit_id, team_id])

func get_unit_by_id(unit_id: String) -> Variant:
	return unit_registry.get(unit_id, null)

func get_units_for_team(team_id: int) -> Array:
	return units_by_team.get(team_id, [])

func get_unit_count(team_id: int) -> int:
	return units_by_team.get(team_id, []).size()

func get_total_unit_count() -> int:
	return unit_registry.size()

func get_alive_units() -> Array:
	var alive_units = []
	for unit in unit_registry.values():
		if unit and not unit.is_dead:
			alive_units.append(unit)
	return alive_units

func get_team_with_most_units() -> int:
	var team1_count = get_unit_count(1)
	var team2_count = get_unit_count(2)
	
	if team1_count > team2_count:
		return 1
	elif team2_count > team1_count:
		return 2
	else:
		return 0  # Tie

func clear_all_units() -> void:
	unit_registry.clear()
	for team_id in units_by_team.keys():
		units_by_team[team_id].clear()
	Logger.info("GameManager", "Cleared all units from registry")

# Victory condition checks
func check_victory_conditions() -> void:
	if current_state != GameState.IN_GAME:
		return
	
	# Check if any team has no units left
	var team1_alive = 0
	var team2_alive = 0
	
	for unit in get_alive_units():
		if unit.team_id == 1:
			team1_alive += 1
		elif unit.team_id == 2:
			team2_alive += 1
	
	if team1_alive == 0 and team2_alive > 0:
		_declare_victory(2)
	elif team2_alive == 0 and team1_alive > 0:
		_declare_victory(1)
	elif team1_alive == 0 and team2_alive == 0:
		_declare_victory(0)  # Draw

func _declare_victory(winner: int) -> void:
	change_state(GameState.GAME_OVER)
	
	if winner == 0:
		Logger.info("GameManager", "Match ended in a draw")
	else:
		Logger.info("GameManager", "Team %d wins!" % winner)
	
	game_ended.emit(winner)

# Player management
func add_player(player_id: int, player_info: Dictionary) -> void:
	player_data[player_id] = player_info
	player_count = player_data.size()
	Logger.info("GameManager", "Added player %d, total players: %d" % [player_id, player_count])

func remove_player(player_id: int) -> void:
	if player_data.has(player_id):
		player_data.erase(player_id)
		player_count = player_data.size()
		Logger.info("GameManager", "Removed player %d, total players: %d" % [player_id, player_count])

func get_player_data(player_id: int) -> Dictionary:
	return player_data.get(player_id, {})

# Game configuration
func set_game_config(config: Dictionary) -> void:
	game_config = config
	Logger.debug("GameManager", "Game configuration updated")

func get_game_config() -> Dictionary:
	return game_config

# Map management
func load_map(map_name: String) -> void:
	current_map = map_name
	Logger.info("GameManager", "Loading map: %s" % map_name)

func get_current_map() -> String:
	return current_map

# Signal handlers
func _on_unit_spawned(unit: Variant) -> void:
	register_unit(unit)

func _on_unit_died(unit: Variant) -> void:
	unregister_unit(unit)
	
	# Check victory conditions after unit death
	check_victory_conditions()

# Debug functions
func get_debug_info() -> Dictionary:
	return {
		"current_state": GameState.keys()[current_state],
		"match_time": get_match_time_formatted(),
		"total_units": get_total_unit_count(),
		"team1_units": get_unit_count(1),
		"team2_units": get_unit_count(2),
		"player_count": player_count,
		"current_map": current_map
	}

func print_debug_info() -> void:
	var debug_info = get_debug_info()
	Logger.info("GameManager", "Debug Info: %s" % debug_info) 