# FormationSystem.gd
class_name FormationSystem
extends Node

# Formation types
enum FormationType {
	LINE,
	COLUMN,
	WEDGE,
	SCATTERED,
	CIRCLE,
	DIAMOND,
	CUSTOM
}

# Formation data structure
class Formation:
	var formation_id: String
	var type: FormationType
	var leader: Unit
	var units: Array[Unit] = []
	var positions: Array[Vector3] = []
	var spacing: float = 5.0
	var rotation: float = 0.0
	var is_moving: bool = false
	var target_position: Vector3 = Vector3.ZERO
	var maintain_formation: bool = true
	var formation_speed: float = 8.0
	var cohesion_strength: float = 1.0
	var separation_strength: float = 1.5
	var alignment_strength: float = 0.5
	
	func _init(id: String, form_type: FormationType, leader_unit: Unit):
		formation_id = id
		type = form_type
		leader = leader_unit
		units.append(leader_unit)

# Formation templates
const FORMATION_TEMPLATES = {
	FormationType.LINE: {
		"name": "Line Formation",
		"description": "Units form a horizontal line",
		"optimal_size": 5,
		"spacing": 4.0,
		"advantages": ["Wide front", "Good for area coverage"],
		"disadvantages": ["Vulnerable to flanking", "Hard to maneuver"]
	},
	FormationType.COLUMN: {
		"name": "Column Formation", 
		"description": "Units form a vertical column",
		"optimal_size": 5,
		"spacing": 3.0,
		"advantages": ["Easy to maneuver", "Good for narrow passages"],
		"disadvantages": ["Vulnerable to area attacks", "Limited firepower"]
	},
	FormationType.WEDGE: {
		"name": "Wedge Formation",
		"description": "Units form a triangular wedge",
		"optimal_size": 5,
		"spacing": 4.5,
		"advantages": ["Good for breakthrough", "Concentrated firepower"],
		"disadvantages": ["Weak flanks", "Complex coordination"]
	},
	FormationType.SCATTERED: {
		"name": "Scattered Formation",
		"description": "Units spread out randomly",
		"optimal_size": 5,
		"spacing": 8.0,
		"advantages": ["Hard to target", "Flexible positioning"],
		"disadvantages": ["Poor coordination", "Reduced mutual support"]
	},
	FormationType.CIRCLE: {
		"name": "Circle Formation",
		"description": "Units form a defensive circle",
		"optimal_size": 4,
		"spacing": 6.0,
		"advantages": ["360-degree coverage", "Good for defense"],
		"disadvantages": ["Static positioning", "Limited mobility"]
	},
	FormationType.DIAMOND: {
		"name": "Diamond Formation",
		"description": "Units form a diamond shape",
		"optimal_size": 4,
		"spacing": 5.0,
		"advantages": ["Balanced coverage", "Good protection"],
		"disadvantages": ["Complex positioning", "Moderate effectiveness"]
	}
}

# Active formations
var active_formations: Dictionary = {}  # formation_id -> Formation
var unit_formations: Dictionary = {}    # unit_id -> formation_id
var formation_counter: int = 0

# Formation behavior settings
var update_interval: float = 0.1
var position_tolerance: float = 1.0
var rotation_tolerance: float = 0.1
var max_formation_speed: float = 12.0
var min_formation_speed: float = 3.0
var formation_break_distance: float = 20.0

# Update timers
var last_update_time: float = 0.0

# Visual indicators
var formation_indicators: Dictionary = {}  # formation_id -> visual_node

# Signals
signal formation_created(formation: Formation)
signal formation_disbanded(formation_id: String)
signal formation_updated(formation: Formation)
signal unit_joined_formation(unit: Unit, formation: Formation)
signal unit_left_formation(unit: Unit, formation_id: String)
signal formation_move_started(formation: Formation, target: Vector3)
signal formation_move_completed(formation: Formation)

func _ready() -> void:
	# Add to formation systems group
	add_to_group("formation_systems")
	
	# Start processing
	set_process(true)
	
	print("FormationSystem: Formation system initialized")

func _process(delta: float) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Update formations at regular intervals
	if current_time - last_update_time >= update_interval:
		_update_all_formations(delta)
		last_update_time = current_time

func _update_all_formations(delta: float) -> void:
	"""Update all active formations"""
	for formation_id in active_formations:
		var formation = active_formations[formation_id]
		_update_formation(formation, delta)

