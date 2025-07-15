# NetworkOptimizationSystem.gd
class_name NetworkOptimizationSystem
extends Node

# Network optimization settings
@export var enable_delta_compression: bool = true
@export var enable_prediction: bool = true
@export var enable_lag_compensation: bool = true
@export var enable_interpolation: bool = true
@export var enable_extrapolation: bool = true

# Timing settings
@export var network_tick_rate: int = 30  # Network updates per second
@export var client_tick_rate: int = 60   # Client updates per second
@export var max_ping_tolerance: float = 500.0  # Maximum ping in milliseconds
@export var interpolation_buffer_size: int = 3  # Number of frames to buffer

# Compression settings
@export var position_precision: float = 0.1      # Position quantization
@export var rotation_precision: float = 0.01     # Rotation quantization
@export var velocity_precision: float = 0.1      # Velocity quantization
@export var health_precision: float = 1.0        # Health quantization

# Performance settings
@export var max_updates_per_frame: int = 100     # Maximum network updates per frame
@export var priority_update_distance: float = 50.0  # Distance for priority updates
@export var culling_distance: float = 100.0     # Distance for update culling

# Network state
var network_time: float = 0.0
var last_network_update: float = 0.0
var network_tick_accumulator: float = 0.0
var client_tick_accumulator: float = 0.0
var network_dt: float = 1.0 / 30.0  # Network delta time
var client_dt: float = 1.0 / 60.0   # Client delta time

# Connection tracking
var clients: Dictionary = {}  # client_id -> ClientNetworkState
var server_state: ServerNetworkState = null

# Data structures
var entity_states: Dictionary = {}          # entity_id -> EntityNetworkState
var entity_snapshots: Dictionary = {}      # entity_id -> Array[EntitySnapshot]
var command_buffer: Array[NetworkCommand] = []
var pending_updates: Array[NetworkUpdate] = []

# Prediction and lag compensation
var prediction_buffer: Array[PredictionFrame] = []
var lag_compensation_buffer: Array[LagCompensationFrame] = []
var client_input_buffer: Array[ClientInput] = []

# Performance tracking
var network_stats: NetworkStats = NetworkStats.new()
var update_priority_system: UpdatePrioritySystem = UpdatePrioritySystem.new()

# Client network state
class ClientNetworkState:
	var client_id: int
	var ping: float = 0.0
	var last_ping_time: float = 0.0
	var packet_loss: float = 0.0
	var bandwidth_usage: float = 0.0
	var last_update_time: float = 0.0
	var update_frequency: float = 30.0
	var prediction_enabled: bool = true
	var interpolation_enabled: bool = true
	
	func _init(id: int):
		client_id = id
		last_ping_time = Time.get_ticks_msec() / 1000.0

# Server network state
class ServerNetworkState:
	var server_time: float = 0.0
	var tick_count: int = 0
	var client_count: int = 0
	var total_bandwidth: float = 0.0
	var entity_count: int = 0
	var update_rate: float = 30.0

# Entity network state
class EntityNetworkState:
	var entity_id: String
	var position: Vector3 = Vector3.ZERO
	var rotation: float = 0.0
	var velocity: Vector3 = Vector3.ZERO
	var health: float = 100.0
	var state: int = 0
	var last_update_time: float = 0.0
	var dirty_flags: int = 0
	var priority: float = 1.0
	var owner_client: int = -1
	
	func _init(id: String):
		entity_id = id
		last_update_time = Time.get_ticks_msec() / 1000.0

# Entity snapshot for interpolation
class EntitySnapshot:
	var timestamp: float
	var position: Vector3
	var rotation: float
	var velocity: Vector3
	var health: float
	var state: int
	
	func _init(time: float, pos: Vector3, rot: float, vel: Vector3, hp: float, st: int):
		timestamp = time
		position = pos
		rotation = rot
		velocity = vel
		health = hp
		state = st

