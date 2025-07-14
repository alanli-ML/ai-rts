# TankUnit.gd
class_name TankUnit
extends Unit

# Tank-specific properties
var armor_bonus: float = 0.5  # Damage reduction
var shield_active: bool = false
var shield_cooldown: float = 10.0
var shield_duration: float = 5.0
var shield_timer: float = 0.0
var taunt_range: float = 15.0
var is_taunting: bool = false

func _ready() -> void:
	archetype = "tank"
	system_prompt = "You are a heavily armored tank unit. Your role is to absorb damage, protect allies, and hold strategic positions. You are slow but extremely durable. Use your bulk to block enemies and create safe zones for your team."
	
	# Call parent _ready
	super._ready()
	
	# Tank-specific setup
	_setup_tank_abilities()

func _setup_tank_abilities() -> void:
	# Tanks have high health and armor
	max_health = 200.0
	current_health = max_health
	
	# Slow movement
	speed = 5.0
	move_speed = 5.0
	
	# Short vision range but wide angle
	vision_range = 20.0
	vision_angle = 120.0
	
	# High damage at close range
	attack_range = 10.0
	attack_damage = 40.0
	
	# Update visual for tank
	_update_tank_visual()

func _update_tank_visual() -> void:
	if unit_model:
		# Make tank larger and more imposing
		unit_model.scale = Vector3(1.2, 1.2, 1.2)
		
		# Different color scheme
		var material = unit_model.material_override as StandardMaterial3D
		if material:
			if team_id == 1:
				material.albedo_color = Color.DARK_BLUE  # Dark blue for team 1
			else:
				material.albedo_color = Color.DARK_RED  # Dark red for team 2
			
			# Make material look more metallic
			material.metallic = 0.8
			material.roughness = 0.2

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Handle shield cooldown
	if shield_timer > 0:
		shield_timer -= delta
		if shield_timer <= 0 and shield_active:
			deactivate_shield()

func take_damage(damage: float) -> void:
	# Apply armor reduction
	var reduced_damage = damage * (1.0 - armor_bonus)
	
	# Additional shield reduction
	if shield_active:
		reduced_damage *= 0.5
	
	super.take_damage(reduced_damage)
	
	Logger.debug("TankUnit", "Tank %s took %s damage (reduced from %s)" % [unit_id, reduced_damage, damage])

func activate_shield() -> void:
	if shield_timer > 0:
		Logger.debug("TankUnit", "Tank %s shield on cooldown" % unit_id)
		return
	
	shield_active = true
	shield_timer = shield_duration
	
	# Visual feedback
	modulate = Color(0.8, 0.8, 1.2, 1.0)  # Slight blue tint
	
	Logger.info("TankUnit", "Tank %s activated shield" % unit_id)
	
	# Auto-deactivate after duration
	await get_tree().create_timer(shield_duration).timeout
	if shield_active:
		deactivate_shield()

func deactivate_shield() -> void:
	shield_active = false
	shield_timer = shield_cooldown
	
	# Remove visual feedback
	modulate = Color.WHITE
	
	Logger.info("TankUnit", "Tank %s shield deactivated" % unit_id)

func taunt_enemies() -> void:
	# Force nearby enemies to target this tank
	is_taunting = true
	
	var nearby_enemies = get_tree().get_nodes_in_group("units")
	var taunted_count = 0
	
	for node in nearby_enemies:
		if node is Unit:
			var unit = node as Unit
			if unit.is_enemy_of(self):
				var distance = global_position.distance_to(unit.global_position)
				if distance <= taunt_range:
					_taunt_enemy(unit)
					taunted_count += 1
	
	Logger.info("TankUnit", "Tank %s taunted %d enemies" % [unit_id, taunted_count])
	
	# Taunt lasts for a few seconds
	await get_tree().create_timer(3.0).timeout
	is_taunting = false

func _taunt_enemy(enemy: Unit) -> void:
	# This would make the enemy prioritize attacking this tank
	# For now, we'll just log it
	Logger.debug("TankUnit", "Tank %s taunted enemy %s" % [unit_id, enemy.unit_id])

