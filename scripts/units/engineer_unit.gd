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

# Enhanced abilities
var hijack_range: float = 8.0
var hijack_duration: float = 5.0
var hijack_cooldown: float = 20.0
var hijack_cooldown_timer: float = 0.0
var is_hijacking: bool = false
var hijack_target: Node3D = null
var hijack_timer: float = 0.0

# Mine laying system
var mine_type: String = "proximity"
var mine_cooldown: float = 3.0
var mine_cooldown_timer: float = 0.0
var mine_damage: float = 50.0
var mine_blast_radius: float = 8.0

# Turret building system
var turret_build_time: float = 8.0
var turret_cooldown: float = 15.0
var turret_cooldown_timer: float = 0.0
var built_turrets: Array[Node3D] = []
var max_turrets: int = 2

# Repair system enhancement
var repair_cooldown: float = 2.0
var repair_cooldown_timer: float = 0.0
var repair_amount: float = 20.0
var can_repair_units: bool = true
var can_repair_buildings: bool = true

# Construction queue
var construction_queue: Array[Dictionary] = []
var construction_materials: Dictionary = {
	"metal": 100.0,
	"energy": 50.0
}

# Visual indicators
var build_indicator: Node3D
var repair_indicator: Node3D
var hijack_indicator: Node3D

# Signals
signal mine_deployed(position: Vector3, mine_type: String)
signal spire_hijacked(spire: Node3D, success: bool)
signal turret_built(position: Vector3, turret_type: String)
signal repair_completed(target: Node3D, health_restored: float)
signal construction_started(project: Dictionary)
signal construction_completed(project: Dictionary)

func _ready() -> void:
	archetype = "engineer"
	system_prompt = "You are a versatile engineer unit. Your role is to build structures, repair damaged buildings, deploy tactical equipment, and perform sabotage operations. You can fight when needed but excel at support, utility, and construction tasks."
	
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
	movement_speed = 8.0
	
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
	
	# Create visual indicators
	_create_visual_indicators()
	
	# Update visual for engineer
	_update_engineer_visual()

func _create_visual_indicators() -> void:
	"""Create visual indicators for engineer abilities"""
	# Build indicator
	build_indicator = MeshInstance3D.new()
	build_indicator.name = "BuildIndicator"
	build_indicator.mesh = BoxMesh.new()
	build_indicator.mesh.size = Vector3(0.5, 0.5, 0.5)
	build_indicator.position = Vector3(0, 2, 0)
	build_indicator.visible = false
	
	var build_material = StandardMaterial3D.new()
	build_material.albedo_color = Color.BLUE
	build_material.emission_enabled = true
	build_material.emission = Color.BLUE * 0.3
	build_indicator.material_override = build_material
	
	add_child(build_indicator)
	
	# Repair indicator
	repair_indicator = MeshInstance3D.new()
	repair_indicator.name = "RepairIndicator"
	repair_indicator.mesh = CylinderMesh.new()
	repair_indicator.mesh.height = 0.2
	repair_indicator.mesh.top_radius = 0.8
	repair_indicator.mesh.bottom_radius = 0.8
	repair_indicator.position = Vector3(0, 0.1, 0)
	repair_indicator.visible = false
	
	var repair_material = StandardMaterial3D.new()
	repair_material.albedo_color = Color.GREEN
	repair_material.flags_transparent = true
	repair_material.albedo_color.a = 0.4
	repair_indicator.material_override = repair_material
	
	add_child(repair_indicator)
	
	# Hijack indicator
	hijack_indicator = MeshInstance3D.new()
	hijack_indicator.name = "HijackIndicator"
	hijack_indicator.mesh = SphereMesh.new()
	hijack_indicator.mesh.radius = 0.5
	hijack_indicator.position = Vector3(0, 2.5, 0)
	hijack_indicator.visible = false
	
	var hijack_material = StandardMaterial3D.new()
	hijack_material.albedo_color = Color.RED
	hijack_material.emission_enabled = true
	hijack_material.emission = Color.RED * 0.5
	hijack_indicator.material_override = hijack_material
	
	add_child(hijack_indicator)