func _update_formation(formation: Formation, delta: float) -> void:
	"""Update a specific formation"""
	if not formation or formation.units.is_empty():
		return
	
	# Remove dead or invalid units
	_cleanup_formation_units(formation)
	
	# Check if formation should be disbanded
	if formation.units.size() < 2:
		disband_formation(formation.formation_id)
		return
	
	# Update formation positions
	_calculate_formation_positions(formation)
	
	# Apply formation movement
	if formation.is_moving:
		_update_formation_movement(formation, delta)
	else:
		_maintain_formation_positions(formation, delta)
	
	# Update visual indicators
	_update_formation_visuals(formation)

func _cleanup_formation_units(formation: Formation) -> void:
	"""Remove invalid units from formation"""
	var units_to_remove = []
	
	for unit in formation.units:
		if not unit or not is_instance_valid(unit) or unit.is_dead:
			units_to_remove.append(unit)
	
	for unit in units_to_remove:
		remove_unit_from_formation(unit, formation.formation_id)

func _calculate_formation_positions(formation: Formation) -> void:
	"""Calculate target positions for units in formation"""
	if not formation.leader or formation.units.is_empty():
		return
	
	var leader_pos = formation.leader.global_position
	var base_positions = _get_formation_pattern(formation.type, formation.units.size(), formation.spacing)
	
	formation.positions.clear()
	
	for i in range(formation.units.size()):
		if i < base_positions.size():
			var local_pos = base_positions[i]
			# Rotate position based on formation rotation
			var rotated_pos = _rotate_vector(local_pos, formation.rotation)
			var world_pos = leader_pos + rotated_pos
			formation.positions.append(world_pos)
		else:
			formation.positions.append(leader_pos)

func _get_formation_pattern(type: FormationType, unit_count: int, spacing: float) -> Array[Vector3]:
	"""Get formation pattern positions"""
	var positions: Array[Vector3] = []
	
	match type:
		FormationType.LINE:
			positions = _generate_line_formation(unit_count, spacing)
		FormationType.COLUMN:
			positions = _generate_column_formation(unit_count, spacing)
		FormationType.WEDGE:
			positions = _generate_wedge_formation(unit_count, spacing)
		FormationType.SCATTERED:
			positions = _generate_scattered_formation(unit_count, spacing)
		FormationType.CIRCLE:
			positions = _generate_circle_formation(unit_count, spacing)
		FormationType.DIAMOND:
			positions = _generate_diamond_formation(unit_count, spacing)
		_:
			positions = _generate_line_formation(unit_count, spacing)
	
	return positions

func _generate_line_formation(unit_count: int, spacing: float) -> Array[Vector3]:
	"""Generate line formation positions"""
	var positions: Array[Vector3] = []
	var start_offset = -(unit_count - 1) * spacing * 0.5
	
	for i in range(unit_count):
		var x = start_offset + i * spacing
		positions.append(Vector3(x, 0, 0))
	
	return positions

func _generate_column_formation(unit_count: int, spacing: float) -> Array[Vector3]:
	"""Generate column formation positions"""
	var positions: Array[Vector3] = []
	
	for i in range(unit_count):
		var z = -i * spacing
		positions.append(Vector3(0, 0, z))
	
	return positions

func _generate_wedge_formation(unit_count: int, spacing: float) -> Array[Vector3]:
	"""Generate wedge formation positions"""
	var positions: Array[Vector3] = []
	positions.append(Vector3(0, 0, 0))  # Leader at front
	
	var side = -1  # Alternate sides
	var row = 1
	var positions_in_row = 0
	
	for i in range(1, unit_count):
		var x = side * spacing * (positions_in_row + 1)
		var z = -row * spacing * 0.8
		positions.append(Vector3(x, 0, z))
		
		side *= -1
		positions_in_row += 1
		
		if positions_in_row >= row:
			row += 1
			positions_in_row = 0
	
	return positions

func _generate_scattered_formation(unit_count: int, spacing: float) -> Array[Vector3]:
	"""Generate scattered formation positions"""
	var positions: Array[Vector3] = []
	positions.append(Vector3(0, 0, 0))  # Leader at center
	
	for i in range(1, unit_count):
		var angle = randf() * PI * 2
		var distance = randf_range(spacing * 0.5, spacing * 1.5)
		var x = cos(angle) * distance
		var z = sin(angle) * distance
		positions.append(Vector3(x, 0, z))
	
	return positions

func _generate_circle_formation(unit_count: int, spacing: float) -> Array[Vector3]:
	"""Generate circle formation positions"""
	var positions: Array[Vector3] = []
	var radius = spacing * unit_count / (2 * PI)
	
	for i in range(unit_count):
		var angle = (i / float(unit_count)) * PI * 2
		var x = cos(angle) * radius
		var z = sin(angle) * radius
		positions.append(Vector3(x, 0, z))
	
	return positions

