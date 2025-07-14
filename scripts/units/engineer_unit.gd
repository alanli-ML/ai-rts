# EngineerUnit.gd
class_name EngineerUnit
extends Unit

# Engineer-specific properties
var build_speed: float = 2.0
var repair_range: float = 5.0
var repair_rate: float = 15.0
var repair_energy_cost: float = 3.0
var is_building: bool = false
var is_repairing: bool = false
var current_build_target: Node3D = null
var current_repair_target: Node3D = null
var mine_deployment_range: float = 10.0
var deployed_mines: Array[Node3D] = []
var max_mines: int = 3

func _ready() -> void:
	archetype = "engineer"
	system_prompt = "You are a versatile engineer unit. Your role is to build structures, repair damaged buildings, and deploy tactical equipment. You can fight when needed but excel at support and utility tasks."
	
	# Call parent _ready
	super._ready()
	
	# Engineer-specific setup
	_setup_engineer_abilities()

func _setup_engineer_abilities() -> void:
	# Engineers have moderate stats with utility focus
	max_health = 120.0
	current_health = max_health
	
	# Medium movement speed
	speed = 8.0
	move_speed = 8.0
	
	# Medium vision range
	vision_range = 30.0
	vision_angle = 120.0
	
	# Light combat capability
	attack_range = 12.0
	attack_damage = 25.0
	
	# Set build speed from config
	var stats = ConfigManager.get_unit_stats("engineer")
	if not stats.is_empty():
		build_speed = stats.build_speed
	
	# Update visual for engineer
	_update_engineer_visual()

func _update_engineer_visual() -> void:
	if unit_model:
		# Keep engineer normal size
		unit_model.scale = Vector3(1.0, 1.0, 1.0)
		
		# Different color scheme
		var material = unit_model.material_override as StandardMaterial3D
		if material:
			if team_id == 1:
				material.albedo_color = Color.ORANGE  # Orange/construction for team 1
			else:
				material.albedo_color = Color.PURPLE  # Purple for team 2
			
			# Make material look industrial
			material.metallic = 0.6
			material.roughness = 0.7

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Handle building
	if is_building and current_build_target:
		_continue_building(delta)
	
	# Handle repairing
	if is_repairing and current_repair_target:
		_continue_repairing(delta)

func _continue_building(delta: float) -> void:
	if not current_build_target:
		stop_building()
		return
	
	var distance = global_position.distance_to(current_build_target.global_position)
	if distance > repair_range:
		stop_building()
		return
	
	# Check if we have enough energy
	if energy < repair_energy_cost * delta:
		stop_building()
		return
	
	# Continue building (this would update building progress)
	energy -= repair_energy_cost * delta
	
	# Visual feedback
	_show_building_effect()

func _continue_repairing(delta: float) -> void:
	if not current_repair_target:
		stop_repairing()
		return
	
	var distance = global_position.distance_to(current_repair_target.global_position)
	if distance > repair_range:
		stop_repairing()
		return
	
	# Check if we have enough energy
	if energy < repair_energy_cost * delta:
		stop_repairing()
		return
	
	# Continue repairing
	energy -= repair_energy_cost * delta
	
	# Visual feedback
	_show_repair_effect()

func can_build() -> bool:
	return not is_building and not is_repairing and energy >= 10.0

func start_building(building_type: String, position: Vector3) -> bool:
	if not can_build():
		Logger.debug("EngineerUnit", "Engineer %s cannot build (busy or no energy)" % unit_id)
		return false
	
	var distance = global_position.distance_to(position)
	if distance > repair_range:
		Logger.debug("EngineerUnit", "Engineer %s build position too far" % unit_id)
		return false
	
	# Create building placeholder
	var building = Node3D.new()
	building.name = "Building_%s" % building_type
	building.position = position
	get_tree().current_scene.add_child(building)
	
	# Start building
	is_building = true
	current_build_target = building
	
	Logger.info("EngineerUnit", "Engineer %s started building %s at %s" % [unit_id, building_type, position])
	return true

func stop_building() -> void:
	is_building = false
	current_build_target = null
	Logger.debug("EngineerUnit", "Engineer %s stopped building" % unit_id)

func _show_building_effect() -> void:
	# Visual effect for building
	modulate = Color(1.2, 1.0, 0.8, 1.0)  # Orange tint
	
	# Restore after brief effect
	await get_tree().create_timer(0.2).timeout
	modulate = Color.WHITE

func can_repair() -> bool:
	return not is_building and not is_repairing and energy >= 5.0

func start_repairing(target: Node3D) -> bool:
	if not can_repair():
		Logger.debug("EngineerUnit", "Engineer %s cannot repair (busy or no energy)" % unit_id)
		return false
	
	var distance = global_position.distance_to(target.global_position)
	if distance > repair_range:
		Logger.debug("EngineerUnit", "Engineer %s repair target too far" % unit_id)
		return false
	
	# Start repairing
	is_repairing = true
	current_repair_target = target
	
	Logger.info("EngineerUnit", "Engineer %s started repairing %s" % [unit_id, target.name])
	return true

