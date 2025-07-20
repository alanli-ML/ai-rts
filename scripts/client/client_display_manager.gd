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
	# On the host/server, only update plan data for UI, not visual rendering
	if multiplayer.is_server():
		_update_host_plan_data()
		return

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
	# Always store latest state, even on server for UI plan data
	latest_state = state

func _update_host_plan_data() -> void:
	"""Update plan data on host units for UI display without visual rendering"""
	if not latest_state or not latest_state.has("units"):
		return
	
	# Get the server game state to access actual unit instances
	var server_game_state = get_node_or_null("/root/DependencyContainer/GameState")
	if not server_game_state:
		return
	
	# Update plan data on server unit instances for UI access
	for unit_data in latest_state.units:
		var unit_id = unit_data.id
		if server_game_state.units.has(unit_id):
			var unit_instance = server_game_state.units[unit_id]
			if is_instance_valid(unit_instance):
				# Update plan data that the UI needs
				if unit_data.has("full_plan"):
					unit_instance.full_plan = unit_data.full_plan
				if unit_data.has("strategic_goal"):
					unit_instance.strategic_goal = unit_data.strategic_goal
				if unit_data.has("plan_summary"):
					unit_instance.plan_summary = unit_data.plan_summary

func _create_unit(unit_data: Dictionary) -> void:
	var unit_id = unit_data.id
	var unit_instance = UNIT_SCENE.instantiate()
	unit_instance.unit_id = unit_id
	unit_instance.team_id = unit_data.team_id
	unit_instance.archetype = unit_data.archetype
	
	# Add a placeholder for the shield node if it's a tank
	if unit_data.archetype == "tank":
		unit_instance.set("shield_node", null)
	
	# Set default behavior matrix from game constants (same as server-side units)
	var GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
	var default_matrix = GameConstants.get_default_behavior_matrix(unit_data.archetype)
	if not default_matrix.is_empty():
		unit_instance.behavior_matrix = default_matrix.duplicate()
		print("ClientDisplayManager: Set default behavior matrix for unit %s (%s)" % [unit_id, unit_data.archetype])

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
	
	# Check for death/respawn state changes
	var server_is_dead = unit_data.get("is_dead", false)
	var server_is_respawning = unit_data.get("is_respawning", false)
	
	if server_is_dead:
		if not unit_instance.is_dead:
			if unit_instance.has_method("trigger_death_sequence"):
				unit_instance.trigger_death_sequence()
			else:
				# Fallback for non-animated units
				unit_instance.is_dead = true
				unit_instance.visible = false # Or some other visual change
		return # Don't process other updates for dead units
	elif not server_is_dead and unit_instance.is_dead:
		# Unit has respawned! Transition from dead to alive
		unit_instance.is_dead = false
		unit_instance.is_respawning = false
		
		if unit_instance.has_method("trigger_respawn_sequence"):
			unit_instance.trigger_respawn_sequence()
		else:
			# Fallback for non-animated units
			unit_instance.visible = true
	
	var target_pos = Vector3(unit_data.position.x, unit_data.position.y, unit_data.position.z)
	
	# Smoothly interpolate position to avoid jitter
	unit_instance.global_position = unit_instance.global_position.lerp(target_pos, delta * 10.0)

	# Smoothly interpolate rotation based on server-authoritative basis
	if unit_data.has("basis"):
		var basis_data = unit_data.basis
		var target_basis = Basis(
			Vector3(basis_data.x[0], basis_data.x[1], basis_data.x[2]),
			Vector3(basis_data.y[0], basis_data.y[1], basis_data.y[2]),
			Vector3(basis_data.z[0], basis_data.z[1], basis_data.z[2])
		)
		unit_instance.transform.basis = unit_instance.transform.basis.slerp(target_basis, delta * 10.0)

	# Update current state for animation
	if unit_data.has("current_state"):
		unit_instance.current_state = unit_data.current_state
	
	var server_velocity = Vector3(unit_data.velocity.x, unit_data.velocity.y, unit_data.velocity.z)
	if unit_instance.has_method("update_client_visuals"):
		unit_instance.update_client_visuals(server_velocity, delta)

	# Update plan summary from server
	if unit_data.has("plan_summary"):
		if unit_instance.has_method("update_plan_summary"):
			unit_instance.update_plan_summary(unit_data.plan_summary)
		else:
			unit_instance.set("plan_summary", unit_data.plan_summary)
	
	# Update strategic goal from server
	if unit_data.has("strategic_goal"):
		unit_instance.set("strategic_goal", unit_data.strategic_goal)
		# Also update status bar if it exists
		if unit_instance.has_method("refresh_status_bar"):
			unit_instance.refresh_status_bar()
	
	# Update AI processing status from server
	if unit_data.has("waiting_for_ai"):
		unit_instance.set("waiting_for_ai", unit_data.waiting_for_ai)
		# Update status bar to show processing state if needed
		if unit_instance.has_method("set_ai_processing_status"):
			unit_instance.set_ai_processing_status(unit_data.waiting_for_ai)
	
	# Update health from server
	if unit_data.has("health"):
		var old_health = unit_instance.current_health
		unit_instance.current_health = unit_data.health
		# Emit health changed signal if health actually changed
		if old_health != unit_instance.current_health:
			unit_instance.health_changed.emit(unit_instance.current_health, unit_instance.max_health)
	
	# Update full plan data from server
	if unit_data.has("full_plan"):
		# Store full plan data directly on the unit for HUD access
		unit_instance.set("full_plan", unit_data.full_plan)
		# Also call update method if available
		if unit_instance.has_method("update_full_plan"):
			unit_instance.update_full_plan(unit_data.full_plan)
	
	# Update control point attack sequence from server
	if unit_data.has("control_point_attack_sequence"):
		unit_instance.set("control_point_attack_sequence", unit_data.control_point_attack_sequence)
	
	# Update current attack sequence index from server
	if unit_data.has("current_attack_sequence_index"):
		unit_instance.set("current_attack_sequence_index", unit_data.current_attack_sequence_index)
		# Refresh status bar to show updated progress
		if unit_instance.has_method("refresh_status_bar"):
			unit_instance.refresh_status_bar()
	
	# Update waiting for first command status from server
	if unit_data.has("waiting_for_first_command"):
		unit_instance.set("waiting_for_first_command", unit_data.waiting_for_first_command)
	
	if unit_data.has("has_received_first_command"):
		unit_instance.set("has_received_first_command", unit_data.has_received_first_command)
		# Refresh status bar when command state changes
		if unit_instance.has_method("refresh_status_bar"):
			unit_instance.refresh_status_bar()
	
	# NOTE: active_triggers and all_triggers are deprecated - replaced by behavior matrix system
	# Skipping these assignments to avoid property errors on client units

	# Update behavior matrix and scores for UI
	var behavior_data_updated = false
	if unit_data.has("behavior_matrix"):
		# Use set() for safer property assignment
		unit_instance.set("behavior_matrix", unit_data.behavior_matrix)
		behavior_data_updated = true
	if unit_data.has("last_action_scores"):
		# print("DEBUG: ClientDisplayManager updating unit %s with server action scores: %s" % [unit_id, str(unit_data.last_action_scores)])
		unit_instance.set("last_action_scores", unit_data.last_action_scores)
		behavior_data_updated = true
	if unit_data.has("last_state_variables"):
		unit_instance.set("last_state_variables", unit_data.last_state_variables)
		behavior_data_updated = true
	if unit_data.has("current_reactive_state"):
		# print("DEBUG: ClientDisplayManager updating unit %s with server reactive state: %s" % [unit_id, unit_data.current_reactive_state])
		unit_instance.set("current_reactive_state", unit_data.current_reactive_state)
		behavior_data_updated = true
	
	# Refresh status bar when behavior matrix data changes
	if behavior_data_updated:
		# Force status bar to refresh its behavior matrix display
		if unit_instance.has_method("refresh_status_bar"):
			unit_instance.refresh_status_bar()
		
		# Also force the status bar to update its behavior display directly
		var status_bar = unit_instance.get_node_or_null("UnitStatusBar")
		if status_bar and status_bar.has_method("force_refresh"):
			status_bar.force_refresh()
		
		# Also refresh the HUD selection display if this unit is currently selected
		_refresh_hud_if_unit_selected(unit_instance)

	# Update shield visual (only for units that support shields)
	if unit_data.has("shield_active") and "shield_node" in unit_instance:
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

	# Update charge shot data for snipers
	if unit_data.has("charge_timer") and unit_data.has("charge_time"):
		if unit_instance.has_method("update_charge_data"):
			unit_instance.update_charge_data(unit_data.charge_timer, unit_data.charge_time)

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
			if unit_instance.has_method("trigger_death_sequence"):
				unit_instance.trigger_death_sequence()
			else:
				# Fallback for non-animated units
				unit_instance.queue_free()
				
		print("ClientDisplayManager: Removed unit %s" % unit_id)

func _refresh_hud_if_unit_selected(unit_instance: Node) -> void:
	"""Refresh the HUD selection display if the given unit is currently selected"""
	# Find the selection system to check if this unit is selected
	var selection_system = null
	var selection_nodes = get_tree().get_nodes_in_group("selection_systems")
	if not selection_nodes.is_empty():
		selection_system = selection_nodes[0]
	
	if not selection_system:
		return
	
	# Check if this unit is currently selected
	var selected_units = selection_system.get_selected_units()
	var is_selected = false
	for selected_unit in selected_units:
		if selected_unit == unit_instance:
			is_selected = true
			break
	
	if not is_selected:
		return
	
	# Find the game HUD and refresh its selection display
	var game_hud = get_tree().get_first_node_in_group("game_hud")
	if not game_hud:
		# Fallback: try to find it via path
		game_hud = get_node_or_null("/root/UnifiedMain/GameHUD")
	
	if game_hud and game_hud.has_method("_update_selection_display"):
		game_hud._update_selection_display(selected_units)
	
	# Also specifically refresh behavior matrix display if the method exists
	if game_hud and game_hud.has_method("_refresh_behavior_matrix_display"):
		game_hud._refresh_behavior_matrix_display()

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