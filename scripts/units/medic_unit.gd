# MedicUnit.gd
class_name MedicUnit
extends Unit

# Medic-specific properties
var heal_range: float = 15.0
var heal_rate: float = 10.0
var heal_cooldown: float = 2.0
var last_heal_time: float = 0.0
var is_healing: bool = false
var current_heal_target: Unit = null
var heal_energy_cost: float = 5.0
var aoe_heal_radius: float = 8.0
var aoe_heal_cooldown: float = 15.0
var last_aoe_heal_time: float = 0.0
var shield_boost_duration: float = 10.0
var shield_boost_amount: float = 0.3

func _ready() -> void:
	archetype = "medic"
	system_prompt = "You are a support medic unit. Your role is to heal and support allies. You cannot attack enemies but can provide critical healing and buffs. Stay behind cover and prioritize keeping your team alive."
	
	# Call parent _ready
	super._ready()
	
	# Medic-specific setup
	_setup_medic_abilities()

func _setup_medic_abilities() -> void:
	# Medics have moderate stats but no attack
	max_health = 100.0
	current_health = max_health
	
	# Medium movement speed
	speed = 10.0
	move_speed = 10.0
	
	# Medium vision range
	vision_range = 30.0
	vision_angle = 120.0
	
	# No attack capability
	attack_range = 0.0
	attack_damage = 0.0
	
	# Set heal range from config
	var stats = ConfigManager.get_unit_stats("medic")
	if not stats.is_empty():
		heal_range = stats.heal_range
		heal_rate = stats.heal_rate
	
	# Update visual for medic
	_update_medic_visual()

func _update_medic_visual() -> void:
	if unit_model:
		# Keep medic normal size
		unit_model.scale = Vector3(1.0, 1.0, 1.0)
		
		# Different color scheme
		var material = unit_model.material_override as StandardMaterial3D
		if material:
			if team_id == 1:
				material.albedo_color = Color.WHITE  # White/medical for team 1
			else:
				material.albedo_color = Color.YELLOW  # Yellow for team 2
			
			# Make material clean and bright
			material.metallic = 0.0
			material.roughness = 0.1
			material.emission_enabled = true
			material.emission = Color(0.1, 0.1, 0.1)  # Slight glow

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Update heal cooldowns
	if last_heal_time > 0:
		last_heal_time -= delta
	
	if last_aoe_heal_time > 0:
		last_aoe_heal_time -= delta
	
	# Continue healing current target if valid
	if is_healing and current_heal_target:
		_continue_healing(delta)

func _continue_healing(delta: float) -> void:
	if not current_heal_target or current_heal_target.is_dead:
		stop_healing()
		return
	
	var distance = global_position.distance_to(current_heal_target.global_position)
	if distance > heal_range:
		stop_healing()
		return
	
	# Check if we have enough energy
	if energy < heal_energy_cost * delta:
		stop_healing()
		return
	
	# Heal target
	current_heal_target.heal(heal_rate * delta)
	energy -= heal_energy_cost * delta
	
	# Visual feedback
	_show_healing_effect()

func can_heal() -> bool:
	return last_heal_time <= 0.0 and energy >= heal_energy_cost

func start_healing(target: Unit) -> bool:
	if not target or target.is_dead or not target.is_ally_of(self):
		return false
	
	if not can_heal():
		Logger.debug("MedicUnit", "Medic %s cannot heal (on cooldown or no energy)" % unit_id)
		return false
	
	var distance = global_position.distance_to(target.global_position)
	if distance > heal_range:
		Logger.debug("MedicUnit", "Medic %s heal target out of range" % unit_id)
		return false
	
	if target.current_health >= target.max_health:
		Logger.debug("MedicUnit", "Medic %s target already at full health" % unit_id)
		return false
	
	# Start healing
	is_healing = true
	current_heal_target = target
	last_heal_time = heal_cooldown
	
	Logger.info("MedicUnit", "Medic %s started healing %s" % [unit_id, target.unit_id])
	return true

