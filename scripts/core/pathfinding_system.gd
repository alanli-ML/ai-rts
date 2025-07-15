# PathfindingSystem.gd
class_name PathfindingSystem
extends Node

# Pathfinding settings
var navigation_map: RID
var path_update_interval: float = 0.1
var path_optimization_enabled: bool = true
var dynamic_obstacle_avoidance: bool = true
var formation_aware_pathfinding: bool = true

# Unit pathfinding data
var unit_agents: Dictionary = {}  # unit_id -> NavigationAgent3D
var unit_paths: Dictionary = {}   # unit_id -> Array[Vector3]
var unit_path_progress: Dictionary = {}  # unit_id -> int (current path index)
var unit_destinations: Dictionary = {}  # unit_id -> Vector3
var unit_movement_states: Dictionary = {}  # unit_id -> MovementState

# Formation pathfinding
var formation_paths: Dictionary = {}  # formation_id -> Array[Vector3]
var formation_system: FormationSystem

# Collision avoidance
var avoidance_radius: float = 2.0
var avoidance_strength: float = 1.5
var neighbor_search_radius: float = 5.0
var max_avoidance_force: float = 10.0

# Path optimization
var path_smoothing_enabled: bool = true
var path_simplification_threshold: float = 0.5
var lookahead_distance: float = 3.0

# Performance settings
var max_path_requests_per_frame: int = 10
var path_cache_duration: float = 2.0
var path_cache: Dictionary = {}  # position_key -> cached_path_data

# System state
var is_ready: bool = false

# Movement states
enum MovementState {
	IDLE,
	MOVING,
	FOLLOWING_PATH,
	AVOIDING_OBSTACLE,
	FORMATION_MOVING,
	STUCK
}

# Pathfinding request
class PathRequest:
	var unit_id: String
	var start_position: Vector3
	var target_position: Vector3
	var formation_id: String = ""
	var priority: int = 0
	var callback: Callable
	var timestamp: float
	
	func _init(unit: String, start: Vector3, target: Vector3, cb: Callable):
		unit_id = unit
		start_position = start
		target_position = target
		callback = cb
		timestamp = Time.get_ticks_msec() / 1000.0

# Path cache entry
class PathCacheEntry:
	var path: Array[Vector3]
	var timestamp: float
	var usage_count: int = 0
	
	func _init(p: Array[Vector3]):
		path = p
		timestamp = Time.get_ticks_msec() / 1000.0

# Request queue
var path_requests: Array[PathRequest] = []
var last_update_time: float = 0.0

# Signals
signal path_found(unit_id: String, path: Array[Vector3])
signal path_failed(unit_id: String, reason: String)
signal unit_reached_destination(unit_id: String)
signal unit_stuck(unit_id: String, position: Vector3)
signal pathfinding_performance_update(stats: Dictionary)
signal pathfinding_system_ready()

func _ready() -> void:
	print("PathfindingSystem: Initializing pathfinding system...")
	
	# Create navigation map using NavigationServer3D singleton
	navigation_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(navigation_map, true)
	
	# Set up basic navigation configuration
	NavigationServer3D.map_set_cell_size(navigation_map, 0.5)
	NavigationServer3D.map_set_cell_height(navigation_map, 0.2)
	NavigationServer3D.map_set_edge_connection_margin(navigation_map, 0.2)
	
	# Find formation system
	formation_system = _find_formation_system()
	
	# Set up processing
	set_process(true)
	
	# Add to pathfinding systems group
	add_to_group("pathfinding_systems")
	
	print("PathfindingSystem: Navigation map created")
	
	is_ready = true
	pathfinding_system_ready.emit()

func _find_formation_system() -> FormationSystem:
	"""Find formation system in scene"""
	var formation_systems = get_tree().get_nodes_in_group("formation_systems")
	if formation_systems.size() > 0:
		return formation_systems[0]
	return null

func _process(delta: float) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Process path requests
	if current_time - last_update_time >= path_update_interval:
		_process_path_requests()
		_update_unit_movement(delta)
		_clean_path_cache()
		last_update_time = current_time

func _process_path_requests() -> void:
	"""Process queued path requests"""
	var processed = 0
	var requests_to_remove = []
	
	for i in range(path_requests.size()):
		if processed >= max_path_requests_per_frame:
			break
		
		var request = path_requests[i]
		_process_single_request(request)
		requests_to_remove.append(i)
		processed += 1
	
	# Remove processed requests (in reverse order)
	for i in range(requests_to_remove.size() - 1, -1, -1):
		path_requests.remove_at(requests_to_remove[i])

