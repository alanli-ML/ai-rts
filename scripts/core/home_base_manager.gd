# HomeBaseManager.gd
class_name HomeBaseManager
extends Node3D

# Home base positions for teams (moved inward from edges for safety)
const HOME_BASE_POSITIONS = {
	1: Vector3(-47.02, 0.5, -35.0086),  # Team 1: Calculated from city_map Team1Base transform
	2: Vector3(25.513, 0.5, 48.651)     # Team 2: Calculated from city_map Team2Base transform
}

# Unit spawn areas around home bases (radius for spawning units)
const SPAWN_RADIUS = 8.0
const SPAWN_HEIGHT = 1.0
const HEALING_RADIUS = 20.0
const HEALING_RATE = 5.0 # HP per second

# Building assets for home bases
const HOME_BASE_BUILDINGS = {
	"command_center": "res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/building-skyscraper-a.glb",
	"secondary": "res://assets/kenney/kenney_city-kit-industrial_1/Models/GLB format/building-d.glb",
	"support": "res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/building-f.glb"
}

# Team colors (matches unit team colors)
const TEAM_COLORS = {
	1: Color(0.2, 0.4, 1.0),    # Blue team
	2: Color(1.0, 0.3, 0.2),    # Red team
	3: Color(0.2, 1.0, 0.4),    # Green team  
	4: Color(1.0, 0.8, 0.2)     # Yellow team
}

# Home base data
var home_bases: Dictionary = {}  # team_id -> home_base_data
var spawn_points: Dictionary = {} # team_id -> spawn_position
var units_in_healing_zone: Dictionary = {} # team_id -> Array[Unit]

# Signals
signal home_base_created(team_id: int, position: Vector3)
signal home_base_destroyed(team_id: int)

func _ready() -> void:
	print("HomeBaseManager: Initializing home bases...")
	# Add to home_base_managers group for easy discovery
	add_to_group("home_base_managers")
	_setup_home_bases()
	set_physics_process(multiplayer.is_server())

func _physics_process(delta: float):
	for team_id in units_in_healing_zone:
		var units_to_heal = units_in_healing_zone[team_id]
		
		# Filter out invalid units first
		units_in_healing_zone[team_id] = units_to_heal.filter(func(unit): return is_instance_valid(unit) and not unit.is_dead)
		
		# Heal the remaining valid units
		for unit in units_in_healing_zone[team_id]:
			if unit.has_method("receive_healing"):
				unit.receive_healing(HEALING_RATE * delta)

func _setup_home_bases() -> void:
	"""Setup home bases for all teams"""
	# Create home bases for both teams
	for team_id in HOME_BASE_POSITIONS:
		_create_home_base(team_id)
	
	print("HomeBaseManager: Home bases setup complete")

func _create_home_base(team_id: int) -> void:
	"""Create a home base for the specified team"""
	var base_position = HOME_BASE_POSITIONS.get(team_id, Vector3.ZERO)
	
	if base_position == Vector3.ZERO:
		print("HomeBaseManager: No position defined for team %d" % team_id)
		return
	
	print("HomeBaseManager: Creating home base for team %d at %s" % [team_id, base_position])
	
	# Create home base container
	var home_base_node = Node3D.new()
	home_base_node.name = "HomeBase_Team_%d" % team_id
	home_base_node.position = base_position
	add_child(home_base_node)
	
	# Create main command center building
	var command_center = _create_building("command_center", Vector3.ZERO, team_id)
	if command_center:
		command_center.name = "CommandCenter_Team_%d" % team_id
		home_base_node.add_child(command_center)
	
	# Create healing area
	var healing_area = Area3D.new()
	healing_area.name = "HealingAura"
	var collision_shape = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = HEALING_RADIUS
	collision_shape.shape = shape
	healing_area.add_child(collision_shape)
	home_base_node.add_child(healing_area)
	
	healing_area.body_entered.connect(_on_unit_entered_healing_zone.bind(team_id))
	healing_area.body_exited.connect(_on_unit_exited_healing_zone.bind(team_id))
	
	# Create secondary buildings around the command center
	var secondary_positions = [
		Vector3(-8, 0, -5),   # Left building
		Vector3(8, 0, -5),    # Right building
		Vector3(0, 0, 10)     # Back building
	]
	
	#for i in range(secondary_positions.size()):
	#	var building = _create_building("secondary", secondary_positions[i], team_id)
	#	if building:
	#		building.name = "Building_%d_Team_%d" % [i + 1, team_id]
	#		home_base_node.add_child(building)
	
	# Store home base data
	home_bases[team_id] = {
		"position": base_position,
		"node": home_base_node,
		"team_id": team_id
	}
	
	# Set spawn point for this team (slightly offset from base)
	spawn_points[team_id] = base_position + Vector3(0, 0, -12)  # Spawn in front of base
	
	# Add to buildings group for game systems
	home_base_node.add_to_group("buildings")
	home_base_node.add_to_group("home_bases")
	
	# Emit signal
	home_base_created.emit(team_id, base_position)
	
	print("HomeBaseManager: Home base created for team %d" % team_id)