# Network command
class NetworkCommand:
	var command_id: int
	var entity_id: String
	var command_type: String
	var parameters: Dictionary
	var timestamp: float
	var client_id: int
	
	func _init(id: int, entity: String, type: String, params: Dictionary, client: int):
		command_id = id
		entity_id = entity
		command_type = type
		parameters = params
		timestamp = Time.get_ticks_msec() / 1000.0
		client_id = client

# Network update
class NetworkUpdate:
	var update_id: int
	var entity_id: String
	var update_data: Dictionary
	var timestamp: float
	var priority: float
	var compressed_size: int
	
	func _init(id: int, entity: String, data: Dictionary, prio: float = 1.0):
		update_id = id
		entity_id = entity
		update_data = data
		timestamp = Time.get_ticks_msec() / 1000.0
		priority = prio

# Prediction frame
class PredictionFrame:
	var frame_number: int
	var timestamp: float
	var entity_states: Dictionary
	var client_inputs: Array[ClientInput]
	
	func _init(frame: int, time: float):
		frame_number = frame
		timestamp = time
		entity_states = {}
		client_inputs = []

# Lag compensation frame
class LagCompensationFrame:
	var timestamp: float
	var world_state: Dictionary
	var entity_positions: Dictionary
	
	func _init(time: float):
		timestamp = time
		world_state = {}
		entity_positions = {}

# Client input
class ClientInput:
	var input_id: int
	var client_id: int
	var timestamp: float
	var input_data: Dictionary
	var processed: bool = false
	
	func _init(id: int, client: int, data: Dictionary):
		input_id = id
		client_id = client
		timestamp = Time.get_ticks_msec() / 1000.0
		input_data = data

# Network statistics
class NetworkStats:
	var bytes_sent: int = 0
	var bytes_received: int = 0
	var packets_sent: int = 0
	var packets_received: int = 0
	var packets_lost: int = 0
	var average_ping: float = 0.0
	var bandwidth_usage: float = 0.0
	var compression_ratio: float = 0.0
	var update_frequency: float = 0.0
	var entity_updates_sent: int = 0
	var command_updates_sent: int = 0
	
	func reset():
		bytes_sent = 0
		bytes_received = 0
		packets_sent = 0
		packets_received = 0
		packets_lost = 0
		entity_updates_sent = 0
		command_updates_sent = 0

# Update priority system
class UpdatePrioritySystem:
	var priority_weights: Dictionary = {
		"distance": 1.0,
		"velocity": 0.5,
		"health_change": 1.5,
		"player_owned": 2.0,
		"in_combat": 1.8,
		"recently_spawned": 1.2
	}
	
	func calculate_priority(entity_state: EntityNetworkState, viewer_position: Vector3) -> float:
		var priority = 1.0
		
		# Distance-based priority
		var distance = entity_state.position.distance_to(viewer_position)
		if distance < priority_update_distance:
			priority *= priority_weights.distance
		else:
			priority *= (priority_update_distance / distance)
		
		# Velocity-based priority
		if entity_state.velocity.length() > 1.0:
			priority *= priority_weights.velocity
		
		# Health change priority
		if entity_state.dirty_flags & 0x04:  # Health dirty flag
			priority *= priority_weights.health_change
		
		# Player-owned entities
		if entity_state.owner_client >= 0:
			priority *= priority_weights.player_owned
		
		return priority

# Signals
signal network_stats_updated(stats: NetworkStats)
signal client_connected(client_id: int)
signal client_disconnected(client_id: int)
signal entity_updated(entity_id: String, data: Dictionary)
signal command_received(command: NetworkCommand)
signal lag_compensation_applied(compensation_data: Dictionary)

func _ready():
	# Initialize network system
	_initialize_network_system()
	
	# Start network processing
	set_process(true)
	
	# Connect to multiplayer signals
	_connect_multiplayer_signals()
	
	print("NetworkOptimizationSystem: Network optimization system initialized")

