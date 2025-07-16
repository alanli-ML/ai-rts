# ClientDisplayManager.gd - Renders the game state received from the server.
class_name ClientDisplayManager
extends Node

const UNIT_SCENE = preload("res://scenes/units/AnimatedUnit.tscn")
const MINE_SCENE = preload("res://scripts/gameplay/mine.gd")

var displayed_units: Dictionary = {} # unit_id -> Node
var displayed_mines: Dictionary = {} # mine_id -> Node
var displayed_control_points: Dictionary = {} # cp_id -> { "node": ControlPoint, "team_id": int }
var units_node: Node
var mines_node: Node
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

	mines_node = map_node.find_child("Mines", true, false)
	if not mines_node:
		mines_node = Node3D.new()
		mines_node.name = "Mines"
		map_node.add_child(mines_node)

	var capture_nodes_container = map_node.find_child("CaptureNodes", true, false)
	if capture_nodes_container:
		for cp_node in capture_nodes_container.get_children():
			# Check if it's a ControlPoint and has a valid ID
			if cp_node is ControlPoint and not cp_node.control_point_id.is_empty():
				displayed_control_points[cp_node.control_point_id] = { "node": cp_node, "team_id": 0 }
		print("ClientDisplayManager: Found and mapped %d control points." % displayed_control_points.size())
	else:
		print("ClientDisplayManager: ERROR - Could not find 'CaptureNodes' container.")

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		return # Do not run display logic on the server/host

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

	# Process mines
	if latest_state.has("mines"):
		var server_mine_ids = []
		for mine_data in latest_state.mines:
			server_mine_ids.append(mine_data.id)

			if not displayed_mines.has(mine_data.id):
				_create_mine(mine_data)
		
		# Remove mines that are on the client but not in the server state
		var client_mine_ids = displayed_mines.keys()
		for mine_id in client_mine_ids:
			if mine_id not in server_mine_ids:
				remove_mine(mine_id)

	# Process control points
	if latest_state.has("control_points"):
		for cp_data in latest_state.control_points:
			var cp_id = cp_data.id
			if displayed_control_points.has(cp_id):
				var cp_node_data = displayed_control_points[cp_id]
				var cp_node = cp_node_data.node
				var old_team_id = cp_node_data.team_id
				var new_team_id = cp_data.get("team_id", 0)

				if is_instance_valid(cp_node) and cp_node.has_method("update_client_visuals"):
					cp_node.update_client_visuals(cp_data)
				
				# Play sound on capture
				if new_team_id != old_team_id and new_team_id != 0:
					var audio_manager = get_node_or_null("/root/DependencyContainer/AudioManager")
					if audio_manager:
						audio_manager.play_sound_2d("res://assets/audio/ui/command_submit_01.wav") # Using a known-good sound
				
				# Update stored team id
				cp_node_data.team_id = new_team_id

func update_state(state: Dictionary) -> void:
	if multiplayer.is_server():
		return # Do not run display logic on the server/host
	latest_state = state

func _create_unit(unit_data: Dictionary) -> void:
	var unit_id = unit_data.id
	var unit_instance = UNIT_SCENE.instantiate()
	unit_instance.unit_id = unit_id
	unit_instance.team_id = unit_data.team_id
	unit_instance.archetype = unit_data.archetype
	
	# Add a placeholder for the shield node if it's a tank
	if unit_data.archetype == "tank":
		unit_instance.set("shield_node", null)

	# Add to scene tree FIRST before setting position
	units_node.add_child(unit_instance)
	
	# NOW set position after the unit is in the tree
	var pos_arr = unit_data.position
	unit_instance.global_position = Vector3(pos_arr.x, pos_arr.y, pos_arr.z)
	
	displayed_units[unit_id] = unit_instance
	print("ClientDisplayManager: Created unit %s" % unit_id)

func _create_mine(mine_data: Dictionary) -> void:
	var mine_id = mine_data.id
	var mine_instance = MINE_SCENE.new()
	mine_instance.mine_id = mine_id
	mine_instance.team_id = mine_data.team_id
	
	mines_node.add_child(mine_instance)
	
	var pos_arr = mine_data.position
	mine_instance.global_position = Vector3(pos_arr.x, pos_arr.y, pos_arr.z)
	
	displayed_mines[mine_id] = mine_instance
	print("ClientDisplayManager: Created mine %s" % mine_id)

func remove_mine(mine_id: String) -> void:
	if displayed_mines.has(mine_id):
		var mine_instance = displayed_mines[mine_id]
		displayed_mines.erase(mine_id)
		if is_instance_valid(mine_instance):
			mine_instance.queue_free()
		print("ClientDisplayManager: Removed mine %s" % mine_id)