func _process_single_request(request: PathRequest) -> void:
	"""Process single pathfinding request"""
	var path = _calculate_path(request.start_position, request.target_position, request.unit_id)
	
	if path.size() > 0:
		# Store path data
		unit_paths[request.unit_id] = path
		unit_path_progress[request.unit_id] = 0
		unit_destinations[request.unit_id] = request.target_position
		unit_movement_states[request.unit_id] = MovementState.FOLLOWING_PATH
		
		# Cache path
		_cache_path(request.start_position, request.target_position, path)
		
		# Callback
		if request.callback.is_valid():
			request.callback.call(path)
		
		path_found.emit(request.unit_id, path)
	else:
		unit_movement_states[request.unit_id] = MovementState.STUCK
		path_failed.emit(request.unit_id, "No path found")

func _calculate_path(start: Vector3, target: Vector3, unit_id: String) -> Array[Vector3]:
	"""Calculate path between two points"""
	# Check cache first
	var cached_path = _get_cached_path(start, target)
	if cached_path.size() > 0:
		return cached_path
	
	# Use NavigationServer3D to find path
	var path: Array[Vector3] = []
	
	if navigation_map.is_valid():
		var nav_path = NavigationServer3D.map_get_path(
			navigation_map,
			start,
			target,
			true,  # optimize
			0      # navigation_layers
		)
		
		path = nav_path
	
	# Apply path optimization
	if path_optimization_enabled and path.size() > 2:
		path = _optimize_path(path, unit_id)
	
	return path

func _optimize_path(path: Array[Vector3], unit_id: String) -> Array[Vector3]:
	"""Optimize path for smoother movement"""
	var optimized_path: Array[Vector3] = []
	
	if path.size() <= 2:
		return path
	
	# Path simplification
	if path_simplification_threshold > 0:
		optimized_path = _simplify_path(path)
	else:
		optimized_path = path
	
	# Path smoothing
	if path_smoothing_enabled:
		optimized_path = _smooth_path(optimized_path)
	
	# Formation-aware adjustments
	if formation_aware_pathfinding and formation_system:
		optimized_path = _adjust_path_for_formation(optimized_path, unit_id)
	
	return optimized_path

func _simplify_path(path: Array[Vector3]) -> Array[Vector3]:
	"""Simplify path by removing unnecessary waypoints"""
	if path.size() <= 2:
		return path
	
	var simplified: Array[Vector3] = []
	simplified.append(path[0])
	
	for i in range(1, path.size() - 1):
		var prev = path[i - 1]
		var current = path[i]
		var next = path[i + 1]
		
		# Check if current point is necessary
		var direction1 = (current - prev).normalized()
		var direction2 = (next - current).normalized()
		
		if direction1.angle_to(direction2) > path_simplification_threshold:
			simplified.append(current)
	
	simplified.append(path[-1])
	return simplified

func _smooth_path(path: Array[Vector3]) -> Array[Vector3]:
	"""Apply path smoothing for natural movement"""
	if path.size() <= 2:
		return path
	
	var smoothed: Array[Vector3] = []
	smoothed.append(path[0])
	
	for i in range(1, path.size() - 1):
		var prev = path[i - 1]
		var current = path[i]
		var next = path[i + 1]
		
		# Apply smoothing
		var smoothed_point = (prev + current * 2.0 + next) / 4.0
		smoothed.append(smoothed_point)
	
	smoothed.append(path[-1])
	return smoothed

func _adjust_path_for_formation(path: Array[Vector3], unit_id: String) -> Array[Vector3]:
	"""Adjust path for formation movement"""
	if not formation_system:
		return path
	
	var unit = _get_unit_by_id(unit_id)
	if not unit:
		return path
	
	var formation = formation_system.get_unit_formation(unit)
	if not formation:
		return path
	
	# Adjust path based on formation position
	var adjusted_path: Array[Vector3] = []
	var formation_offset = _calculate_formation_offset(unit, formation)
	
	for point in path:
		adjusted_path.append(point + formation_offset)
	
	return adjusted_path

func _calculate_formation_offset(unit: Unit, formation) -> Vector3:
	"""Calculate formation offset for unit"""
	if not formation or not formation.units:
		return Vector3.ZERO
	
	var unit_index = formation.units.find(unit)
	if unit_index == -1:
		return Vector3.ZERO
	
	# Get formation position for this unit
	if unit_index < formation.positions.size():
		var leader_pos = formation.leader.global_position
		var unit_target_pos = formation.positions[unit_index]
		return unit_target_pos - leader_pos
	
	return Vector3.ZERO