func stop_healing() -> void:
	is_healing = false
	current_heal_target = null
	Logger.debug("MedicUnit", "Medic %s stopped healing" % unit_id)

func heal_target(target: Unit) -> bool:
	# One-time heal instead of continuous
	if not target or target.is_dead or not target.is_ally_of(self):
		return false
	
	if not can_heal():
		return false
	
	var distance = global_position.distance_to(target.global_position)
	if distance > heal_range:
		return false
	
	if target.current_health >= target.max_health:
		return false
	
	# Apply healing
	target.heal(heal_rate)
	energy -= heal_energy_cost
	last_heal_time = heal_cooldown
	
	# Visual effect
	_show_healing_effect()
	
	Logger.info("MedicUnit", "Medic %s healed %s for %s HP" % [unit_id, target.unit_id, heal_rate])
	return true

func _show_healing_effect() -> void:
	# Visual effect for healing
	modulate = Color(0.8, 1.2, 0.8, 1.0)  # Green tint
	
	# Restore after brief effect
	await get_tree().create_timer(0.2).timeout
	modulate = Color.WHITE

func aoe_heal() -> int:
	# Heal all allies in radius
	if last_aoe_heal_time > 0:
		Logger.debug("MedicUnit", "Medic %s AOE heal on cooldown" % unit_id)
		return 0
	
	if energy < heal_energy_cost * 3:
		Logger.debug("MedicUnit", "Medic %s insufficient energy for AOE heal" % unit_id)
		return 0
	
	var healed_count = 0
	var nearby_allies = get_tree().get_nodes_in_group("units")
	
	for node in nearby_allies:
		if node is Unit:
			var unit = node as Unit
			if unit.is_ally_of(self) and unit != self:
				var distance = global_position.distance_to(unit.global_position)
				if distance <= aoe_heal_radius:
					if unit.current_health < unit.max_health:
						unit.heal(heal_rate * 0.7)  # Reduced AOE healing
						healed_count += 1
	
	if healed_count > 0:
		energy -= heal_energy_cost * 3
		last_aoe_heal_time = aoe_heal_cooldown
		
		# Visual effect
		_show_aoe_heal_effect()
		
		Logger.info("MedicUnit", "Medic %s AOE healed %d allies" % [unit_id, healed_count])
	
	return healed_count

func _show_aoe_heal_effect() -> void:
	# Visual effect for AOE healing
	modulate = Color(0.6, 1.4, 0.6, 1.0)  # Bright green tint
	
	# Restore after effect
	await get_tree().create_timer(0.5).timeout
	modulate = Color.WHITE

func find_healing_target() -> Unit:
	# Find the best ally to heal
	var best_target: Unit = null
	var best_priority = 0.0
	
	for ally in visible_allies:
		if ally.current_health >= ally.max_health:
			continue
		
		var distance = global_position.distance_to(ally.global_position)
		if distance > heal_range:
			continue
		
		var priority = _calculate_heal_priority(ally)
		if priority > best_priority:
			best_priority = priority
			best_target = ally
	
	return best_target

func _calculate_heal_priority(ally: Unit) -> float:
	var priority = 0.0
	
	# Prioritize based on health percentage (lower = higher priority)
	var health_pct = ally.get_health_percentage()
	priority += (1.0 - health_pct) * 100.0
	
	# Prioritize based on archetype
	match ally.archetype:
		"tank":
			priority += 50.0  # High priority for tanks
		"medic":
			priority += 40.0  # High priority for other medics
		"engineer":
			priority += 30.0  # Medium priority
		"sniper":
			priority += 20.0  # Medium priority
		"scout":
			priority += 10.0  # Lower priority
	
	# Prioritize closer allies
	var distance = global_position.distance_to(ally.global_position)
	priority += (heal_range - distance) * 2.0
	
	return priority