func _initialize_network_system():
	"""Initialize network optimization system"""
	# Calculate delta times
	network_dt = 1.0 / network_tick_rate
	client_dt = 1.0 / client_tick_rate
	
	# Initialize server state
	server_state = ServerNetworkState.new()
	
	# Initialize update priority system
	update_priority_system = UpdatePrioritySystem.new()
	
	# Reset network stats
	network_stats.reset()

func _connect_multiplayer_signals():
	"""Connect to multiplayer system signals"""
	if multiplayer:
		multiplayer.peer_connected.connect(_on_client_connected)
		multiplayer.peer_disconnected.connect(_on_client_disconnected)

func _process(delta: float):
	"""Process network optimization"""
	# Update network time
	network_time += delta
	
	# Accumulate tick time
	network_tick_accumulator += delta
	client_tick_accumulator += delta
	
	# Process network ticks
	while network_tick_accumulator >= network_dt:
		_process_network_tick()
		network_tick_accumulator -= network_dt
	
	# Process client ticks
	while client_tick_accumulator >= client_dt:
		_process_client_tick()
		client_tick_accumulator -= client_dt
	
	# Update network statistics
	_update_network_stats()

func _process_network_tick():
	"""Process network tick (server-side)"""
	if not multiplayer or not multiplayer.is_server():
		return
	
	# Process pending commands
	_process_pending_commands()
	
	# Update entity states
	_update_entity_states()
	
	# Send network updates
	_send_network_updates()
	
	# Apply lag compensation
	if enable_lag_compensation:
		_apply_lag_compensation()
	
	# Update server state
	server_state.tick_count += 1
	server_state.server_time = network_time

func _process_client_tick():
	"""Process client tick (client-side)"""
	if not multiplayer or multiplayer.is_server():
		return
	
	# Process client prediction
	if enable_prediction:
		_process_client_prediction()
	
	# Process interpolation
	if enable_interpolation:
		_process_interpolation()
	
	# Send client input
	_send_client_input()

func _process_pending_commands():
	"""Process pending network commands"""
	var processed_commands = []
	
	for command in command_buffer:
		if _process_command(command):
			processed_commands.append(command)
	
	# Remove processed commands
	for command in processed_commands:
		command_buffer.erase(command)

func _process_command(command: NetworkCommand) -> bool:
	"""Process individual network command"""
	var entity = _get_entity_by_id(command.entity_id)
	if not entity:
		return false
	
	match command.command_type:
		"move":
			_process_move_command(entity, command)
		"attack":
			_process_attack_command(entity, command)
		"ability":
			_process_ability_command(entity, command)
		"formation":
			_process_formation_command(entity, command)
		_:
			print("Unknown command type: %s" % command.command_type)
			return false
	
	return true

func _process_move_command(entity: Node, command: NetworkCommand):
	"""Process move command"""
	var target_pos = Vector3(
		command.parameters.get("x", 0.0),
		command.parameters.get("y", 0.0),
		command.parameters.get("z", 0.0)
	)
	
	if entity.has_method("move_to"):
		entity.move_to(target_pos)
	
	# Update entity state
	_update_entity_network_state(entity, {"target_position": target_pos})

func _process_attack_command(entity: Node, command: NetworkCommand):
	"""Process attack command"""
	var target_id = command.parameters.get("target_id", "")
	var target_entity = _get_entity_by_id(target_id)
	
	if target_entity and entity.has_method("attack_target"):
		entity.attack_target(target_entity)
	
	# Update entity state
	_update_entity_network_state(entity, {"attacking": target_id})

func _process_ability_command(entity: Node, command: NetworkCommand):
	"""Process ability command"""
	var ability_name = command.parameters.get("ability", "")
	var ability_params = command.parameters.get("params", {})
	
	if entity.has_method("use_ability"):
		entity.use_ability(ability_name, ability_params)
	
	# Update entity state
	_update_entity_network_state(entity, {"ability_used": ability_name})

