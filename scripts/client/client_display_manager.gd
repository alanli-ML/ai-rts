# ClientDisplayManager.gd - Renders the game state received from the server.
class_name ClientDisplayManager
extends Node

const UNIT_SCENE = preload("res://scenes/units/AnimatedUnit.tscn")

var displayed_units: Dictionary = {} # unit_id -> Node
var units_node: Node
var latest_state: Dictionary

func _ready() -> void:
	# The units_node reference will be set by UnifiedMain after the map is loaded.
	pass

func setup_map_references(map_node: Node) -> void:
	if not is_instance_valid(map_node):
		print("ClientDisplayManager: ERROR - Invalid map node provided for reference setup.")
		return
		
	units_node = map_node.find_child("Units", true, false)
	if not units_node:
		print("ClientDisplayManager: ERROR - Could not find 'Units' node in the provided map node.")

func _physics_process(delta: float) -> void:
	if not latest_state or not latest_state.has("units"):
		return
		
	if not units_node:
		return # Cannot process without the container node

	var server_unit_ids = []
	for unit_data in latest_state.units:
		server_unit_ids.append(unit_data.id)

		if not displayed_units.has(unit_data.id):
			# Unit doesn't exist on client, create it
			_create_unit(unit_data)
		else:
			# Unit exists, update it
			_update_unit(unit_data, delta)
	
	# Remove units that are on the client but not in the server state
	var client_unit_ids = displayed_units.keys()
	for unit_id in client_unit_ids:
		if unit_id not in server_unit_ids:
			remove_unit(unit_id)

func update_state(state: Dictionary) -> void:
	latest_state = state

func _create_unit(unit_data: Dictionary) -> void:
	var unit_id = unit_data.id
	var unit_instance = UNIT_SCENE.instantiate()
	unit_instance.unit_id = unit_id
	unit_instance.team_id = unit_data.team_id
	unit_instance.archetype = unit_data.archetype
	
	# Add to scene tree FIRST before setting position
	units_node.add_child(unit_instance)
	
	# NOW set position after the unit is in the tree
	var pos_arr = unit_data.position
	unit_instance.global_position = Vector3(pos_arr.x, pos_arr.y, pos_arr.z)
	
	displayed_units[unit_id] = unit_instance
	print("ClientDisplayManager: Created unit %s" % unit_id)

func _update_unit(unit_data: Dictionary, delta: float) -> void:
	var unit_id = unit_data.id
	var unit_instance = displayed_units[unit_id]
	
	var target_pos = Vector3(unit_data.position.x, unit_data.position.y, unit_data.position.z)
	
	# Smoothly interpolate position to avoid jitter
	unit_instance.global_position = unit_instance.global_position.lerp(target_pos, delta * 10.0)
	
	var server_velocity = Vector3(unit_data.velocity.x, unit_data.velocity.y, unit_data.velocity.z)
	if unit_instance.has_method("update_client_visuals"):
		unit_instance.update_client_visuals(server_velocity, delta)

func remove_unit(unit_id: String) -> void:
	if displayed_units.has(unit_id):
		var unit_instance = displayed_units[unit_id]
		# Erase immediately to prevent it being updated or selected again
		displayed_units.erase(unit_id)
		
		if is_instance_valid(unit_instance):
			# The unit will handle its own death animation and queue_free
			if unit_instance.has_method("die_and_cleanup"):
				unit_instance.die_and_cleanup()
			else:
				# Fallback for non-animated units
				unit_instance.queue_free()
				
		print("ClientDisplayManager: Removed unit %s" % unit_id)

func cleanup() -> void:
	for unit_id in displayed_units:
		var unit = displayed_units[unit_id]
		if is_instance_valid(unit):
			unit.queue_free()
	displayed_units.clear()