func provide_shield_boost(target: Unit) -> bool:
	# Provide temporary damage resistance to an ally
	if not target or target.is_dead or not target.is_ally_of(self):
		return false
	
	if energy < 20.0:
		return false
	
	# Apply shield boost (would modify target's damage resistance)
	energy -= 20.0
	
	# Visual effect on target
	target.modulate = Color(0.8, 0.8, 1.2, 1.0)  # Blue tint
	
	Logger.info("MedicUnit", "Medic %s provided shield boost to %s" % [unit_id, target.unit_id])
	
	# Remove boost after duration
	await get_tree().create_timer(shield_boost_duration).timeout
	target.modulate = Color.WHITE
	
	return true

func emergency_heal(target: Unit) -> bool:
	# Powerful heal that costs a lot of energy
	if not target or target.is_dead or not target.is_ally_of(self):
		return false
	
	if energy < 30.0:
		return false
	
	var distance = global_position.distance_to(target.global_position)
	if distance > heal_range * 1.5:  # Slightly extended range
		return false
	
	# Powerful heal
	target.heal(heal_rate * 3.0)
	energy -= 30.0
	
	# Long cooldown
	last_heal_time = heal_cooldown * 2.0
	
	# Strong visual effect
	target.modulate = Color(1.0, 1.4, 1.0, 1.0)  # Bright green
	await get_tree().create_timer(1.0).timeout
	target.modulate = Color.WHITE
	
	Logger.info("MedicUnit", "Medic %s emergency healed %s" % [unit_id, target.unit_id])
	return true

func retreat_to_safety() -> void:
	# Move to a safe position away from enemies
	if visible_enemies.size() > 0:
		var retreat_direction = Vector3.ZERO
		
		# Calculate direction away from all enemies
		for enemy in visible_enemies:
			var direction = (global_position - enemy.global_position).normalized()
			retreat_direction += direction
		
		retreat_direction = retreat_direction.normalized()
		
		# Find allies to retreat towards
		var closest_ally = _find_closest_ally()
		if closest_ally:
			var ally_direction = (closest_ally.global_position - global_position).normalized()
			retreat_direction = (retreat_direction + ally_direction * 0.5).normalized()
		
		var retreat_position = global_position + retreat_direction * 20.0
		move_to(retreat_position)
		
		Logger.info("MedicUnit", "Medic %s retreating to safety" % unit_id)

func _find_closest_ally() -> Unit:
	var closest_ally: Unit = null
	var closest_distance = INF
	
	for ally in visible_allies:
		var distance = global_position.distance_to(ally.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_ally = ally
	
	return closest_ally

func get_triage_report() -> Dictionary:
	# Return status of all visible allies
	var report = {
		"medic_id": unit_id,
		"energy": energy,
		"can_heal": can_heal(),
		"can_aoe_heal": last_aoe_heal_time <= 0.0,
		"allies": []
	}
	
	for ally in visible_allies:
		report.allies.append({
			"unit_id": ally.unit_id,
			"archetype": ally.archetype,
			"health_pct": ally.get_health_percentage(),
			"distance": global_position.distance_to(ally.global_position),
			"priority": _calculate_heal_priority(ally)
		})
	
	return report

func _on_vision_body_entered(body: Node3D) -> void:
	super._on_vision_body_entered(body)
	
	# Medic-specific: Check if ally needs healing
	if body is Unit:
		var unit = body as Unit
		if unit.is_ally_of(self) and unit.get_health_percentage() < 0.5:
			Logger.debug("MedicUnit", "Medic %s spotted wounded ally %s" % [unit_id, unit.unit_id])

func attack_target(_target: Unit) -> void:
	# Medics cannot attack
	Logger.debug("MedicUnit", "Medic %s cannot attack (medic archetype)" % unit_id)

func take_damage(damage: float) -> void:
	# Medics take normal damage but call for help
	super.take_damage(damage)
	
	if get_health_percentage() < 0.5:
		Logger.warning("MedicUnit", "Medic %s is under attack and needs protection!" % unit_id)
		# Signal for help could go here 