func _update_unit(unit_data: Dictionary, delta: float) -> void:
	var unit_id = unit_data.id
	var unit_instance = displayed_units[unit_id]
	
	var target_pos = Vector3(unit_data.position.x, unit_data.position.y, unit_data.position.z)
	
	# Smoothly interpolate position to avoid jitter
	unit_instance.global_position = unit_instance.global_position.lerp(target_pos, delta * 10.0)
	
	var server_velocity = Vector3(unit_data.velocity.x, unit_data.velocity.y, unit_data.velocity.z)
	if unit_instance.has_method("update_client_visuals"):
		unit_instance.update_client_visuals(server_velocity, delta)

	# Update plan summary from server
	if unit_data.has("plan_summary"):
		if unit_instance.has_method("update_plan_summary"):
			unit_instance.update_plan_summary(unit_data.plan_summary)
		else:
			unit_instance.plan_summary = unit_data.plan_summary
	
	# Update full plan data from server
	if unit_data.has("full_plan"):
		# Store full plan data directly on the unit for HUD access
		unit_instance.full_plan = unit_data.full_plan
		# Also call update method if available
		if unit_instance.has_method("update_full_plan"):
			unit_instance.update_full_plan(unit_data.full_plan)

	# Update shield visual
	if unit_data.has("shield_active"):
		if unit_data.shield_active and not is_instance_valid(unit_instance.get("shield_node")):
			var shield_scene = preload("res://scenes/fx/ShieldEffect.tscn")
			var shield_effect = shield_scene.instantiate()
			unit_instance.add_child(shield_effect)
			unit_instance.shield_node = shield_effect
		elif not unit_data.shield_active and is_instance_valid(unit_instance.get("shield_node")):
			unit_instance.shield_node.queue_free()
			unit_instance.shield_node = null

	# Update stealth visual
	if unit_data.has("is_stealthed"):
		var model_container = unit_instance.get_node_or_null("ModelContainer")
		if model_container:
			var was_stealthed = unit_instance.get_meta("was_stealthed", false)
			if unit_data.is_stealthed != was_stealthed:
				if unit_data.is_stealthed:
					_set_model_transparency(model_container, 0.3)
				else:
					_set_model_transparency(model_container, 1.0)
				unit_instance.set_meta("was_stealthed", unit_data.is_stealthed)

func _set_model_transparency(model_container: Node3D, alpha_value: float) -> void:
	"""Set transparency for all MeshInstance3D nodes in the model container"""
	if not is_instance_valid(model_container):
		return
	
	# Find all MeshInstance3D nodes recursively
	var mesh_instances = _find_all_mesh_instances(model_container)
	
	for mesh_instance in mesh_instances:
		if not is_instance_valid(mesh_instance):
			continue
		
		# Skip if no mesh or surfaces
		if not mesh_instance.mesh or mesh_instance.get_surface_override_material_count() == 0:
			continue
			
		# Get existing material or create from mesh surface material
		var material = mesh_instance.get_surface_override_material(0)
		
		# If no override material, try to get the mesh's built-in material
		if not material and mesh_instance.mesh.surface_get_material(0):
			material = mesh_instance.mesh.surface_get_material(0)
			
		# If still no material, create a basic one with proper initialization
		if not material:
			material = StandardMaterial3D.new()
			# Set basic material properties to avoid null parameter errors
			material.albedo_color = Color.WHITE
			material.metallic = 0.0
			material.roughness = 0.7
			material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		
		# Always duplicate the material to avoid affecting other instances
		if material:
			material = material.duplicate()
			mesh_instance.set_surface_override_material(0, material)
			
			# Apply transparency settings
			if material is StandardMaterial3D:
				var std_material = material as StandardMaterial3D
				if alpha_value < 1.0:
					std_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					std_material.albedo_color.a = alpha_value
				else:
					std_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED  
					std_material.albedo_color.a = 1.0

func _find_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	"""Recursively find all MeshInstance3D nodes"""
	var mesh_instances: Array[MeshInstance3D] = []
	
	if node is MeshInstance3D:
		mesh_instances.append(node as MeshInstance3D)
	
	for child in node.get_children():
		mesh_instances.append_array(_find_all_mesh_instances(child))
	
	return mesh_instances

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

	for mine_id in displayed_mines:
		var mine = displayed_mines[mine_id]
		if is_instance_valid(mine):
			mine.queue_free()
	displayed_mines.clear()
	displayed_control_points.clear()