func _process_formation_command(entity: Node, command: NetworkCommand):
	"""Process formation command"""
	var formation_type = command.parameters.get("formation_type", "")
	var formation_params = command.parameters.get("params", {})
	
	# This would integrate with the formation system
	if entity.has_method("join_formation"):
		entity.join_formation(formation_type, formation_params)

func _update_entity_states():
	"""Update entity states for network synchronization"""
	var entities = get_tree().get_nodes_in_group("networked_entities")
	
	for entity in entities:
		if entity and is_instance_valid(entity):
			_update_entity_network_state(entity)

func _update_entity_network_state(entity: Node, additional_data: Dictionary = {}):
	"""Update network state for entity"""
	var entity_id = entity.get("unit_id", entity.name)
	
	if entity_id not in entity_states:
		entity_states[entity_id] = EntityNetworkState.new(entity_id)
	
	var state = entity_states[entity_id]
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Update position
	var new_position = entity.global_position
	if new_position.distance_to(state.position) > position_precision:
		state.position = new_position
		state.dirty_flags |= 0x01  # Position dirty
	
	# Update rotation
	var new_rotation = entity.rotation.y
	if abs(new_rotation - state.rotation) > rotation_precision:
		state.rotation = new_rotation
		state.dirty_flags |= 0x02  # Rotation dirty
	
	# Update health
	if entity.has_method("get_health_percentage"):
		var new_health = entity.get_health_percentage() * 100.0
		if abs(new_health - state.health) > health_precision:
			state.health = new_health
			state.dirty_flags |= 0x04  # Health dirty
	
	# Update velocity
	if entity.has_method("get_velocity"):
		var new_velocity = entity.get_velocity()
		if new_velocity.distance_to(state.velocity) > velocity_precision:
			state.velocity = new_velocity
			state.dirty_flags |= 0x08  # Velocity dirty
	
	# Add additional data
	for key in additional_data:
		state.dirty_flags |= 0x10  # Additional data dirty
	
	state.last_update_time = current_time

func _send_network_updates():
	"""Send network updates to clients"""
	var updates_sent = 0
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Get all clients
	var client_ids = multiplayer.get_peers()
	
	for client_id in client_ids:
		if client_id not in clients:
			clients[client_id] = ClientNetworkState.new(client_id)
		
		var client_state = clients[client_id]
		var viewer_position = _get_client_position(client_id)
		
		# Collect updates for this client
		var updates = _collect_updates_for_client(client_id, viewer_position)
		
		# Send updates
		if updates.size() > 0:
			_send_updates_to_client(client_id, updates)
			updates_sent += updates.size()
	
	network_stats.entity_updates_sent += updates_sent

func _collect_updates_for_client(client_id: int, viewer_position: Vector3) -> Array:
	"""Collect network updates for specific client"""
	var updates = []
	var current_time = Time.get_ticks_msec() / 1000.0
	
	for entity_id in entity_states:
		var state = entity_states[entity_id]
		
		# Skip if no changes
		if state.dirty_flags == 0:
			continue
		
		# Check distance culling
		var distance = state.position.distance_to(viewer_position)
		if distance > culling_distance:
			continue
		
		# Calculate priority
		var priority = update_priority_system.calculate_priority(state, viewer_position)
		
		# Create update
		var update_data = _create_update_data(state)
		var update = NetworkUpdate.new(
			updates.size(),
			entity_id,
			update_data,
			priority
		)
		
		updates.append(update)
	
	# Sort by priority
	updates.sort_custom(func(a, b): return a.priority > b.priority)
	
	# Limit updates per frame
	if updates.size() > max_updates_per_frame:
		updates = updates.slice(0, max_updates_per_frame)
	
	return updates