func stop_repairing() -> void:
	is_repairing = false
	current_repair_target = null
	Logger.debug("EngineerUnit", "Engineer %s stopped repairing" % unit_id)

func _show_repair_effect() -> void:
	# Visual effect for repairing
	modulate = Color(0.8, 1.2, 1.0, 1.0)  # Cyan tint
	
	# Restore after brief effect
	await get_tree().create_timer(0.2).timeout
	modulate = Color.WHITE

func deploy_mine(position: Vector3) -> bool:
	if deployed_mines.size() >= max_mines:
		Logger.debug("EngineerUnit", "Engineer %s cannot deploy more mines (max reached)" % unit_id)
		return false
	
	var distance = global_position.distance_to(position)
	if distance > mine_deployment_range:
		Logger.debug("EngineerUnit", "Engineer %s mine position too far" % unit_id)
		return false
	
	if energy < 20.0:
		Logger.debug("EngineerUnit", "Engineer %s insufficient energy for mine" % unit_id)
		return false
	
	# Create mine
	var mine = _create_mine(position)
	if mine:
		deployed_mines.append(mine)
		energy -= 20.0
		
		Logger.info("EngineerUnit", "Engineer %s deployed mine at %s" % [unit_id, position])
		return true
	
	return false

func _create_mine(position: Vector3) -> Node3D:
	# Create a simple mine node
	var mine = Node3D.new()
	mine.name = "Mine_%s" % randf()
	mine.position = position
	
	# Add visual representation
	var mine_visual = MeshInstance3D.new()
	mine_visual.mesh = SphereMesh.new()
	mine_visual.mesh.radius = 0.3
	mine_visual.mesh.height = 0.6
	
	var mine_material = StandardMaterial3D.new()
	mine_material.albedo_color = Color.DARK_GRAY
	mine_visual.material_override = mine_material
	
	mine.add_child(mine_visual)
	
	# Add detection area
	var detection_area = Area3D.new()
	var detection_shape = CollisionShape3D.new()
	detection_shape.shape = SphereShape3D.new()
	detection_shape.shape.radius = 2.0
	
	detection_area.add_child(detection_shape)
	mine.add_child(detection_area)
	
	# Connect signals
	detection_area.body_entered.connect(_on_mine_triggered.bind(mine))
	
	get_tree().current_scene.add_child(mine)
	return mine

func _on_mine_triggered(mine: Node3D, body: Node3D) -> void:
	if body is Unit:
		var unit = body as Unit
		if unit.is_enemy_of(self):
			# Explode mine
			_explode_mine(mine)

func _explode_mine(mine: Node3D) -> void:
	var explosion_radius = 5.0
	var explosion_damage = 50.0
	
	# Find all units in explosion radius
	var all_units = get_tree().get_nodes_in_group("units")
	var damaged_units = 0
	
	for node in all_units:
		if node is Unit:
			var unit = node as Unit
			var distance = mine.global_position.distance_to(unit.global_position)
			if distance <= explosion_radius:
				unit.take_damage(explosion_damage)
				damaged_units += 1
	
	# Remove mine from tracking
	deployed_mines.erase(mine)
	
	# Visual effect (would add explosion particle effect here)
	mine.queue_free()
	
	Logger.info("EngineerUnit", "Engineer %s mine exploded, damaged %d units" % [unit_id, damaged_units])

func construct_turret(position: Vector3) -> bool:
	if not can_build():
		return false
	
	var distance = global_position.distance_to(position)
	if distance > repair_range:
		return false
	
	if energy < 40.0:
		return false
	
	# Create turret
	var turret = _create_turret(position)
	if turret:
		energy -= 40.0
		Logger.info("EngineerUnit", "Engineer %s constructed turret at %s" % [unit_id, position])
		return true
	
	return false

func _create_turret(position: Vector3) -> Node3D:
	# Create a simple turret node
	var turret = Node3D.new()
	turret.name = "Turret_%s" % randf()
	turret.position = position
	
	# Add visual representation
	var turret_visual = MeshInstance3D.new()
	turret_visual.mesh = CylinderMesh.new()
	turret_visual.mesh.top_radius = 0.8
	turret_visual.mesh.bottom_radius = 1.0
	turret_visual.mesh.height = 1.5
	
	var turret_material = StandardMaterial3D.new()
	turret_material.albedo_color = Color.GRAY
	turret_visual.material_override = turret_material
	
	turret.add_child(turret_visual)
	
	get_tree().current_scene.add_child(turret)
	return turret

