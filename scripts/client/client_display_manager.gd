# ClientDisplayManager.gd
# Client-side display manager - handles rendering and input only
class_name ClientDisplayManager
extends Node

# Load shared components
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# Display state (received from server)
var displayed_units: Dictionary = {}  # unit_id -> DisplayUnit
var displayed_buildings: Dictionary = {}  # building_id -> DisplayBuilding
var game_state: Dictionary = {}

# Input handling
var selection_manager: EnhancedSelectionSystem
var camera_controller: Node
var ui_manager: Node

# Network connection
var server_connection: ServerConnection
var connected_to_server: bool = false

# Interpolation for smooth movement
var interpolation_enabled: bool = true
var interpolation_buffer: Array = []

# Signals
signal unit_selected(unit_ids: Array)
signal ai_command_entered(command: String)
signal connection_status_changed(connected: bool)

func _ready() -> void:
	# Initialize components
	selection_manager = EnhancedSelectionSystem.new()
	add_child(selection_manager)
	
	# Setup server connection
	server_connection = ServerConnection.new()
	add_child(server_connection)
	server_connection.game_state_received.connect(_on_game_state_received)
	server_connection.connected_to_server.connect(_on_connected_to_server)
	server_connection.disconnected_from_server.connect(_on_disconnected_from_server)
	
	# Connect selection signals
	selection_manager.selection_changed.connect(_on_selection_changed)
	
	print("ClientDisplayManager initialized")