func _generate_diamond_formation(unit_count: int, spacing: float) -> Array[Vector3]:
	"""Generate diamond formation positions"""
	var positions: Array[Vector3] = []
	
	if unit_count >= 1:
		positions.append(Vector3(0, 0, spacing))  # Front
	if unit_count >= 2:
		positions.append(Vector3(-spacing, 0, 0))  # Left
	if unit_count >= 3:
		positions.append(Vector3(spacing, 0, 0))   # Right
	if unit_count >= 4:
		positions.append(Vector3(0, 0, -spacing))  # Back
	
	# Additional units form inner diamond
	for i in range(4, unit_count):
		var angle = (i - 4) * PI * 2 / (unit_count - 4)
		var x = cos(angle) * spacing * 0.6
		var z = sin(angle) * spacing * 0.6
		positions.append(Vector3(x, 0, z))
	
	return positions

func _update_formation_movement(formation: Formation, delta: float) -> void:
	"""Update formation movement towards target"""
	if not formation.leader:
		return
	
	var leader_pos = formation.leader.global_position
	var distance_to_target = leader_pos.distance_to(formation.target_position)
	
	# Check if formation has reached target
	if distance_to_target <= position_tolerance:
		formation.is_moving = false
		formation_move_completed.emit(formation)
		return
	
	# Move leader towards target
	var direction = (formation.target_position - leader_pos).normalized()
	var movement_speed = min(formation.formation_speed, distance_to_target / delta)
	
	if formation.leader.has_method("move_to"):
		formation.leader.move_to(formation.target_position)
	
	# Apply formation cohesion and separation
	_apply_formation_forces(formation, delta)

func _maintain_formation_positions(formation: Formation, delta: float) -> void:
	"""Maintain formation positions when not moving"""
	_apply_formation_forces(formation, delta)

func _apply_formation_forces(formation: Formation, delta: float) -> void:
	"""Apply cohesion, separation, and alignment forces"""
	for i in range(formation.units.size()):
		var unit = formation.units[i]
		if not unit or not is_instance_valid(unit) or unit.is_dead:
			continue
		
		var target_pos = formation.positions[i] if i < formation.positions.size() else formation.leader.global_position
		var current_pos = unit.global_position
		
		# Calculate forces
		var cohesion_force = _calculate_cohesion_force(unit, target_pos, formation.cohesion_strength)
		var separation_force = _calculate_separation_force(unit, formation.units, formation.separation_strength)
		var alignment_force = _calculate_alignment_force(unit, formation.units, formation.alignment_strength)
		
		# Combine forces
		var total_force = cohesion_force + separation_force + alignment_force
		
		# Apply movement
		if total_force.length() > 0.1:
			var target_position = current_pos + total_force * delta
			if unit.has_method("move_to"):
				unit.move_to(target_position)

func _calculate_cohesion_force(unit: Unit, target_pos: Vector3, strength: float) -> Vector3:
	"""Calculate cohesion force towards target position"""
	var current_pos = unit.global_position
	var direction = (target_pos - current_pos)
	var distance = direction.length()
	
	if distance <= position_tolerance:
		return Vector3.ZERO
	
	return direction.normalized() * strength * min(distance, 10.0)

func _calculate_separation_force(unit: Unit, units: Array[Unit], strength: float) -> Vector3:
	"""Calculate separation force to avoid crowding"""
	var separation_force = Vector3.ZERO
	var current_pos = unit.global_position
	
	for other_unit in units:
		if other_unit == unit or not other_unit or not is_instance_valid(other_unit):
			continue
		
		var distance = current_pos.distance_to(other_unit.global_position)
		if distance < 3.0:  # Minimum separation distance
			var direction = (current_pos - other_unit.global_position).normalized()
			separation_force += direction * strength * (3.0 - distance)
	
	return separation_force

func _calculate_alignment_force(unit: Unit, units: Array[Unit], strength: float) -> Vector3:
	"""Calculate alignment force to match unit velocities"""
	var average_velocity = Vector3.ZERO
	var count = 0
	
	for other_unit in units:
		if other_unit == unit or not other_unit or not is_instance_valid(other_unit):
			continue
		
		if other_unit.has_method("get_velocity"):
			average_velocity += other_unit.get_velocity()
			count += 1
	
	if count > 0:
		average_velocity /= count
		return average_velocity * strength
	
	return Vector3.ZERO

func _rotate_vector(vector: Vector3, angle: float) -> Vector3:
	"""Rotate vector by angle in radians"""
	var cos_angle = cos(angle)
	var sin_angle = sin(angle)
	
	return Vector3(
		vector.x * cos_angle - vector.z * sin_angle,
		vector.y,
		vector.x * sin_angle + vector.z * cos_angle
	)