func create_barrier(start_position: Vector3, end_position: Vector3) -> bool:
	if not can_build():
		return false
	
	if energy < 25.0:
		return false
	
	# Create barrier segments
	var barrier_segments = []
	var segment_count = 5
	
	for i in range(segment_count):
		var t = float(i) / (segment_count - 1)
		var segment_position = start_position.lerp(end_position, t)
		var segment = _create_barrier_segment(segment_position)
		if segment:
			barrier_segments.append(segment)
	
	if barrier_segments.size() > 0:
		energy -= 25.0
		Logger.info("EngineerUnit", "Engineer %s created barrier with %d segments" % [unit_id, barrier_segments.size()])
		return true
	
	return false

func _create_barrier_segment(position: Vector3) -> Node3D:
	var barrier = Node3D.new()
	barrier.name = "Barrier_%s" % randf()
	barrier.position = position
	
	# Add visual
	var barrier_visual = MeshInstance3D.new()
	barrier_visual.mesh = BoxMesh.new()
	barrier_visual.mesh.size = Vector3(2, 2, 0.5)
	
	var barrier_material = StandardMaterial3D.new()
	barrier_material.albedo_color = Color.BROWN
	barrier_visual.material_override = barrier_material
	
	barrier.add_child(barrier_visual)
	
	# Add collision
	var collision_body = StaticBody3D.new()
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = BoxShape3D.new()
	collision_shape.shape.size = Vector3(2, 2, 0.5)
	
	collision_body.add_child(collision_shape)
	barrier.add_child(collision_body)
	
	get_tree().current_scene.add_child(barrier)
	return barrier

func salvage_wreckage(wreckage: Node3D) -> bool:
	if not wreckage:
		return false
	
	var distance = global_position.distance_to(wreckage.global_position)
	if distance > repair_range:
		return false
	
	if energy < 10.0:
		return false
	
	# Salvage materials (restore energy)
	energy += 15.0
	energy = min(100.0, energy)
	
	# Remove wreckage
	wreckage.queue_free()
	
	Logger.info("EngineerUnit", "Engineer %s salvaged wreckage" % unit_id)
	return true

func hack_enemy_structure(target: Node3D) -> bool:
	if not target:
		return false
	
	var distance = global_position.distance_to(target.global_position)
	if distance > repair_range:
		return false
	
	if energy < 30.0:
		return false
	
	# Attempt to hack (success chance based on energy)
	var success_chance = min(0.8, energy / 100.0)
	if randf() < success_chance:
		energy -= 30.0
		Logger.info("EngineerUnit", "Engineer %s successfully hacked %s" % [unit_id, target.name])
		return true
	else:
		energy -= 15.0  # Partial energy cost on failure
		Logger.info("EngineerUnit", "Engineer %s failed to hack %s" % [unit_id, target.name])
		return false

func get_construction_options() -> Array[Dictionary]:
	# Return available construction options
	var options = []
	
	if energy >= 40.0:
		options.append({
			"type": "turret",
			"name": "Defense Turret",
			"cost": 40.0,
			"range": repair_range
		})
	
	if energy >= 25.0:
		options.append({
			"type": "barrier",
			"name": "Defensive Barrier",
			"cost": 25.0,
			"range": repair_range
		})
	
	if energy >= 20.0 and deployed_mines.size() < max_mines:
		options.append({
			"type": "mine",
			"name": "Explosive Mine",
			"cost": 20.0,
			"range": mine_deployment_range
		})
	
	return options

func get_repair_targets() -> Array[Node3D]:
	# Find nearby damaged structures
	var repair_targets = []
	
	# This would search for buildings, turrets, etc. that need repair
	# For now, return empty array
	
	return repair_targets

func emergency_repair_self() -> bool:
	if energy < 20.0:
		return false
	
	if get_health_percentage() >= 0.8:
		return false
	
	# Heal self
	heal(max_health * 0.3)
	energy -= 20.0
	
	# Visual effect
	modulate = Color(1.0, 1.2, 1.0, 1.0)
	await get_tree().create_timer(0.5).timeout
	modulate = Color.WHITE
	
	Logger.info("EngineerUnit", "Engineer %s performed emergency self-repair" % unit_id)
	return true

func _on_vision_body_entered(body: Node3D) -> void:
	super._on_vision_body_entered(body)
	
	# Engineer-specific: Look for things to repair or salvage
	if body.name.contains("Wreckage") or body.name.contains("Damaged"):
		Logger.debug("EngineerUnit", "Engineer %s spotted salvageable wreckage" % unit_id)

func get_utility_report() -> Dictionary:
	# Return status of engineer capabilities
	return {
		"unit_id": unit_id,
		"energy": energy,
		"can_build": can_build(),
		"can_repair": can_repair(),
		"deployed_mines": deployed_mines.size(),
		"max_mines": max_mines,
		"construction_options": get_construction_options(),
		"repair_targets": get_repair_targets().size()
	} 