func _update_unit_movement(delta: float) -> void:
	"""Update unit movement along paths"""
	for unit_id in unit_paths:
		_update_unit_path_movement(unit_id, delta)

func _update_unit_path_movement(unit_id: String, delta: float) -> void:
	"""Update individual unit path movement"""
	if not unit_id in unit_paths:
		return
	
	var unit = _get_unit_by_id(unit_id)
	if not unit:
		return
	
	var path = unit_paths[unit_id]
	var progress = unit_path_progress.get(unit_id, 0)
	var movement_state = unit_movement_states.get(unit_id, MovementState.IDLE)
	
	if progress >= path.size():
		# Reached destination
		_complete_unit_movement(unit_id)
		return
	
	# Calculate movement with collision avoidance
	var current_pos = unit.global_position
	var target_pos = path[progress]
	var distance_to_target = current_pos.distance_to(target_pos)
	
	# Check if reached current waypoint
	if distance_to_target < 1.0:
		progress += 1
		unit_path_progress[unit_id] = progress
		
		if progress >= path.size():
			_complete_unit_movement(unit_id)
			return
		
		target_pos = path[progress]
	
	# Apply collision avoidance
	var movement_vector = (target_pos - current_pos).normalized()
	
	if dynamic_obstacle_avoidance:
		var avoidance_vector = _calculate_avoidance_vector(unit, current_pos)
		movement_vector = (movement_vector + avoidance_vector).normalized()
	
	# Apply movement
	var movement_speed = unit.movement_speed if unit.has_method("get") else 8.0
	var movement_distance = movement_speed * delta
	var new_position = current_pos + movement_vector * movement_distance
	
	# Update unit position
	if unit.has_method("move_to"):
		unit.move_to(new_position)
	else:
		unit.global_position = new_position

func _calculate_avoidance_vector(unit: Unit, current_pos: Vector3) -> Vector3:
	"""Calculate collision avoidance vector"""
	var avoidance_vector = Vector3.ZERO
	var nearby_units = _get_nearby_units(unit, current_pos, neighbor_search_radius)
	
	for other_unit in nearby_units:
		if other_unit == unit:
			continue
		
		var distance = current_pos.distance_to(other_unit.global_position)
		if distance < avoidance_radius:
			var repulsion_direction = (current_pos - other_unit.global_position).normalized()
			var repulsion_strength = avoidance_strength * (avoidance_radius - distance) / avoidance_radius
			avoidance_vector += repulsion_direction * repulsion_strength
	
	# Limit avoidance force
	if avoidance_vector.length() > max_avoidance_force:
		avoidance_vector = avoidance_vector.normalized() * max_avoidance_force
	
	return avoidance_vector

func _get_nearby_units(unit: Unit, position: Vector3, radius: float) -> Array[Unit]:
	"""Get nearby units within radius"""
	var nearby_units: Array[Unit] = []
	var all_units = get_tree().get_nodes_in_group("units")
	
	for other_unit in all_units:
		if other_unit is Unit:
			var distance = position.distance_to(other_unit.global_position)
			if distance <= radius:
				nearby_units.append(other_unit)
	
	return nearby_units

func _complete_unit_movement(unit_id: String) -> void:
	"""Complete unit movement"""
	unit_movement_states[unit_id] = MovementState.IDLE
	unit_reached_destination.emit(unit_id)
	
	# Clean up path data
	unit_paths.erase(unit_id)
	unit_path_progress.erase(unit_id)
	unit_destinations.erase(unit_id)

func _get_unit_by_id(unit_id: String) -> Unit:
	"""Get unit by ID"""
	var all_units = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if unit is Unit and unit.unit_id == unit_id:
			return unit
	return null

func _cache_path(start: Vector3, target: Vector3, path: Array[Vector3]) -> void:
	"""Cache calculated path"""
	var cache_key = _get_cache_key(start, target)
	path_cache[cache_key] = PathCacheEntry.new(path)

func _get_cached_path(start: Vector3, target: Vector3) -> Array[Vector3]:
	"""Get cached path if available"""
	var cache_key = _get_cache_key(start, target)
	if cache_key in path_cache:
		var entry = path_cache[cache_key]
		var current_time = Time.get_ticks_msec() / 1000.0
		
		if current_time - entry.timestamp < path_cache_duration:
			entry.usage_count += 1
			return entry.path
		else:
			path_cache.erase(cache_key)
	
	return []