func _create_update_data(state: EntityNetworkState) -> Dictionary:
	"""Create update data for entity state"""
	var data = {}
	
	# Add dirty data only
	if state.dirty_flags & 0x01:  # Position
		data["position"] = [state.position.x, state.position.y, state.position.z]
	
	if state.dirty_flags & 0x02:  # Rotation
		data["rotation"] = state.rotation
	
	if state.dirty_flags & 0x04:  # Health
		data["health"] = state.health
	
	if state.dirty_flags & 0x08:  # Velocity
		data["velocity"] = [state.velocity.x, state.velocity.y, state.velocity.z]
	
	# Add timestamp
	data["timestamp"] = state.last_update_time
	
	return data

func _send_updates_to_client(client_id: int, updates: Array):
	"""Send updates to specific client"""
	var compressed_data = _compress_updates(updates) if enable_delta_compression else updates
	
	# Send via RPC
	_send_entity_updates.rpc_id(client_id, compressed_data)
	
	# Update stats
	network_stats.packets_sent += 1
	network_stats.bytes_sent += _calculate_data_size(compressed_data)

func _compress_updates(updates: Array) -> Dictionary:
	"""Compress network updates using delta compression"""
	var compressed = {
		"frame": server_state.tick_count,
		"timestamp": network_time,
		"entities": {}
	}
	
	for update in updates:
		var entity_id = update.entity_id
		var data = update.update_data
		
		# Apply quantization
		if "position" in data:
			var pos = data["position"]
			data["position"] = [
				_quantize(pos[0], position_precision),
				_quantize(pos[1], position_precision),
				_quantize(pos[2], position_precision)
			]
		
		if "rotation" in data:
			data["rotation"] = _quantize(data["rotation"], rotation_precision)
		
		if "health" in data:
			data["health"] = _quantize(data["health"], health_precision)
		
		compressed.entities[entity_id] = data
	
	return compressed

func _quantize(value: float, precision: float) -> float:
	"""Quantize value to reduce precision"""
	return round(value / precision) * precision

func _calculate_data_size(data) -> int:
	"""Calculate size of data structure"""
	var json_string = JSON.stringify(data)
	return json_string.length()

func _process_client_prediction():
	"""Process client-side prediction"""
	var current_frame = client_tick_accumulator / client_dt
	var prediction_frame = PredictionFrame.new(current_frame, network_time)
	
	# Store current state
	var entities = get_tree().get_nodes_in_group("networked_entities")
	for entity in entities:
		if entity and is_instance_valid(entity):
			var entity_id = entity.get("unit_id", entity.name)
			prediction_frame.entity_states[entity_id] = {
				"position": entity.global_position,
				"rotation": entity.rotation.y,
				"velocity": entity.get_velocity() if entity.has_method("get_velocity") else Vector3.ZERO
			}
	
	# Add to prediction buffer
	prediction_buffer.append(prediction_frame)
	
	# Limit buffer size
	if prediction_buffer.size() > 60:  # Keep ~1 second of frames
		prediction_buffer.pop_front()

func _process_interpolation():
	"""Process client-side interpolation"""
	var current_time = Time.get_ticks_msec() / 1000.0
	var interpolation_time = current_time - (network_dt * interpolation_buffer_size)
	
	var entities = get_tree().get_nodes_in_group("networked_entities")
	for entity in entities:
		if entity and is_instance_valid(entity):
			var entity_id = entity.get("unit_id", entity.name)
			_interpolate_entity(entity, entity_id, interpolation_time)

func _interpolate_entity(entity: Node, entity_id: String, interpolation_time: float):
	"""Interpolate entity to specific time"""
	if entity_id not in entity_snapshots:
		return
	
	var snapshots = entity_snapshots[entity_id]
	if snapshots.size() < 2:
		return
	
	# Find snapshots to interpolate between
	var from_snapshot = null
	var to_snapshot = null
	
	for i in range(snapshots.size() - 1):
		if snapshots[i].timestamp <= interpolation_time and snapshots[i + 1].timestamp >= interpolation_time:
			from_snapshot = snapshots[i]
			to_snapshot = snapshots[i + 1]
			break
	
	if not from_snapshot or not to_snapshot:
		return
	
	# Calculate interpolation factor
	var time_diff = to_snapshot.timestamp - from_snapshot.timestamp
	var t = (interpolation_time - from_snapshot.timestamp) / time_diff
	t = clamp(t, 0.0, 1.0)
	
	# Interpolate position
	var interpolated_position = from_snapshot.position.lerp(to_snapshot.position, t)
	entity.global_position = interpolated_position
	
	# Interpolate rotation
	var interpolated_rotation = lerp_angle(from_snapshot.rotation, to_snapshot.rotation, t)
	entity.rotation.y = interpolated_rotation

