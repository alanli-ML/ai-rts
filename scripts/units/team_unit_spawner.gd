# TeamUnitSpawner.gd
class_name TeamUnitSpawner
extends Node

var resource_manager: ResourceManager
const UNIT_SCENE = preload("res://scenes/units/AnimatedUnit.tscn")
const UNIT_COST = {"energy": 100} # Simplified cost

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
	
	# Find the "Units" container node to keep the scene tree clean
	var units_node = get_tree().get_root().find_child("Units", true, false)
	if not units_node:
		print("TeamUnitSpawner: ERROR - 'Units' node not found in scene tree. Cannot spawn unit.")
		return null

	# Add to the Units node FIRST
	units_node.add_child(unit)
	
	# Wait for the next frame to ensure the unit's _ready() has been called
	await get_tree().process_frame
	
	# Now safely set properties after the unit is fully initialized
	if unit is Unit:
		unit.team_id = team_id
		unit.archetype = archetype
		unit.global_position = position
	else:
		print("TeamUnitSpawner: ERROR - Instantiated node is not a Unit. Type: %s" % unit.get_class())
		if unit.get_script():
			print("TeamUnitSpawner: Unit script: %s" % unit.get_script().resource_path)
		else:
			print("TeamUnitSpawner: Unit has no script attached.")
		unit.queue_free()
		return null
	
	return unit