func _create_building(building_type: String, offset: Vector3, team_id: int) -> Node3D:
	"""Create a building with team coloring"""
	var building_path = HOME_BASE_BUILDINGS.get(building_type, "")
	
	if building_path.is_empty() or not ResourceLoader.exists(building_path):
		print("HomeBaseManager: Building asset not found: %s" % building_path)
		return null
	
	# Load building scene
	var building_scene = load(building_path)
	var building_node = building_scene.instantiate()
	
	if not building_node:
		print("HomeBaseManager: Failed to instantiate building: %s" % building_path)
		return null
	
	# Position the building
	building_node.position = offset
	
	# Apply team coloring
	_apply_team_coloring(building_node, team_id)
	
	# Add collision and interaction
	_setup_building_collision(building_node)
	
	# Add building metadata
	building_node.set_meta("team_id", team_id)
	building_node.set_meta("building_type", "home_base")
	building_node.set_meta("building_category", building_type)
	
	return building_node

func _apply_team_coloring(building_node: Node3D, team_id: int) -> void:
	"""Apply team colors to building materials"""
	var team_color = TEAM_COLORS.get(team_id, Color.WHITE)
	
	# Find all MeshInstance3D nodes in the building
	var mesh_instances = _find_all_mesh_instances(building_node)
	
	for mesh_instance in mesh_instances:
		if mesh_instance.material_override:
			# Clone existing material and modify
			var material = mesh_instance.material_override.duplicate()
			if material is StandardMaterial3D:
				material.albedo_color = material.albedo_color * team_color
				material.emission_enabled = true
				material.emission = team_color * 0.3  # Subtle glow
				mesh_instance.material_override = material
		else:
			# Create new team-colored material
			var material = StandardMaterial3D.new()
			material.albedo_color = team_color
			material.emission_enabled = true
			material.emission = team_color * 0.2
			material.metallic = 0.3
			material.roughness = 0.7
			mesh_instance.material_override = material

func _find_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	"""Recursively find all MeshInstance3D nodes"""
	var mesh_instances: Array[MeshInstance3D] = []
	
	if node is MeshInstance3D:
		mesh_instances.append(node as MeshInstance3D)
	
	for child in node.get_children():
		mesh_instances.append_array(_find_all_mesh_instances(child))
	
	return mesh_instances

func _setup_building_collision(building_node: Node3D) -> void:
	"""Setup collision for building (disabled for units to pass through)"""
	# Check if building already has collision
	var has_collision = false
	for child in building_node.get_children():
		if child is CollisionShape3D or child is StaticBody3D:
			has_collision = true
			break
	
	if not has_collision:
		# Create basic collision for the building on a separate layer
		var static_body = StaticBody3D.new()
		static_body.name = "BuildingCollision"
		
		# Put buildings on collision layer 3 (separate from units on layer 1)
		# Units won't collide with buildings this way
		static_body.set_collision_layer_value(1, false)  # Not on unit layer
		static_body.set_collision_layer_value(3, true)   # On building layer
		static_body.set_collision_mask_value(1, false)   # Don't collide with units
		
		var collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		
		# Create a box shape based on the building's approximate size
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(6, 8, 6)  # Approximate building size
		collision_shape.shape = box_shape
		collision_shape.position = Vector3(0, 4, 0)  # Center the collision
		
		static_body.add_child(collision_shape)
		building_node.add_child(static_body)