func _send_client_input():
	"""Send client input to server"""
	if not multiplayer or multiplayer.is_server():
		return
	
	# Collect input data
	var input_data = {
		"timestamp": network_time,
		"movement": Vector3.ZERO,
		"commands": []
	}
	
	# Add movement input
	if Input.is_action_pressed("move_forward"):
		input_data.movement.z -= 1
	if Input.is_action_pressed("move_backward"):
		input_data.movement.z += 1
	if Input.is_action_pressed("move_left"):
		input_data.movement.x -= 1
	if Input.is_action_pressed("move_right"):
		input_data.movement.x += 1
	
	# Send input
	_receive_client_input.rpc_id(1, input_data)

func _apply_lag_compensation():
	"""Apply lag compensation for hit detection"""
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Store current world state
	var compensation_frame = LagCompensationFrame.new(current_time)
	
	var entities = get_tree().get_nodes_in_group("networked_entities")
	for entity in entities:
		if entity and is_instance_valid(entity):
			var entity_id = entity.get("unit_id", entity.name)
			compensation_frame.entity_positions[entity_id] = entity.global_position
	
	# Add to buffer
	lag_compensation_buffer.append(compensation_frame)
	
	# Limit buffer size
	if lag_compensation_buffer.size() > 100:  # Keep ~3 seconds at 30fps
		lag_compensation_buffer.pop_front()

func _get_entity_by_id(entity_id: String) -> Node:
	"""Get entity by ID"""
	var entities = get_tree().get_nodes_in_group("networked_entities")
	for entity in entities:
		if entity and is_instance_valid(entity):
			if entity.get("unit_id", entity.name) == entity_id:
				return entity
	return null

func _get_client_position(client_id: int) -> Vector3:
	"""Get client camera position"""
	# This would typically get the player's camera position
	# For now, return a default position
	return Vector3.ZERO

func _update_network_stats():
	"""Update network statistics"""
	# Calculate compression ratio
	if network_stats.bytes_sent > 0:
		network_stats.compression_ratio = 1.0 - (network_stats.bytes_sent / float(network_stats.bytes_sent + network_stats.bytes_received))
	
	# Calculate average ping
	if clients.size() > 0:
		var total_ping = 0.0
		for client_id in clients:
			total_ping += clients[client_id].ping
		network_stats.average_ping = total_ping / clients.size()
	
	# Update frequency
	network_stats.update_frequency = 1.0 / network_dt
	
	# Emit stats update
	network_stats_updated.emit(network_stats)

# RPC methods
@rpc("any_peer", "call_remote", "reliable")
func _receive_client_input(input_data: Dictionary):
	"""Receive client input on server"""
	var client_id = multiplayer.get_remote_sender_id()
	var input = ClientInput.new(
		client_input_buffer.size(),
		client_id,
		input_data
	)
	
	client_input_buffer.append(input)

@rpc("authority", "call_remote", "unreliable")
func _send_entity_updates(update_data: Dictionary):
	"""Send entity updates to client"""
	# Process received updates
	_process_received_updates(update_data)