func _update_engineer_visual() -> void:
	# Find mesh instance for visual updates
	var mesh_instance = find_child("UnitMesh") as MeshInstance3D
	if mesh_instance:
		# Make engineer look more robust
		mesh_instance.scale = Vector3(1.1, 1.0, 1.1)
		
		# Different color scheme
		var material = mesh_instance.material_override as StandardMaterial3D
		if material:
			if team_id == 1:
				material.albedo_color = Color.BLUE  # Blue for team 1
			else:
				material.albedo_color = Color.MAGENTA  # Magenta for team 2

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Update ability timers
	_update_ability_timers(delta)
	
	# Handle building
	if is_building and current_build_target:
		_handle_building(delta)
	
	# Handle repairing
	if is_repairing and current_repair_target:
		_handle_repairing(delta)
	
	# Handle hijacking
	if is_hijacking and hijack_target:
		_handle_hijacking(delta)

func _update_ability_timers(delta: float) -> void:
	"""Update cooldown timers for abilities"""
	if hijack_cooldown_timer > 0:
		hijack_cooldown_timer -= delta
	
	if mine_cooldown_timer > 0:
		mine_cooldown_timer -= delta
	
	if turret_cooldown_timer > 0:
		turret_cooldown_timer -= delta
	
	if repair_cooldown_timer > 0:
		repair_cooldown_timer -= delta
	
	if hijack_timer > 0:
		hijack_timer -= delta
		if hijack_timer <= 0:
			_complete_hijack()

func _handle_building(delta: float) -> void:
	"""Handle building process"""
	if not current_build_target:
		is_building = false
		return
	
	# Building progress logic would go here
	# For now, just show visual indicator
	if build_indicator:
		build_indicator.visible = true
		var tween = create_tween()
		tween.tween_property(build_indicator, "rotation", build_indicator.rotation + Vector3(0, PI * 2, 0), 1.0)

func _handle_repairing(delta: float) -> void:
	"""Handle repair process"""
	if not current_repair_target:
		is_repairing = false
		return
	
	# Repair progress
	var repair_this_frame = repair_rate * delta
	
	# Apply repair
	if current_repair_target.has_method("repair"):
		current_repair_target.repair(repair_this_frame)
	
	# Energy cost
	energy -= repair_energy_cost * delta
	
	# Visual feedback
	if repair_indicator:
		repair_indicator.visible = true
		var tween = create_tween()
		tween.tween_property(repair_indicator, "scale", Vector3(1.1, 1.0, 1.1), 0.3)
		tween.tween_property(repair_indicator, "scale", Vector3(1.0, 1.0, 1.0), 0.3)

func _handle_hijacking(delta: float) -> void:
	"""Handle hijacking process"""
	if not hijack_target:
		is_hijacking = false
		return
	
	# Visual feedback during hijacking
	if hijack_indicator:
		hijack_indicator.visible = true
		var progress = 1.0 - (hijack_timer / hijack_duration)
		hijack_indicator.scale = Vector3(progress, progress, progress)

# Enhanced Engineer Abilities
func lay_mines(position: Vector3, count: int = 1) -> bool:
	"""Deploy mines at specified position"""
	if mine_cooldown_timer > 0:
		print("Engineer %s: Mine laying on cooldown" % unit_id)
		return false
	
	if deployed_mines.size() >= max_mines:
		print("Engineer %s: Maximum mines deployed" % unit_id)
		return false
	
	if energy < 20.0:
		print("Engineer %s: Not enough energy for mine deployment" % unit_id)
		return false
	
	var distance = global_position.distance_to(position)
	if distance > mine_deployment_range:
		print("Engineer %s: Mine position too far" % unit_id)
		return false
	
	# Deploy mines
	for i in range(count):
		if deployed_mines.size() >= max_mines:
			break
		
		var mine_position = position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		var mine = _create_mine(mine_position)
		deployed_mines.append(mine)
		
		mine_deployed.emit(mine_position, mine_type)
		print("Engineer %s: Mine deployed at %s" % [unit_id, mine_position])
	
	# Set cooldown
	mine_cooldown_timer = mine_cooldown
	
	# Energy cost
	energy -= 15.0 * count
	
	return true

