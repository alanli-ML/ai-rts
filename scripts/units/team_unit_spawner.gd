# TeamUnitSpawner.gd
class_name TeamUnitSpawner
extends Node

# Unit configuration
const UNITS_PER_TEAM = 5
const UNIT_ARCHETYPES = ["scout", "tank", "sniper", "medic", "engineer"]

# References
var map_node: Node3D
var Unit = preload("res://scripts/core/unit.gd")

func _ready() -> void:
	# Connect to match events
	EventBus.match_started.connect(_on_match_started)
	EventBus.team_data_updated.connect(_on_team_data_updated)
	
	Logger.info("TeamUnitSpawner", "Team-based unit spawner initialized")

func _on_match_started() -> void:
	Logger.info("TeamUnitSpawner", "Match started - spawning team units")
	spawn_team_units()

func spawn_team_units() -> void:
	"""Spawn units for each team with cooperative control"""
	if not map_node:
		map_node = get_tree().get_first_node_in_group("maps")
	
	if not map_node:
		Logger.error("TeamUnitSpawner", "No map node found")
		return
	
	# Clear existing units
	_clear_existing_units()
	
	# Spawn units for each team
	for team_id in NetworkManager.teams.keys():
		var team_data = NetworkManager.teams[team_id]
		if team_data.player_ids.size() > 0:
			_spawn_team_units(team_data)

func _spawn_team_units(team_data: NetworkManager.TeamData) -> void:
	"""Spawn 5 units for a specific team with shared control"""
	var spawn_position = _get_team_spawn_position(team_data.team_id)
	var spawn_positions = _generate_formation_positions(spawn_position, UNITS_PER_TEAM)
	
	Logger.info("TeamUnitSpawner", "Spawning %d units for team %d at %s" % [UNITS_PER_TEAM, team_data.team_id, spawn_position])
	
	# Create units with shared team ownership
	for i in range(UNITS_PER_TEAM):
		var unit_archetype = UNIT_ARCHETYPES[i]
		var unit_position = spawn_positions[i]
		var unit = _create_team_unit(unit_archetype, team_data.team_id, unit_position)
		
		if unit:
			team_data.units.append(unit)
			Logger.info("TeamUnitSpawner", "Created %s unit for team %d at %s" % [unit_archetype, team_data.team_id, unit_position])

func _create_team_unit(archetype: String, team_id: int, position: Vector3) -> Node:
	"""Create a unit with team-based ownership"""
	var unit_scene = preload("res://scenes/units/AnimatedUnit.tscn")
	var unit = unit_scene.instantiate()
	unit.archetype = archetype
	unit.team_id = team_id
	unit.position = position
	
	# Add to scene
	if map_node:
		map_node.add_child(unit)
	else:
		add_child(unit)
	
	# Register unit with team
	EventBus.unit_spawned.emit(unit)
	
	return unit

func _get_team_spawn_position(team_id: int) -> Vector3:
	"""Get spawn position for team"""
	# Try to get spawn position from HomeBaseManager first
	var home_base_manager = _find_home_base_manager()
	if home_base_manager:
		var spawn_pos = home_base_manager.get_team_spawn_position(team_id)
		if spawn_pos != Vector3.ZERO:
			return spawn_pos
	
	# Fallback to new home base positions (bottom-left and top-right corners)
	var spawn_positions = {
		1: Vector3(-40, 0, -52),  # Team 1 spawn: In front of bottom-left home base
		2: Vector3(40, 0, 28)     # Team 2 spawn: In front of top-right home base
	}
	return spawn_positions.get(team_id, Vector3.ZERO)

func _find_home_base_manager() -> Node:
	"""Find HomeBaseManager in the scene"""
	var managers = get_tree().get_nodes_in_group("home_base_managers")
	if managers.size() > 0:
		return managers[0]
	
	# Try to find by name
	var scene_root = get_tree().current_scene
	if scene_root:
		return scene_root.find_child("HomeBaseManager", true, false)
	
	return null

func _generate_formation_positions(center: Vector3, count: int) -> Array:
	"""Generate positions in a formation around the center point"""
	var positions: Array = []
	var spacing = 5.0
	var rows = 2
	var cols = 3
	
	for i in range(count):
		var row = i / cols
		var col = i % cols
		var x_offset = (col - 1) * spacing
		var z_offset = (row - 0.5) * spacing
		positions.append(center + Vector3(x_offset, 0, z_offset))
	
	return positions

func _clear_existing_units() -> void:
	"""Clear all existing units from the scene"""
	var existing_units = get_tree().get_nodes_in_group("units")
	for unit in existing_units:
		if unit:
			unit.queue_free()
	
	# Clear units from team data
	for team_data in NetworkManager.teams.values():
		team_data.units.clear()

func _on_team_data_updated(teams: Array) -> void:
	"""Handle team data updates"""
	Logger.info("TeamUnitSpawner", "Team data updated with %d teams" % teams.size())

# Team unit management functions
func get_team_units(team_id: int) -> Array:
	"""Get all units for a specific team"""
	if team_id in NetworkManager.teams:
		return NetworkManager.teams[team_id].units
	return []

func get_shared_controlled_units(player_id: int) -> Array:
	"""Get units that can be controlled by a specific player (team's units)"""
	var player_data = NetworkManager.get_player_data(player_id)
	if not player_data:
		return []
	
	return get_team_units(player_data.team_id)

func can_player_control_unit(player_id: int, unit) -> bool:
	"""Check if a player can control a specific unit"""
	var player_data = NetworkManager.get_player_data(player_id)
	if not player_data:
		return false
	
	return unit.team_id == player_data.team_id

func issue_team_command(team_id: int, command: Dictionary, issuer_id: int) -> void:
	"""Issue a command to team units with issuer tracking"""
	var team_units = get_team_units(team_id)
	
	Logger.info("TeamUnitSpawner", "Team %d command issued by player %d: %s" % [team_id, issuer_id, command])
	
	# Process command for team units
	for unit in team_units:
		if unit and unit.has_method("_on_command_received"):
			unit._on_command_received(command)
	
	# Emit event for UI updates
	EventBus.team_command_issued.emit(team_id, command, issuer_id)

func get_team_status(team_id: int) -> Dictionary:
	"""Get comprehensive status of a team"""
	if team_id not in NetworkManager.teams:
		return {}
	
	var team_data = NetworkManager.teams[team_id]
	var alive_units = []
	var dead_units = []
	
	for unit in team_data.units:
		if unit and not unit.is_dead:
			alive_units.append(unit)
		else:
			dead_units.append(unit)
	
	return {
		"team_id": team_id,
		"team_name": team_data.team_name,
		"players": team_data.player_ids,
		"total_units": team_data.units.size(),
		"alive_units": alive_units.size(),
		"dead_units": dead_units.size(),
		"is_eliminated": alive_units.size() == 0
	} 