func _get_cache_key(start: Vector3, target: Vector3) -> String:
	"""Generate cache key for path"""
	return "%d_%d_%d_%d_%d_%d" % [
		int(start.x), int(start.y), int(start.z),
		int(target.x), int(target.y), int(target.z)
	]

func _clean_path_cache() -> void:
	"""Clean expired cache entries"""
	var current_time = Time.get_ticks_msec() / 1000.0
	var keys_to_remove = []
	
	for key in path_cache:
		var entry = path_cache[key]
		if current_time - entry.timestamp > path_cache_duration:
			keys_to_remove.append(key)
	
	for key in keys_to_remove:
		path_cache.erase(key)

# Public API
func request_path(unit_id: String, start: Vector3, target: Vector3, callback: Callable = Callable()) -> void:
	"""Request path calculation for unit"""
	var request = PathRequest.new(unit_id, start, target, callback)
	path_requests.append(request)

func request_formation_path(formation_id: String, target: Vector3) -> void:
	"""Request path for entire formation"""
	if not formation_system:
		return
	
	var formation = formation_system.get_formation(formation_id)
	if not formation:
		return
	
	# Calculate path for formation leader
	var leader = formation.leader
	if leader:
		request_path(leader.unit_id, leader.global_position, target)
		formation_paths[formation_id] = []

func stop_unit_movement(unit_id: String) -> void:
	"""Stop unit movement"""
	unit_movement_states[unit_id] = MovementState.IDLE
	unit_paths.erase(unit_id)
	unit_path_progress.erase(unit_id)
	unit_destinations.erase(unit_id)

func get_unit_path(unit_id: String) -> Array[Vector3]:
	"""Get current path for unit"""
	return unit_paths.get(unit_id, [])

func get_unit_movement_state(unit_id: String) -> MovementState:
	"""Get unit movement state"""
	return unit_movement_states.get(unit_id, MovementState.IDLE)

func is_unit_moving(unit_id: String) -> bool:
	"""Check if unit is moving"""
	var state = get_unit_movement_state(unit_id)
	return state in [MovementState.MOVING, MovementState.FOLLOWING_PATH, MovementState.FORMATION_MOVING]

func get_unit_destination(unit_id: String) -> Vector3:
	"""Get unit destination"""
	return unit_destinations.get(unit_id, Vector3.ZERO)

func set_avoidance_settings(radius: float, strength: float, search_radius: float) -> void:
	"""Set collision avoidance settings"""
	avoidance_radius = radius
	avoidance_strength = strength
	neighbor_search_radius = search_radius

func set_path_optimization(enabled: bool, smoothing: bool, simplification: float) -> void:
	"""Set path optimization settings"""
	path_optimization_enabled = enabled
	path_smoothing_enabled = smoothing
	path_simplification_threshold = simplification

func get_pathfinding_statistics() -> Dictionary:
	"""Get pathfinding system statistics"""
	return {
		"active_paths": unit_paths.size(),
		"queued_requests": path_requests.size(),
		"cached_paths": path_cache.size(),
		"moving_units": _count_moving_units(),
		"formation_paths": formation_paths.size(),
		"cache_hit_rate": _calculate_cache_hit_rate()
	}

func _count_moving_units() -> int:
	"""Count units currently moving"""
	var count = 0
	for unit_id in unit_movement_states:
		if is_unit_moving(unit_id):
			count += 1
	return count

func _calculate_cache_hit_rate() -> float:
	"""Calculate cache hit rate"""
	var total_usage = 0
	var total_entries = path_cache.size()
	
	for key in path_cache:
		var entry = path_cache[key]
		total_usage += entry.usage_count
	
	return float(total_usage) / float(max(total_entries, 1)) if total_entries > 0 else 0.0

func add_navigation_obstacle(obstacle: Node3D) -> void:
	"""Add navigation obstacle"""
	if obstacle and navigation_map.is_valid():
		# This would integrate with NavigationObstacle3D
		pass

func remove_navigation_obstacle(obstacle: Node3D) -> void:
	"""Remove navigation obstacle"""
	if obstacle and navigation_map.is_valid():
		# This would integrate with NavigationObstacle3D
		pass

func update_navigation_mesh(mesh: NavigationMesh) -> void:
	"""Update navigation mesh"""
	if mesh and navigation_map.is_valid():
		# This would update the navigation mesh
		pass

func get_navigation_map() -> RID:
	"""Get navigation map RID"""
	return navigation_map 