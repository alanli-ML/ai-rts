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
var fog_of_war_manager: Node

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

	# Use a more robust method to find fog manager with retries
	_find_fog_manager()

func _find_fog_manager() -> void:
	"""Find the fog of war manager with multiple search strategies"""
	# Strategy 1: Direct find by name
	fog_of_war_manager = get_tree().get_root().find_child("FogOfWarManager", true, false)
	
	if not fog_of_war_manager:
		# Strategy 2: Search in UnifiedMain
		var unified_main = get_tree().get_root().find_child("UnifiedMain", true, false)
		if unified_main:
			fog_of_war_manager = unified_main.find_child("FogOfWarManager", true, false)
	
	if not fog_of_war_manager:
		# Strategy 3: Search by class type
		var all_nodes = get_tree().get_nodes_in_group("fog_managers")
		if all_nodes.size() > 0:
			fog_of_war_manager = all_nodes[0]
	
	if fog_of_war_manager:
		print("ClientDisplayManager: Found FogOfWarManager: %s" % fog_of_war_manager.get_path())
	else:
		print("ClientDisplayManager: Warning - Could not find FogOfWarManager yet, will retry")

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
	
	# Pass visibility data to the fog of war manager
	if state.has("visibility_grid"):
		# Retry finding fog manager if we don't have one
		if not is_instance_valid(fog_of_war_manager):
			_find_fog_manager()
		
		if is_instance_valid(fog_of_war_manager):
			var grid_data = state.visibility_grid
			var grid_meta = state.visibility_grid_meta
			
			# Debug: Log visibility data reception
			if grid_data and grid_meta:
				var visible_count = 0
				for i in range(grid_data.size()):
					if grid_data[i] == 255:
						visible_count += 1
				print("ClientDisplayManager: Received visibility data - %d visible cells out of %d total" % [visible_count, grid_data.size()])
			else:
				print("ClientDisplayManager: Warning - visibility data is missing or invalid")
			
			if fog_of_war_manager.has_method("update_visibility_grid"):
				fog_of_war_manager.update_visibility_grid(grid_data, grid_meta)
				print("ClientDisplayManager: Passed visibility data to fog manager")
			else:
				print("ClientDisplayManager: Error - fog manager missing update_visibility_grid method")
		else:
			print("ClientDisplayManager: Warning - fog manager still not found, visibility data will be skipped this frame")
	else:
		print("ClientDisplayManager: No visibility data in state update")