func _update_formation_visuals(formation: Formation) -> void:
	"""Update visual indicators for formation"""
	if formation.formation_id in formation_indicators:
		var indicator = formation_indicators[formation.formation_id]
		if indicator and is_instance_valid(indicator):
			indicator.global_position = formation.leader.global_position
			indicator.rotation.y = formation.rotation

# Public API
func create_formation(type: FormationType, leader: Unit, units: Array[Unit] = []) -> String:
	"""Create a new formation"""
	if not leader or not is_instance_valid(leader):
		print("FormationSystem: Invalid leader unit")
		return ""
	
	formation_counter += 1
	var formation_id = "formation_" + str(formation_counter)
	
	var formation = Formation.new(formation_id, type, leader)
	formation.spacing = FORMATION_TEMPLATES[type]["spacing"]
	
	# Add additional units
	for unit in units:
		if unit and is_instance_valid(unit) and unit != leader:
			formation.units.append(unit)
			unit_formations[unit.unit_id] = formation_id
	
	# Set up formation
	unit_formations[leader.unit_id] = formation_id
	active_formations[formation_id] = formation
	
	# Create visual indicator
	_create_formation_indicator(formation)
	
	# Calculate initial positions
	_calculate_formation_positions(formation)
	
	print("FormationSystem: Created %s formation with %d units" % [FORMATION_TEMPLATES[type]["name"], formation.units.size()])
	formation_created.emit(formation)
	
	return formation_id

func disband_formation(formation_id: String) -> bool:
	"""Disband a formation"""
	if not formation_id in active_formations:
		return false
	
	var formation = active_formations[formation_id]
	
	# Remove units from formation tracking
	for unit in formation.units:
		if unit and unit.unit_id in unit_formations:
			unit_formations.erase(unit.unit_id)
			unit_left_formation.emit(unit, formation_id)
	
	# Remove visual indicator
	if formation_id in formation_indicators:
		var indicator = formation_indicators[formation_id]
		if indicator and is_instance_valid(indicator):
			indicator.queue_free()
		formation_indicators.erase(formation_id)
	
	# Remove formation
	active_formations.erase(formation_id)
	
	print("FormationSystem: Disbanded formation %s" % formation_id)
	formation_disbanded.emit(formation_id)
	
	return true

func add_unit_to_formation(unit: Unit, formation_id: String) -> bool:
	"""Add unit to existing formation"""
	if not unit or not is_instance_valid(unit):
		return false
	
	if not formation_id in active_formations:
		return false
	
	var formation = active_formations[formation_id]
	
	# Remove from previous formation if any
	if unit.unit_id in unit_formations:
		remove_unit_from_formation(unit, unit_formations[unit.unit_id])
	
	# Add to new formation
	formation.units.append(unit)
	unit_formations[unit.unit_id] = formation_id
	
	# Recalculate positions
	_calculate_formation_positions(formation)
	
	print("FormationSystem: Added unit %s to formation %s" % [unit.unit_id, formation_id])
	unit_joined_formation.emit(unit, formation)
	
	return true

func remove_unit_from_formation(unit: Unit, formation_id: String) -> bool:
	"""Remove unit from formation"""
	if not unit or not formation_id in active_formations:
		return false
	
	var formation = active_formations[formation_id]
	
	# Remove unit
	if unit in formation.units:
		formation.units.erase(unit)
	
	if unit.unit_id in unit_formations:
		unit_formations.erase(unit.unit_id)
	
	# Update leader if necessary
	if formation.leader == unit and not formation.units.is_empty():
		formation.leader = formation.units[0]
	
	# Recalculate positions
	_calculate_formation_positions(formation)
	
	print("FormationSystem: Removed unit %s from formation %s" % [unit.unit_id, formation_id])
	unit_left_formation.emit(unit, formation_id)
	
	return true

func move_formation(formation_id: String, target_position: Vector3) -> bool:
	"""Move formation to target position"""
	if not formation_id in active_formations:
		return false
	
	var formation = active_formations[formation_id]
	formation.target_position = target_position
	formation.is_moving = true
	
	print("FormationSystem: Moving formation %s to %s" % [formation_id, target_position])
	formation_move_started.emit(formation, target_position)
	
	return true

func set_formation_type(formation_id: String, new_type: FormationType) -> bool:
	"""Change formation type"""
	if not formation_id in active_formations:
		return false
	
	var formation = active_formations[formation_id]
	formation.type = new_type
	formation.spacing = FORMATION_TEMPLATES[new_type]["spacing"]
	
	# Recalculate positions
	_calculate_formation_positions(formation)
	
	print("FormationSystem: Changed formation %s to %s" % [formation_id, FORMATION_TEMPLATES[new_type]["name"]])
	formation_updated.emit(formation)
	
	return true

