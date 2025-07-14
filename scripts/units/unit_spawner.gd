# UnitSpawner.gd
class_name UnitSpawner
extends Node3D

# Unit classes
const Unit = preload("res://scripts/core/unit.gd")

# Unit spawn settings
@export var max_units_per_team: int = 10
@export var spawn_radius: float = 5.0
@export var spawn_height: float = 1.0

# Spawn tracking
var units_spawned: Dictionary = {}  # team_id -> int
var active_units: Dictionary = {}   # unit_id -> Unit
var spawn_points: Dictionary = {}   # team_id -> Vector3

# Unit ID generation
var next_unit_id: int = 1

# Signals
signal unit_spawned(unit: Unit)
signal unit_destroyed(unit: Unit)
signal max_units_reached(team_id: int)

func _ready() -> void:
	# Connect to map spawn points
	_setup_spawn_points()
	
	# Connect to EventBus
	EventBus.unit_spawn_requested.connect(_on_unit_spawn_requested)
	EventBus.unit_destroy_requested.connect(_on_unit_destroy_requested)
	
	Logger.info("UnitSpawner", "Unit spawner initialized")

func _setup_spawn_points() -> void:
	# Get spawn points from the map
	var spawn_nodes = get_tree().get_nodes_in_group("spawn_points")
	
	for spawn_node in spawn_nodes:
		if spawn_node.name.contains("Team1"):
			spawn_points[1] = spawn_node.global_position
		elif spawn_node.name.contains("Team2"):
			spawn_points[2] = spawn_node.global_position
	
	# Default spawn points if none found
	if not spawn_points.has(1):
		spawn_points[1] = Vector3(10, 0, 10)
	if not spawn_points.has(2):
		spawn_points[2] = Vector3(90, 0, 90)
	
	Logger.debug("UnitSpawner", "Spawn points configured: %s" % spawn_points)

func spawn_unit(archetype: String, team_id: int, custom_position: Vector3 = Vector3.ZERO) -> Unit:
	# Check unit limits
	var current_count = units_spawned.get(team_id, 0)
	if current_count >= max_units_per_team:
		Logger.warning("UnitSpawner", "Cannot spawn unit: max units reached for team %d" % team_id)
		max_units_reached.emit(team_id)
		return null
	
	# Get spawn position
	var spawn_position = custom_position
	if spawn_position == Vector3.ZERO:
		spawn_position = _get_spawn_position(team_id)
	
	# Create unit based on archetype
	var unit = _create_unit(archetype, team_id, spawn_position)
	if not unit:
		Logger.error("UnitSpawner", "Failed to create unit of archetype: %s" % archetype)
		return null
	
	# Configure unit
	unit.unit_id = _generate_unit_id()
	unit.position = spawn_position
	
	# Add to scene
	add_child(unit)
	
	# Track unit
	active_units[unit.unit_id] = unit
	units_spawned[team_id] = current_count + 1
	
	# Connect unit signals
	unit.unit_died.connect(_on_unit_died)
	unit.unit_selected.connect(_on_unit_selected)
	unit.unit_deselected.connect(_on_unit_deselected)
	
	Logger.info("UnitSpawner", "Spawned %s unit %s for team %d at %s" % [archetype, unit.unit_id, team_id, spawn_position])
	unit_spawned.emit(unit)
	
	return unit

func _create_unit(archetype: String, team_id: int, spawn_position: Vector3) -> Unit:
	var unit: Unit
	
	unit = Unit.new()
	unit.archetype = archetype
	
	if unit:
		unit.archetype = archetype
		unit.team_id = team_id
		unit.name = "Unit_%s_%s" % [archetype, team_id]
	
	return unit

func _get_spawn_position(team_id: int) -> Vector3:
	var base_position = spawn_points.get(team_id, Vector3.ZERO)
	
	# Add random offset within spawn radius
	var angle = randf() * 2 * PI
	var radius = randf() * spawn_radius
	var offset = Vector3(
		cos(angle) * radius,
		spawn_height,
		sin(angle) * radius
	)
	
	return base_position + offset

func _generate_unit_id() -> String:
	var id = "unit_%d" % next_unit_id
	next_unit_id += 1
	return id

func destroy_unit(unit_id: String) -> void:
	if not active_units.has(unit_id):
		Logger.warning("UnitSpawner", "Cannot destroy unit: unit %s not found" % unit_id)
		return
	
	var unit = active_units[unit_id]
	var team_id = unit.team_id
	
	# Remove from tracking
	active_units.erase(unit_id)
	units_spawned[team_id] = units_spawned.get(team_id, 0) - 1
	
	# Emit signal
	unit_destroyed.emit(unit)
	
	# Remove from scene
	unit.queue_free()
	
	Logger.info("UnitSpawner", "Destroyed unit %s from team %d" % [unit_id, team_id])

func get_units_for_team(team_id: int) -> Array[Unit]:
	var team_units: Array[Unit] = []
	
	for unit in active_units.values():
		if unit.team_id == team_id:
			team_units.append(unit)
	
	return team_units

func get_unit_by_id(unit_id: String) -> Unit:
	return active_units.get(unit_id, null)

func get_units_in_radius(center: Vector3, radius: float, team_id: int = -1) -> Array[Unit]:
	var units_in_radius: Array[Unit] = []
	
	for unit in active_units.values():
		if team_id != -1 and unit.team_id != team_id:
			continue
			
		var distance = center.distance_to(unit.global_position)
		if distance <= radius:
			units_in_radius.append(unit)
	
	return units_in_radius

func get_unit_count(team_id: int) -> int:
	return units_spawned.get(team_id, 0)

func get_total_unit_count() -> int:
	return active_units.size()

func spawn_default_units(team_id: int) -> void:
	# Spawn a balanced mix of units for testing
	var unit_composition = [
		"scout", "scout",
		"tank", "tank",
		"sniper", "sniper",
		"medic", "medic",
		"engineer", "engineer"
	]
	
	for archetype in unit_composition:
		spawn_unit(archetype, team_id)
		await get_tree().create_timer(0.1).timeout  # Small delay between spawns

func clear_all_units() -> void:
	for unit in active_units.values():
		unit.queue_free()
	
	active_units.clear()
	units_spawned.clear()
	
	Logger.info("UnitSpawner", "Cleared all units")

# Signal handlers
func _on_unit_spawn_requested(archetype: String, team_id: int, position: Vector3) -> void:
	spawn_unit(archetype, team_id, position)

func _on_unit_destroy_requested(unit_id: String) -> void:
	destroy_unit(unit_id)

func _on_unit_died(unit: Unit) -> void:
	# Unit died naturally, remove from tracking
	active_units.erase(unit.unit_id)
	units_spawned[unit.team_id] = units_spawned.get(unit.team_id, 0) - 1
	
	unit_destroyed.emit(unit)
	Logger.info("UnitSpawner", "Unit %s died" % unit.unit_id)

func _on_unit_selected(unit: Unit) -> void:
	EventBus.unit_selected.emit(unit)

func _on_unit_deselected(unit: Unit) -> void:
	EventBus.unit_deselected.emit(unit) 