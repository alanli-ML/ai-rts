# TeamUnitSpawner.gd
class_name TeamUnitSpawner
extends Node

var resource_manager: ResourceManager
const UNIT_SCENE = preload("res://scenes/units/AnimatedUnit.tscn")
const UNIT_COST = {"energy": 100} # Simplified cost

const ARCHETYPE_SCRIPTS = {
	"scout": "res://scripts/units/scout_unit.gd",
	"tank": "res://scripts/units/tank_unit.gd",
	"sniper": "res://scripts/units/sniper_unit.gd",
	"medic": "res://scripts/units/medic_unit.gd",
	"engineer": "res://scripts/units/engineer_unit.gd",
}

func spawn_initial_squads(map_node: Node) -> void:
	var team1_spawn = map_node.get_node("SpawnPoints/Team1Spawn").global_position
	var team2_spawn = map_node.get_node("SpawnPoints/Team2Spawn").global_position
	
	for i in range(5):
		await spawn_unit(1, team1_spawn + Vector3(i * 2, 0, 0))
		await spawn_unit(2, team2_spawn + Vector3(i * 2, 0, 0))

func request_spawn_unit(team_id: int, archetype: String) -> bool:
	if resource_manager.consume_resources(team_id, UNIT_COST):
		var spawn_pos = Vector3.ZERO # Get from home base
		var home_base_manager = get_tree().get_first_node_in_group("home_base_managers")
		if home_base_manager:
			spawn_pos = home_base_manager.get_team_spawn_position(team_id)
			
		await spawn_unit(team_id, spawn_pos, archetype)
		return true
	
	return false

func spawn_unit(team_id: int, position: Vector3, archetype: String = "scout") -> Node:
	var unit = UNIT_SCENE.instantiate()

	# Attach the correct script based on the archetype
	var script_path = ARCHETYPE_SCRIPTS.get(archetype)
	if script_path:
		var script = load(script_path)
		if script:
			unit.set_script(script)
		else:
			print("TeamUnitSpawner: ERROR - Could not load script for archetype %s at path %s" % [archetype, script_path])
			unit.queue_free()
			return null
	else:
		print("TeamUnitSpawner: ERROR - No script path defined for archetype %s" % archetype)
		unit.queue_free()
		return null
	
	# Find the "Units" container node to keep the scene tree clean
	var units_node = get_tree().get_root().find_child("Units", true, false)
	if not units_node:
		print("TeamUnitSpawner: ERROR - 'Units' node not found in scene tree. Cannot spawn unit.")
		unit.queue_free()
		return null

	# Set properties that don't depend on the scene tree
	unit.team_id = team_id
	unit.archetype = archetype
	
	# Add to the Units node FIRST
	units_node.add_child(unit)
	
	# NOW set properties that require the node to be in the tree
	unit.global_position = position
	
	# The engine will call _ready() automatically. We await a frame to ensure it runs.
	await get_tree().process_frame

	if not is_instance_valid(unit) or not unit.has_method("get_unit_info"):
		print("TeamUnitSpawner: ERROR - Unit failed to initialize properly. Script not attached correctly.")
		if is_instance_valid(unit):
			unit.queue_free()
		return null
	
	if unit.unit_id.is_empty():
		print("TeamUnitSpawner: ERROR - Unit ID is empty after initialization.")
		unit.queue_free()
		return null

	print("TeamUnitSpawner: Successfully spawned unit %s (%s) for team %d at %s" % [
		unit.unit_id,
		unit.archetype,
		team_id,
		position
	])
	
	return unit