func set_formation_spacing(formation_id: String, spacing: float) -> bool:
	"""Set formation spacing"""
	if not formation_id in active_formations:
		return false
	
	var formation = active_formations[formation_id]
	formation.spacing = max(2.0, spacing)
	
	# Recalculate positions
	_calculate_formation_positions(formation)
	
	formation_updated.emit(formation)
	return true

func set_formation_rotation(formation_id: String, rotation: float) -> bool:
	"""Set formation rotation"""
	if not formation_id in active_formations:
		return false
	
	var formation = active_formations[formation_id]
	formation.rotation = rotation
	
	# Recalculate positions
	_calculate_formation_positions(formation)
	
	formation_updated.emit(formation)
	return true

func get_formation(formation_id: String) -> Formation:
	"""Get formation by ID"""
	return active_formations.get(formation_id, null)

func get_unit_formation(unit: Unit) -> Formation:
	"""Get formation containing unit"""
	if not unit or not unit.unit_id in unit_formations:
		return null
	
	var formation_id = unit_formations[unit.unit_id]
	return active_formations.get(formation_id, null)

func get_all_formations() -> Array[Formation]:
	"""Get all active formations"""
	var formations: Array[Formation] = []
	for formation_id in active_formations:
		formations.append(active_formations[formation_id])
	return formations

func get_formation_info(formation_id: String) -> Dictionary:
	"""Get detailed formation information"""
	if not formation_id in active_formations:
		return {}
	
	var formation = active_formations[formation_id]
	var template = FORMATION_TEMPLATES[formation.type]
	
	return {
		"id": formation.formation_id,
		"type": formation.type,
		"name": template["name"],
		"description": template["description"],
		"unit_count": formation.units.size(),
		"leader": formation.leader.unit_id if formation.leader else "",
		"spacing": formation.spacing,
		"rotation": formation.rotation,
		"is_moving": formation.is_moving,
		"target_position": formation.target_position,
		"advantages": template["advantages"],
		"disadvantages": template["disadvantages"]
	}

func _create_formation_indicator(formation: Formation) -> void:
	"""Create visual indicator for formation"""
	var indicator = MeshInstance3D.new()
	indicator.name = "FormationIndicator"
	indicator.mesh = CylinderMesh.new()
	indicator.mesh.height = 0.1
	indicator.mesh.top_radius = 2.0
	indicator.mesh.bottom_radius = 2.0
	indicator.position = formation.leader.global_position
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.CYAN
	material.flags_transparent = true
	material.albedo_color.a = 0.3
	material.emission_enabled = true
	material.emission = Color.CYAN * 0.2
	indicator.material_override = material
	
	get_tree().current_scene.add_child(indicator)
	formation_indicators[formation.formation_id] = indicator

func get_formation_templates() -> Dictionary:
	"""Get all formation templates"""
	return FORMATION_TEMPLATES

func get_optimal_formation_for_situation(situation: String, unit_count: int) -> FormationType:
	"""Get optimal formation type for situation"""
	match situation:
		"attack":
			return FormationType.WEDGE if unit_count >= 3 else FormationType.LINE
		"defense":
			return FormationType.CIRCLE if unit_count >= 4 else FormationType.LINE
		"movement":
			return FormationType.COLUMN if unit_count >= 3 else FormationType.LINE
		"patrol":
			return FormationType.LINE
		"stealth":
			return FormationType.SCATTERED
		_:
			return FormationType.LINE

func get_formation_statistics() -> Dictionary:
	"""Get formation system statistics"""
	return {
		"active_formations": active_formations.size(),
		"total_units_in_formations": unit_formations.size(),
		"formation_types": _count_formation_types(),
		"average_formation_size": _calculate_average_formation_size()
	}

func _count_formation_types() -> Dictionary:
	"""Count formations by type"""
	var counts = {}
	for formation_id in active_formations:
		var formation = active_formations[formation_id]
		var type_name = FORMATION_TEMPLATES[formation.type]["name"]
		counts[type_name] = counts.get(type_name, 0) + 1
	return counts

func _calculate_average_formation_size() -> float:
	"""Calculate average formation size"""
	if active_formations.is_empty():
		return 0.0
	
	var total_units = 0
	for formation_id in active_formations:
		var formation = active_formations[formation_id]
		total_units += formation.units.size()
	
	return float(total_units) / float(active_formations.size()) 