func hijack_spire(spire: Node3D) -> bool:
	"""Hijack enemy spire"""
	if not spire or hijack_cooldown_timer > 0 or is_hijacking:
		print("Engineer %s: Hijack on cooldown or already hijacking" % unit_id)
		return false
	
	if energy < 50.0:
		print("Engineer %s: Not enough energy for hijacking" % unit_id)
		return false
	
	var distance = global_position.distance_to(spire.global_position)
	if distance > hijack_range:
		print("Engineer %s: Spire too far to hijack" % unit_id)
		return false
	
	# Check if spire is enemy
	if spire.has_method("get") and spire.get("team_id") == team_id:
		print("Engineer %s: Cannot hijack allied spire" % unit_id)
		return false
	
	# Start hijacking process
	is_hijacking = true
	hijack_target = spire
	hijack_timer = hijack_duration
	
	# Move to spire if not close enough
	if distance > 3.0:
		move_to(spire.global_position)
	
	print("Engineer %s: Starting hijack of spire at %s" % [unit_id, spire.global_position])
	return true

func repair_unit(target: Unit) -> bool:
	"""Repair target unit"""
	if not target or repair_cooldown_timer > 0:
		print("Engineer %s: Repair on cooldown or invalid target" % unit_id)
		return false
	
	if not can_repair_units:
		print("Engineer %s: Cannot repair units" % unit_id)
		return false
	
	if target.team_id != team_id:
		print("Engineer %s: Cannot repair enemy unit" % unit_id)
		return false
	
	if target.current_health >= target.max_health:
		print("Engineer %s: Target already at full health" % unit_id)
		return false
	
	var distance = global_position.distance_to(target.global_position)
	if distance > repair_range:
		print("Engineer %s: Target too far to repair" % unit_id)
		return false
	
	if energy < 25.0:
		print("Engineer %s: Not enough energy for repair" % unit_id)
		return false
	
	# Perform repair
	var health_restored = min(repair_amount, target.max_health - target.current_health)
	target.heal(health_restored)
	
	# Energy cost
	energy -= 20.0
	
	# Set cooldown
	repair_cooldown_timer = repair_cooldown
	
	# Visual effect
	_create_repair_effect(target.global_position)
	
	print("Engineer %s: Repaired %s for %.1f health" % [unit_id, target.unit_id, health_restored])
	repair_completed.emit(target, health_restored)
	
	return true

func build_turret(position: Vector3, turret_type: String = "basic") -> bool:
	"""Build defensive turret"""
	if turret_cooldown_timer > 0:
		print("Engineer %s: Turret building on cooldown" % unit_id)
		return false
	
	if built_turrets.size() >= max_turrets:
		print("Engineer %s: Maximum turrets built" % unit_id)
		return false
	
	if energy < 60.0:
		print("Engineer %s: Not enough energy for turret construction" % unit_id)
		return false
	
	var distance = global_position.distance_to(position)
	if distance > 15.0:
		print("Engineer %s: Turret position too far" % unit_id)
		return false
	
	# Check if position is valid
	if not _is_valid_build_position(position):
		print("Engineer %s: Invalid build position" % unit_id)
		return false
	
	# Start building process
	is_building = true
	
	# Move to build position
	move_to(position)
	
	# Wait for positioning
	await get_tree().create_timer(2.0).timeout
	
	# Build turret
	var turret = _create_turret(position, turret_type)
	built_turrets.append(turret)
	
	# Set cooldown
	turret_cooldown_timer = turret_cooldown
	
	# Energy cost
	energy -= 50.0
	
	is_building = false
	
	print("Engineer %s: Built %s turret at %s" % [unit_id, turret_type, position])
	turret_built.emit(position, turret_type)
	
	return true