func _input(event: InputEvent) -> void:
	if not connected_to_server:
		return
	
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey:
		_handle_key_input(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_left_click(event.position)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_handle_right_click(event.position)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	# Handle mouse motion (for camera drag, etc.)
	pass

func _handle_left_click(position: Vector2) -> void:
	# Handle unit selection - client-side visual feedback only
	var world_pos = _screen_to_world(position)
	var modifier_keys = {
		"shift": Input.is_action_pressed("shift") if InputMap.has_action("shift") else false,
		"ctrl": Input.is_action_pressed("ctrl") if InputMap.has_action("ctrl") else false
	}
	
	# Find units at position
	var units_at_position = _get_units_at_position(world_pos)
	
	if units_at_position.size() > 0:
		# Select units locally for immediate feedback
		if modifier_keys.shift:
			selection_manager.add_to_selection(units_at_position)
		else:
			selection_manager.select_units(units_at_position)
		
		# Send selection to server for validation
		_send_input_to_server({
			"input_type": "select_units",
			"target_position": [world_pos.x, world_pos.y, world_pos.z],
			"selected_units": units_at_position,
			"modifier_keys": modifier_keys
		})
	else:
		# Clear selection
		selection_manager.clear_selection()

func _handle_right_click(position: Vector2) -> void:
	# Handle unit commands - send to server for processing
	var world_pos = _screen_to_world(position)
	var selected_units = selection_manager.get_selected_units()
	
	if selected_units.size() > 0:
		# Check if clicking on enemy unit (attack command)
		var units_at_position = _get_units_at_position(world_pos)
		var enemy_unit = _get_enemy_unit(units_at_position)
		
		if enemy_unit:
			# Attack command
			_send_input_to_server({
				"input_type": "attack_target",
				"target_id": enemy_unit.unit_id,
				"selected_units": selected_units
			})
		else:
			# Move command
			_send_input_to_server({
				"input_type": "move_units",
				"target_position": [world_pos.x, world_pos.y, world_pos.z],
				"selected_units": selected_units
			})

func _handle_key_input(event: InputEventKey) -> void:
	# Handle AI command input
	if event.pressed and event.keycode == KEY_ENTER:
		_show_ai_command_input()

func _show_ai_command_input() -> void:
	# Show AI command input dialog
	var selected_units = selection_manager.get_selected_units()
	if selected_units.size() > 0:
		# This would open a UI dialog for AI command input
		# For now, we'll simulate it
		ai_command_entered.emit("Move to strategic position")

func _on_ai_command_entered(command: String) -> void:
	var selected_units = selection_manager.get_selected_units()
	if selected_units.size() > 0:
		# Send AI command to server
		_send_ai_command_to_server(command, selected_units)

func _send_input_to_server(input_data: Dictionary) -> void:
	if connected_to_server:
		server_connection.send_player_input(input_data)

func _send_ai_command_to_server(command: String, selected_units: Array) -> void:
	if connected_to_server:
		server_connection.send_ai_command(command, selected_units)

# Server state updates
func _on_game_state_received(state_data: Dictionary) -> void:
	game_state = state_data
	_update_displayed_units(state_data.get("units", []))
	_update_displayed_buildings(state_data.get("buildings", []))
	_update_resources(state_data.get("resources", {}))
	_update_match_state(state_data.get("match_state", ""))

func _update_displayed_units(units_data: Array) -> void:
	# Update or create display units based on server data
	var current_unit_ids = Set.new()
	
	for unit_data in units_data:
		var unit_id = unit_data.get("id", "")
		current_unit_ids.add(unit_id)
		
		if unit_id in displayed_units:
			# Update existing unit
			var display_unit = displayed_units[unit_id]
			display_unit.update_from_server_data(unit_data)
		else:
			# Create new display unit
			var display_unit = _create_display_unit(unit_data)
			displayed_units[unit_id] = display_unit
			add_child(display_unit)
	
	# Remove units that no longer exist on server
	for unit_id in displayed_units.keys():
		if not current_unit_ids.has(unit_id):
			var display_unit = displayed_units[unit_id]
			displayed_units.erase(unit_id)
			display_unit.queue_free()

func _create_display_unit(unit_data: Dictionary) -> DisplayUnit:
	var display_unit = DisplayUnit.new()
	display_unit.setup_from_server_data(unit_data)
	return display_unit

func _update_displayed_buildings(buildings_data: Array) -> void:
	# Similar to units, but for buildings
	var current_building_ids = Set.new()
	
	for building_data in buildings_data:
		var building_id = building_data.get("id", "")
		current_building_ids.add(building_id)
		
		if building_id in displayed_buildings:
			var display_building = displayed_buildings[building_id]
			display_building.update_from_server_data(building_data)
		else:
			var display_building = _create_display_building(building_data)
			displayed_buildings[building_id] = display_building
			add_child(display_building)
	
	# Remove buildings that no longer exist
	for building_id in displayed_buildings.keys():
		if not current_building_ids.has(building_id):
			var display_building = displayed_buildings[building_id]
			displayed_buildings.erase(building_id)
			display_building.queue_free()

func _create_display_building(building_data: Dictionary) -> DisplayBuilding:
	var display_building = DisplayBuilding.new()
	display_building.setup_from_server_data(building_data)
	return display_building

func _update_resources(resources_data: Dictionary) -> void:
	# Update UI with resource information
	if ui_manager:
		ui_manager.update_resources(resources_data)

func _update_match_state(match_state: String) -> void:
	# Update UI with match state
	if ui_manager:
		ui_manager.update_match_state(match_state)

# Utility functions
func _screen_to_world(screen_pos: Vector2) -> Vector3:
	# Convert screen position to world position
	var camera = get_viewport().get_camera_3d()
	if camera:
		var from = camera.project_ray_origin(screen_pos)
		var to = from + camera.project_ray_normal(screen_pos) * 1000
		
		# Intersect with ground plane (y = 0)
		var t = -from.y / (to.y - from.y)
		return from + (to - from) * t
	return Vector3.ZERO

func _get_units_at_position(world_pos: Vector3) -> Array:
	var units_at_pos = []
	for unit_id in displayed_units:
		var unit = displayed_units[unit_id]
		if unit.global_position.distance_to(world_pos) < GameConstants.UNIT_SELECTION_RADIUS:
			units_at_pos.append(unit)
	return units_at_pos

func _get_enemy_unit(units: Array) -> DisplayUnit:
	# Find enemy unit in the given units
	for unit in units:
		if unit.team_id != _get_local_player_team():
			return unit
	return null

func _get_local_player_team() -> int:
	# Get the local player's team ID
	return server_connection.get_local_player_team()

# Selection management
func _on_selection_changed(selected_units: Array) -> void:
	# Update UI to show selected units
	if ui_manager:
		ui_manager.update_selected_units(selected_units)
	
	unit_selected.emit(selected_units)

# Connection management
func _on_connected_to_server() -> void:
	connected_to_server = true
	connection_status_changed.emit(true)
	print("Connected to server")

func _on_disconnected_from_server() -> void:
	connected_to_server = false
	connection_status_changed.emit(false)
	print("Disconnected from server")

# Public interface
func connect_to_server(server_address: String, port: int) -> void:
	server_connection.connect_to_server(server_address, port)

func disconnect_from_server() -> void:
	server_connection.disconnect_from_server()

func get_selected_units() -> Array:
	return selection_manager.get_selected_units()

func get_game_state() -> Dictionary:
	return game_state

# Display unit class for client-side visual representation
class DisplayUnit extends Node3D:
	var unit_id: String
	var unit_type: String
	var team_id: int
	var health: float
	var max_health: float
	var current_state: int  # Using int instead of GameEnums.UnitState
	
	var mesh_instance: MeshInstance3D
	var health_bar: Node3D
	var selection_indicator: Node3D
	var is_selected: bool = false
	
	func _ready() -> void:
		# Create visual representation
		mesh_instance = MeshInstance3D.new()
		add_child(mesh_instance)
		
		# Create health bar
		health_bar = Node3D.new()
		add_child(health_bar)
		
		# Create selection indicator
		selection_indicator = Node3D.new()
		add_child(selection_indicator)
		selection_indicator.visible = false
	
	func setup_from_server_data(data: Dictionary) -> void:
		unit_id = data.get("id", "")
		unit_type = data.get("unit_type", "")
		team_id = data.get("team_id", 0)
		health = data.get("health", 100)
		max_health = data.get("max_health", 100)
		current_state = 0  # Default to idle
		
		# Set position
		var pos = data.get("position", [0, 0, 0])
		global_position = Vector3(pos[0], pos[1], pos[2])
		
		# Set rotation
		rotation.y = data.get("rotation", 0.0)
		
		# Setup visual representation based on unit type
		_setup_mesh_for_unit_type(unit_type)
		_update_health_bar()
		_update_selection_indicator()
	
	func update_from_server_data(data: Dictionary) -> void:
		# Update position with interpolation
		var new_pos = data.get("position", [0, 0, 0])
		var target_position = Vector3(new_pos[0], new_pos[1], new_pos[2])
		
		# Smooth movement interpolation
		var tween = create_tween()
		tween.tween_property(self, "global_position", target_position, 0.1)
		
		# Update rotation
		rotation.y = data.get("rotation", 0.0)
		
		# Update health
		health = data.get("health", health)
		_update_health_bar()
		
		# Update state
		current_state = 0  # Default state
		_update_visual_state()
	
	func _setup_mesh_for_unit_type(type: String) -> void:
		var mesh: Mesh
		match type:
			"scout":
				mesh = CapsuleMesh.new()
				mesh.height = 2.0
				mesh.top_radius = 0.4
				mesh.bottom_radius = 0.4
			"soldier":
				mesh = BoxMesh.new()
				mesh.size = Vector3(0.8, 2.0, 0.8)
			"tank":
				mesh = BoxMesh.new()
				mesh.size = Vector3(2.0, 1.5, 3.0)
			"medic":
				mesh = CylinderMesh.new()
				mesh.height = 2.0
				mesh.top_radius = 0.5
				mesh.bottom_radius = 0.5
			"engineer":
				mesh = BoxMesh.new()
				mesh.size = Vector3(1.0, 2.0, 1.0)
			_:
				mesh = CapsuleMesh.new()
		
		mesh_instance.mesh = mesh
		
		# Set team color
		var material = StandardMaterial3D.new()
		match team_id:
			1:
				material.albedo_color = Color.BLUE
			2:
				material.albedo_color = Color.RED
			_:
				material.albedo_color = Color.GRAY
		
		mesh_instance.material_override = material
	
	func _update_health_bar() -> void:
		# Update health bar visualization
		# TODO: Implement health bar rendering
		pass
	
	func _update_selection_indicator() -> void:
		# Update selection indicator
		if is_selected:
			selection_indicator.visible = true
		else:
			selection_indicator.visible = false
	
	func _update_visual_state() -> void:
		# Update visual state based on current_state
		match current_state:
			0:  # IDLE
				pass
			1:  # MOVING
				pass
			2:  # ATTACKING
				pass
			3:  # DEAD
				pass
	
	func select() -> void:
		is_selected = true
		_update_selection_indicator()
	
	func deselect() -> void:
		is_selected = false
		_update_selection_indicator()

class DisplayBuilding extends Node3D:
	var building_id: String
	var building_type: String
	var team_id: int
	var health: float
	var max_health: float
	
	var mesh_instance: MeshInstance3D
	var health_bar: Node3D
	
	func setup_from_server_data(data: Dictionary) -> void:
		building_id = data.get("id", "")
		building_type = data.get("building_type", "")
		team_id = data.get("team_id", 0)
		health = data.get("health", 100)
		max_health = data.get("max_health", 100)
		
		# Set position
		var pos = data.get("position", [0, 0, 0])
		global_position = Vector3(pos[0], pos[1], pos[2])
		
		# Setup visual representation
		_setup_mesh_for_building_type(building_type)
	
	func update_from_server_data(data: Dictionary) -> void:
		health = data.get("health", health)
		_update_health_bar()
	
	func _setup_mesh_for_building_type(type: String) -> void:
		mesh_instance = MeshInstance3D.new()
		add_child(mesh_instance)
		
		var mesh: Mesh
		match type:
			"power_spire":
				mesh = CylinderMesh.new()
				mesh.height = 4.0
				mesh.top_radius = 0.5
				mesh.bottom_radius = 1.0
			"defense_tower":
				mesh = BoxMesh.new()
				mesh.size = Vector3(2.0, 3.0, 2.0)
			"relay_pad":
				mesh = CylinderMesh.new()
				mesh.height = 0.5
				mesh.top_radius = 2.0
				mesh.bottom_radius = 2.0
			_:
				mesh = BoxMesh.new()
		
		mesh_instance.mesh = mesh
		
		# Set team color
		var material = StandardMaterial3D.new()
		match team_id:
			1:
				material.albedo_color = Color.BLUE
			2:
				material.albedo_color = Color.RED
			_:
				material.albedo_color = Color.GRAY
		
		mesh_instance.material_override = material
	
	func _update_health_bar() -> void:
		# Update health bar visualization
		pass

# Simple Set class for tracking IDs
class Set:
	var items: Dictionary = {}
	
	func add(item) -> void:
		items[item] = true
	
	func has(item) -> bool:
		return item in items
	
	func remove(item) -> void:
		items.erase(item)
	
	func clear() -> void:
		items.clear()



# Server connection class
class ServerConnection extends Node:
	signal game_state_received(state_data: Dictionary)
	signal connected_to_server()
	signal disconnected_from_server()
	
	var multiplayer_peer: ENetMultiplayerPeer
	var local_player_team: int = 0
	
	func connect_to_server(address: String, port: int) -> void:
		multiplayer_peer = ENetMultiplayerPeer.new()
		multiplayer_peer.create_client(address, port)
		multiplayer.multiplayer_peer = multiplayer_peer
		
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	func disconnect_from_server() -> void:
		if multiplayer_peer:
			multiplayer_peer.close()
			multiplayer_peer = null
		disconnected_from_server.emit()
	
	func send_player_input(input_data: Dictionary) -> void:
		rpc_id(1, "process_player_input", input_data)
	
	func send_ai_command(command: String, selected_units: Array) -> void:
		rpc_id(1, "process_ai_command", command, selected_units)
	
	func get_local_player_team() -> int:
		return local_player_team
	
	func _on_connected_to_server() -> void:
		connected_to_server.emit()
	
	func _on_connection_failed() -> void:
		disconnected_from_server.emit()
	
	func _on_server_disconnected() -> void:
		disconnected_from_server.emit()
	
	@rpc("authority", "call_local", "reliable")
	func _on_game_state_update(state_data: Dictionary) -> void:
		game_state_received.emit(state_data) 