func _process_received_updates(update_data: Dictionary):
	"""Process received network updates"""
	var frame = update_data.get("frame", 0)
	var timestamp = update_data.get("timestamp", 0.0)
	var entities = update_data.get("entities", {})
	
	for entity_id in entities:
		var entity_data = entities[entity_id]
		var entity = _get_entity_by_id(entity_id)
		
		if entity:
			_apply_entity_update(entity, entity_data, timestamp)
			
			# Store snapshot for interpolation
			if entity_id not in entity_snapshots:
				entity_snapshots[entity_id] = []
			
			var snapshot = EntitySnapshot.new(
				timestamp,
				Vector3(entity_data.get("position", [0, 0, 0])[0], entity_data.get("position", [0, 0, 0])[1], entity_data.get("position", [0, 0, 0])[2]),
				entity_data.get("rotation", 0.0),
				Vector3(entity_data.get("velocity", [0, 0, 0])[0], entity_data.get("velocity", [0, 0, 0])[1], entity_data.get("velocity", [0, 0, 0])[2]),
				entity_data.get("health", 100.0),
				entity_data.get("state", 0)
			)
			
			entity_snapshots[entity_id].append(snapshot)
			
			# Limit snapshot buffer
			if entity_snapshots[entity_id].size() > 10:
				entity_snapshots[entity_id].pop_front()

func _apply_entity_update(entity: Node, entity_data: Dictionary, timestamp: float):
	"""Apply entity update from network"""
	# Update position
	if "position" in entity_data:
		var pos = entity_data["position"]
		entity.global_position = Vector3(pos[0], pos[1], pos[2])
	
	# Update rotation
	if "rotation" in entity_data:
		entity.rotation.y = entity_data["rotation"]
	
	# Update health
	if "health" in entity_data and entity.has_method("set_health"):
		entity.set_health(entity_data["health"])
	
	# Emit update signal
	entity_updated.emit(entity.get("unit_id", entity.name), entity_data)

func _on_client_connected(client_id: int):
	"""Handle client connection"""
	clients[client_id] = ClientNetworkState.new(client_id)
	server_state.client_count += 1
	
	client_connected.emit(client_id)
	print("NetworkOptimizationSystem: Client %d connected" % client_id)

func _on_client_disconnected(client_id: int):
	"""Handle client disconnection"""
	if client_id in clients:
		clients.erase(client_id)
		server_state.client_count -= 1
	
	client_disconnected.emit(client_id)
	print("NetworkOptimizationSystem: Client %d disconnected" % client_id)

# Public API
func send_command(entity_id: String, command_type: String, parameters: Dictionary):
	"""Send network command"""
	var command = NetworkCommand.new(
		command_buffer.size(),
		entity_id,
		command_type,
		parameters,
		multiplayer.get_unique_id()
	)
	
	command_buffer.append(command)
	network_stats.command_updates_sent += 1

func register_networked_entity(entity: Node):
	"""Register entity for network synchronization"""
	entity.add_to_group("networked_entities")
	
	var entity_id = entity.get("unit_id", entity.name)
	if entity_id not in entity_states:
		entity_states[entity_id] = EntityNetworkState.new(entity_id)

func unregister_networked_entity(entity: Node):
	"""Unregister entity from network synchronization"""
	entity.remove_from_group("networked_entities")
	
	var entity_id = entity.get("unit_id", entity.name)
	if entity_id in entity_states:
		entity_states.erase(entity_id)
	
	if entity_id in entity_snapshots:
		entity_snapshots.erase(entity_id)

func get_network_statistics() -> NetworkStats:
	"""Get current network statistics"""
	return network_stats

func set_update_rate(rate: int):
	"""Set network update rate"""
	network_tick_rate = rate
	network_dt = 1.0 / rate

func get_client_ping(client_id: int) -> float:
	"""Get client ping"""
	if client_id in clients:
		return clients[client_id].ping
	return 0.0

func is_prediction_enabled() -> bool:
	"""Check if prediction is enabled"""
	return enable_prediction

func is_lag_compensation_enabled() -> bool:
	"""Check if lag compensation is enabled"""
	return enable_lag_compensation

func get_compression_ratio() -> float:
	"""Get current compression ratio"""
	return network_stats.compression_ratio 