func start_construction(project: Dictionary) -> bool:
	"""Start construction project"""
	if is_building:
		print("Engineer %s: Already building" % unit_id)
		return false
	
	var required_materials = project.get("materials", {})
	if not _has_required_materials(required_materials):
		print("Engineer %s: Insufficient materials for construction" % unit_id)
		return false
	
	# Add to construction queue
	construction_queue.append(project)
	
	# Start building if not already building
	if not is_building:
		_start_next_construction()
	
	construction_started.emit(project)
	return true

func _complete_hijack() -> void:
	"""Complete hijacking process"""
	if not is_hijacking or not hijack_target:
		return
	
	var success = true
	
	# Attempt to hijack the spire
	if hijack_target.has_method("change_team"):
		hijack_target.change_team(team_id)
		print("Engineer %s: Successfully hijacked spire" % unit_id)
	else:
		success = false
		print("Engineer %s: Failed to hijack spire" % unit_id)
	
	# Clean up
	is_hijacking = false
	hijack_target = null
	hijack_timer = 0.0
	
	# Set cooldown
	hijack_cooldown_timer = hijack_cooldown
	
	# Energy cost
	energy -= 40.0
	
	# Hide indicator
	if hijack_indicator:
		hijack_indicator.visible = false
	
	spire_hijacked.emit(hijack_target, success)

func _create_mine(position: Vector3) -> Node3D:
	"""Create mine at position"""
	var mine = MeshInstance3D.new()
	mine.name = "Mine"
	mine.mesh = SphereMesh.new()
	mine.mesh.radius = 0.3
	mine.mesh.height = 0.2
	mine.position = position
	
	# Mine material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.DARK_GRAY
	material.metallic = 0.8
	material.roughness = 0.2
	mine.material_override = material
	
	# Add mine to scene
	get_tree().current_scene.add_child(mine)
	
	# Set up mine behavior
	mine.set_meta("mine_damage", mine_damage)
	mine.set_meta("blast_radius", mine_blast_radius)
	mine.set_meta("owner_team", team_id)
	mine.set_meta("mine_type", mine_type)
	
	return mine

func _create_turret(position: Vector3, turret_type: String) -> Node3D:
	"""Create turret at position"""
	var turret = MeshInstance3D.new()
	turret.name = "Turret"
	turret.mesh = CylinderMesh.new()
	turret.mesh.height = 2.0
	turret.mesh.top_radius = 0.8
	turret.mesh.bottom_radius = 1.0
	turret.position = position
	
	# Turret material
	var material = StandardMaterial3D.new()
	if team_id == 1:
		material.albedo_color = Color.BLUE
	else:
		material.albedo_color = Color.RED
	material.metallic = 0.6
	material.roughness = 0.3
	turret.material_override = material
	
	# Add turret to scene
	get_tree().current_scene.add_child(turret)
	
	# Set up turret behavior
	turret.set_meta("turret_type", turret_type)
	turret.set_meta("owner_team", team_id)
	turret.set_meta("attack_range", 25.0)
	turret.set_meta("attack_damage", 30.0)
	turret.set_meta("health", 100.0)
	turret.set_meta("max_health", 100.0)
	
	return turret

func _create_repair_effect(position: Vector3) -> void:
	"""Create visual repair effect"""
	var effect = MeshInstance3D.new()
	effect.name = "RepairEffect"
	effect.mesh = SphereMesh.new()
	effect.mesh.radius = 1.0
	effect.position = position
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.GREEN
	material.flags_transparent = true
	material.albedo_color.a = 0.3
	material.emission_enabled = true
	material.emission = Color.GREEN * 0.5
	effect.material_override = material
	
	get_tree().current_scene.add_child(effect)
	
	# Animate effect
	var tween = create_tween()
	tween.tween_property(effect, "scale", Vector3(2.0, 2.0, 2.0), 0.5)
	tween.parallel().tween_property(effect, "material_override:albedo_color:a", 0.0, 0.5)
	tween.tween_callback(func(): effect.queue_free())