func create_defensive_position(position: Vector3) -> void:
	# Tank takes a defensive stance at a position
	move_to(position)
	
	# Wait until we reach the position
	await get_tree().create_timer(1.0).timeout
	
	# Activate defensive bonuses
	var original_armor = armor_bonus
	armor_bonus = 0.7  # Increased damage reduction
	
	# Slow movement while in defensive position
	move_speed *= 0.5
	
	Logger.info("TankUnit", "Tank %s established defensive position at %s" % [unit_id, position])
	
	# Maintain defensive position for duration
	await get_tree().create_timer(10.0).timeout
	
	# Restore normal state
	armor_bonus = original_armor
	move_speed = speed
	
	Logger.debug("TankUnit", "Tank %s ended defensive position" % unit_id)

func intercept_enemy(enemy: Unit) -> void:
	# Tank moves to intercept an enemy
	if not enemy or enemy.is_dead:
		return
	
	var intercept_position = enemy.global_position + (enemy.velocity * 2.0)
	move_to(intercept_position)
	
	Logger.info("TankUnit", "Tank %s intercepting enemy %s" % [unit_id, enemy.unit_id])

func protect_ally(ally: Unit) -> void:
	# Tank positions itself to protect an ally
	if not ally or ally.is_dead or not ally.is_ally_of(self):
		return
	
	# Move to position between ally and closest enemy
	var closest_enemy = _find_closest_enemy_to_ally(ally)
	if closest_enemy:
		var protection_position = ally.global_position + (ally.global_position - closest_enemy.global_position).normalized() * 3.0
		move_to(protection_position)
		
		Logger.info("TankUnit", "Tank %s protecting ally %s" % [unit_id, ally.unit_id])

func _find_closest_enemy_to_ally(ally: Unit) -> Unit:
	var closest_enemy: Unit = null
	var closest_distance = INF
	
	for enemy in visible_enemies:
		var distance = ally.global_position.distance_to(enemy.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_enemy = enemy
	
	return closest_enemy

func slam_attack() -> void:
	# Tank performs a powerful area attack
	var slam_radius = 5.0
	var slam_damage = attack_damage * 1.5
	
	# Find all enemies in range
	var enemies_in_range = get_tree().get_nodes_in_group("units")
	var hit_count = 0
	
	for node in enemies_in_range:
		if node is Unit:
			var unit = node as Unit
			if unit.is_enemy_of(self):
				var distance = global_position.distance_to(unit.global_position)
				if distance <= slam_radius:
					unit.take_damage(slam_damage)
					hit_count += 1
	
	Logger.info("TankUnit", "Tank %s slam attack hit %d enemies" % [unit_id, hit_count])
	
	# Visual effect (screen shake would go here)
	# Add cooldown for slam attack
	await get_tree().create_timer(8.0).timeout

func get_threat_level() -> float:
	# Tanks are high-threat targets due to their role
	var base_threat = 0.7
	
	# Higher threat if shielded or taunting
	if shield_active:
		base_threat += 0.2
	if is_taunting:
		base_threat += 0.3
	
	return base_threat

func _on_vision_body_entered(body: Node3D) -> void:
	super._on_vision_body_entered(body)
	
	# Tank-specific: Evaluate threats
	if body is Unit:
		var unit = body as Unit
		if unit.is_enemy_of(self):
			_evaluate_threat(unit)

func _evaluate_threat(enemy: Unit) -> void:
	# Tank assesses enemy threat level
	var threat_level = "low"
	
	if enemy.archetype == "sniper":
		threat_level = "high"
	elif enemy.archetype == "tank":
		threat_level = "medium"
	elif enemy.get_health_percentage() < 0.3:
		threat_level = "low"
	
	Logger.debug("TankUnit", "Tank %s assessed %s as %s threat" % [unit_id, enemy.unit_id, threat_level])

func can_block_path_to(target: Vector3) -> bool:
	# Check if tank can position itself to block a path
	var distance_to_target = global_position.distance_to(target)
	return distance_to_target <= move_speed * 3.0  # Can reach in 3 seconds 