# Public interface for spawn positions
func get_team_spawn_position(team_id: int) -> Vector3:
	"""Get the spawn position for a team"""
	return spawn_points.get(team_id, Vector3.ZERO)

func get_home_base_position(team_id: int) -> Vector3:
	"""Get the home base position for a team"""
	return HOME_BASE_POSITIONS.get(team_id, Vector3.ZERO)

func get_spawn_position_with_offset(team_id: int, offset: Vector3 = Vector3.ZERO) -> Vector3:
	"""Get spawn position with random offset within spawn radius, clamped to map bounds"""
	var base_spawn = get_team_spawn_position(team_id)
	
	if offset == Vector3.ZERO:
		# Generate random offset within spawn radius
		var angle = randf() * 2 * PI
		var radius = randf() * SPAWN_RADIUS
		offset = Vector3(
			cos(angle) * radius,
			SPAWN_HEIGHT,
			sin(angle) * radius
		)
	
	var final_position = base_spawn + offset
	
	# Clamp to map bounds (using the same bounds as Unit class)
	final_position.x = clamp(final_position.x, -40.0, 40.0)  # Leave 5 unit safety margin
	final_position.z = clamp(final_position.z, -40.0, 40.0)  # Leave 5 unit safety margin
	
	return final_position

func is_near_home_base(position: Vector3, team_id: int, max_distance: float = 20.0) -> bool:
	"""Check if position is near a team's home base"""
	var home_base_pos = get_home_base_position(team_id)
	return position.distance_to(home_base_pos) <= max_distance

func get_all_home_base_positions() -> Dictionary:
	"""Get all home base positions"""
	return HOME_BASE_POSITIONS.duplicate()

func get_team_buildings(team_id: int) -> Array[Node3D]:
	"""Get all buildings for a specific team"""
	var team_buildings: Array[Node3D] = []
	
	if home_bases.has(team_id):
		var home_base_node = home_bases[team_id].node
		if home_base_node:
			team_buildings.append(home_base_node)
			# Add all children buildings
			for child in home_base_node.get_children():
				if child is Node3D:
					team_buildings.append(child)
	
	return team_buildings

func destroy_home_base(team_id: int) -> void:
	"""Destroy a team's home base (for end game conditions)"""
	if home_bases.has(team_id):
		var home_base_data = home_bases[team_id]
		if home_base_data.node:
			home_base_data.node.queue_free()
		
		home_bases.erase(team_id)
		spawn_points.erase(team_id)
		
		home_base_destroyed.emit(team_id)
		print("HomeBaseManager: Home base destroyed for team %d" % team_id)

# Static utility functions for other systems
static func get_default_team_spawn_position(team_id: int) -> Vector3:
	"""Static method to get team spawn positions when HomeBaseManager isn't available"""
	return HOME_BASE_POSITIONS.get(team_id, Vector3.ZERO)

func _on_unit_entered_healing_zone(body: Node3D, team_id: int):
	if body is Unit and body.team_id == team_id:
		if not units_in_healing_zone.has(team_id):
			units_in_healing_zone[team_id] = []
		if not body in units_in_healing_zone[team_id]:
			units_in_healing_zone[team_id].append(body)

func _on_unit_exited_healing_zone(body: Node3D, team_id: int):
	if body is Unit and body.team_id == team_id:
		if units_in_healing_zone.has(team_id):
			units_in_healing_zone[team_id].erase(body)

func get_debug_info() -> Dictionary:
	"""Get debug information about home bases"""
	return {
		"home_bases": home_bases.keys(),
		"spawn_points": spawn_points,
		"positions": HOME_BASE_POSITIONS
	} 