func _update_host_plan_data() -> void:
	"""Update plan data on host units for UI display without visual rendering"""
	if not latest_state or not latest_state.has("units"):
		return
	
	# IMPORTANT: Only update units that are in the filtered state data
	# This ensures the host only sees units they should be able to see
	for unit_data in latest_state.units:
		var unit_id = unit_data.id
		
		# Update the displayed_units dictionary for consistency with client behavior
		if not displayed_units.has(unit_id):
			# Create a lightweight unit reference for UI purposes
			var unit_placeholder = Node.new()
			unit_placeholder.name = "HostUnit_%s" % unit_id
			unit_placeholder.set("unit_id", unit_id)
			unit_placeholder.set("team_id", unit_data.team_id)
			unit_placeholder.set("archetype", unit_data.archetype)
			unit_placeholder.set("current_health", unit_data.get("current_health", 100))
			unit_placeholder.set("max_health", unit_data.get("max_health", 100))
			unit_placeholder.set("is_dead", unit_data.get("is_dead", false))
			unit_placeholder.set("global_position", Vector3(
				unit_data.position.x, 
				unit_data.position.y, 
				unit_data.position.z
			))
			displayed_units[unit_id] = unit_placeholder
		
		var unit_instance = displayed_units[unit_id]
		if is_instance_valid(unit_instance):
			# Update plan data that the UI needs from the filtered data
			if unit_data.has("strategic_goal"):
				unit_instance.set("strategic_goal", unit_data.strategic_goal)
			if unit_data.has("plan_summary"):
				unit_instance.set("plan_summary", unit_data.plan_summary)
			if unit_data.has("control_point_attack_sequence"):
				unit_instance.set("control_point_attack_sequence", unit_data.control_point_attack_sequence)
			if unit_data.has("current_attack_sequence_index"):
				unit_instance.set("current_attack_sequence_index", unit_data.current_attack_sequence_index)
			
			# Update health and other basic properties
			if unit_data.has("current_health"):
				unit_instance.set("current_health", unit_data.current_health)
			if unit_data.has("is_dead"):
				unit_instance.set("is_dead", unit_data.is_dead)
			if unit_data.has("position"):
				unit_instance.set("global_position", Vector3(
					unit_data.position.x, 
					unit_data.position.y, 
					unit_data.position.z
				))
	
	# Remove units that are no longer in the filtered state (they moved out of vision)
	var current_unit_ids = []
	for unit_data in latest_state.units:
		current_unit_ids.append(unit_data.id)
	
	var displayed_unit_ids = displayed_units.keys()
	for unit_id in displayed_unit_ids:
		if unit_id not in current_unit_ids:
			var unit_instance = displayed_units[unit_id]
			displayed_units.erase(unit_id)
			if is_instance_valid(unit_instance):
				unit_instance.queue_free()
			print("ClientDisplayManager: Host removed unit %s (no longer visible)" % unit_id)

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
	var pos_data = unit_data.get("position")
	if pos_data:
		unit_instance.global_position = Vector3(pos_data.x, pos_data.y, pos_data.z)
	
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
	
	# Interpolate position and rotation for smooth movement
	if unit_data.has("position"):
		var server_pos_data = unit_data.position
		var server_pos = Vector3(server_pos_data.x, server_pos_data.y, server_pos_data.z)
		unit_instance.global_position = unit_instance.global_position.lerp(server_pos, 0.5)

	if unit_data.has("basis"):
		var b = unit_data.basis
		var server_basis = Basis(
			Vector3(b.x.x, b.x.y, b.x.z),
			Vector3(b.y.x, b.y.y, b.y.z),
			Vector3(b.z.x, b.z.y, b.z.z)
		)
		unit_instance.transform.basis = unit_instance.transform.basis.slerp(server_basis, 0.2)
	
	# Update animation based on server velocity
	if unit_data.has("velocity"):
		var vel_data = unit_data.velocity
		var server_velocity = Vector3(vel_data.x, vel_data.y, vel_data.z)
		if unit_instance.has_method("update_client_visuals"):
			unit_instance.update_client_visuals(server_velocity, delta)

	# Update current state for animation
	if unit_data.has("current_state"):
		unit_instance.current_state = unit_data.current_state

	# Update plan summary from server
	if unit_data.has("plan_summary"):
		if unit_instance.has_method("update_plan_summary"):
			unit_instance.update_plan_summary(unit_data.plan_summary)
		else:
			unit_instance.set("plan_summary", unit_data.plan_summary)
	
	# Update strategic goal from server
	if unit_data.has("strategic_goal"):
		print("ClientDisplayManager: Updating unit %s strategic goal to: '%s'" % [unit_id, unit_data.strategic_goal])
		
		if "strategic_goal" in unit_instance:
			unit_instance.strategic_goal = unit_data.strategic_goal
		else:
			unit_instance.set("strategic_goal", unit_data.strategic_goal)
		
		# Check if unit has status bar
		if unit_instance.status_bar:
			print("ClientDisplayManager: Unit %s has status bar, calling refresh" % unit_id)
		else:
			print("ClientDisplayManager: WARNING - Unit %s does not have status bar!" % unit_id)
		
		# Refresh the status bar to show updated goal
		if unit_instance.has_method("refresh_status_bar"):
			unit_instance.refresh_status_bar()
			print("ClientDisplayManager: Called refresh_status_bar() for unit %s" % unit_id)
		else:
			print("ClientDisplayManager: WARNING - Unit %s does not have refresh_status_bar method!" % unit_id)
		
		# Refresh HUD unit status if strategic goal changed
		var game_hud = get_tree().get_first_node_in_group("game_hud")
		if not game_hud:
			game_hud = get_node_or_null("/root/UnifiedMain/GameHUD")
		if game_hud and game_hud.has_method("update_unit_data"):
			game_hud.update_unit_data(unit_id, unit_data)
	
	# Update control point attack sequence from server
	if unit_data.has("control_point_attack_sequence"):
		if "control_point_attack_sequence" in unit_instance:
			unit_instance.control_point_attack_sequence = unit_data.control_point_attack_sequence
		else:
			unit_instance.set("control_point_attack_sequence", unit_data.control_point_attack_sequence)
		
		# Refresh the status bar to show updated target sequence
		if unit_instance.has_method("refresh_status_bar"):
			unit_instance.refresh_status_bar()
	
	# Update current attack sequence index from server
	if unit_data.has("current_attack_sequence_index"):
		if "current_attack_sequence_index" in unit_instance:
			unit_instance.current_attack_sequence_index = unit_data.current_attack_sequence_index
		else:
			unit_instance.set("current_attack_sequence_index", unit_data.current_attack_sequence_index)
		
		# Refresh the status bar to show updated sequence progress
		if unit_instance.has_method("refresh_status_bar"):
			unit_instance.refresh_status_bar()
	
	# Update health from server
	if unit_data.has("health"):
		var old_health = unit_instance.current_health
		unit_instance.current_health = unit_data.health
		# Emit health changed signal if health actually changed
		if old_health != unit_instance.current_health:
			unit_instance.health_changed.emit(unit_instance.current_health, unit_instance.max_health)
	
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

	# Note: Plan data and high-frequency UI data are now sent via separate RPCs.
	# This keeps the main state packet small.
	var behavior_data_updated = false
	# NOTE: The GameHUD and UnitStatusBar now use their own timers to refresh their displays
	# periodically. Forcing an update here on every network tick was causing severe performance
	# degradation. The UI components will pick up the data changes on their own schedule.

	# Update charge shot data for snipers
	if unit_data.has("charge_timer") and unit_data.has("charge_time"):
		if unit_instance.has_method("update_charge_data"):
			unit_instance.update_charge_data(unit_data.charge_timer, unit_data.charge_time)

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