func _is_valid_build_position(position: Vector3) -> bool:
	"""Check if position is valid for building"""
	# Check if position is too close to other buildings
	var buildings = get_tree().get_nodes_in_group("buildings")
	for building in buildings:
		if building.global_position.distance_to(position) < 10.0:
			return false
	
	# Check if position is in valid terrain
	# This would integrate with terrain system
	return true

func _has_required_materials(required: Dictionary) -> bool:
	"""Check if engineer has required materials"""
	for material in required:
		if construction_materials.get(material, 0) < required[material]:
			return false
	return true

func _start_next_construction() -> void:
	"""Start next construction project in queue"""
	if construction_queue.is_empty() or is_building:
		return
	
	var project = construction_queue.pop_front()
	is_building = true
	
	# This would implement actual construction logic
	print("Engineer %s: Starting construction of %s" % [unit_id, project.get("name", "Unknown")])

func _consume_materials(required: Dictionary) -> void:
	"""Consume materials from inventory"""
	for material in required:
		construction_materials[material] -= required[material]

func detonate_mine(mine: Node3D) -> void:
	"""Detonate specific mine"""
	if mine in deployed_mines:
		deployed_mines.erase(mine)
		
		# Create explosion effect
		_create_explosion_effect(mine.global_position)
		
		# Damage units in blast radius
		var damage = mine.get_meta("mine_damage", mine_damage)
		var radius = mine.get_meta("blast_radius", mine_blast_radius)
		
		var units = get_tree().get_nodes_in_group("units")
		for unit in units:
			var distance = mine.global_position.distance_to(unit.global_position)
			if distance <= radius:
				var damage_amount = damage * (1.0 - distance / radius)
				unit.take_damage(damage_amount)
		
		# Remove mine from scene
		mine.queue_free()
		
		print("Engineer %s: Mine detonated at %s" % [unit_id, mine.global_position])

func _create_explosion_effect(position: Vector3) -> void:
	"""Create explosion visual effect"""
	var explosion = MeshInstance3D.new()
	explosion.name = "Explosion"
	explosion.mesh = SphereMesh.new()
	explosion.mesh.radius = 0.5
	explosion.position = position
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.ORANGE
	material.emission_enabled = true
	material.emission = Color.ORANGE * 2.0
	explosion.material_override = material
	
	get_tree().current_scene.add_child(explosion)
	
	# Animate explosion
	var tween = create_tween()
	tween.tween_property(explosion, "scale", Vector3(5.0, 5.0, 5.0), 0.3)
	tween.parallel().tween_property(explosion, "material_override:albedo_color:a", 0.0, 0.3)
	tween.tween_callback(func(): explosion.queue_free())

# Public ability interface for plan executor
func get_available_abilities() -> Array[String]:
	"""Get list of available abilities"""
	var abilities = []
	
	if mine_cooldown_timer <= 0 and deployed_mines.size() < max_mines:
		abilities.append("lay_mines")
	
	if hijack_cooldown_timer <= 0:
		abilities.append("hijack_spire")
	
	if repair_cooldown_timer <= 0:
		abilities.append("repair")
	
	if turret_cooldown_timer <= 0 and built_turrets.size() < max_turrets:
		abilities.append("build_turret")
	
	abilities.append("start_construction")
	
	return abilities

func get_ability_cooldown(ability: String) -> float:
	"""Get cooldown time for specific ability"""
	match ability:
		"lay_mines":
			return mine_cooldown_timer
		"hijack_spire":
			return hijack_cooldown_timer
		"repair":
			return repair_cooldown_timer
		"build_turret":
			return turret_cooldown_timer
		_:
			return 0.0

func is_ability_available(ability: String) -> bool:
	"""Check if ability is available"""
	return get_ability_cooldown(ability) <= 0.0

func get_construction_status() -> Dictionary:
	"""Get current construction status"""
	return {
		"building": is_building,
		"queue_size": construction_queue.size(),
		"materials": construction_materials
	}

func get_deployed_mines() -> Array[Node3D]:
	"""Get list of deployed mines"""
	return deployed_mines.duplicate()

func get_built_turrets() -> Array[Node3D]:
	"""Get list of built turrets"""
	return built_turrets.duplicate() 