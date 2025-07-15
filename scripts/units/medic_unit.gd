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

# Enhanced abilities
var emergency_heal_amount: float = 50.0
var emergency_heal_cooldown: float = 30.0
var emergency_heal_cooldown_timer: float = 0.0

# Shield system
var shield_cooldown: float = 8.0
var shield_cooldown_timer: float = 0.0
var shield_strength: float = 30.0
var shield_duration: float = 15.0
var active_shields: Dictionary = {}  # unit_id -> shield_data

# Revive system
var revive_range: float = 5.0
var revive_duration: float = 8.0
var revive_cooldown: float = 45.0
var revive_cooldown_timer: float = 0.0
var is_reviving: bool = false
var revive_target: Unit = null
var revive_timer: float = 0.0

# Buff system
var buff_duration: float = 20.0
var buff_cooldown: float = 25.0
var buff_cooldown_timer: float = 0.0
var active_buffs: Dictionary = {}  # unit_id -> buff_data

# Triage system
var triage_patients: Array[Unit] = []
var auto_heal_enabled: bool = true
var heal_priority_threshold: float = 0.5  # Below 50% health gets priority

# Medical supplies
var medical_supplies: float = 100.0
var max_medical_supplies: float = 100.0
var supply_regeneration_rate: float = 2.0

# Visual indicators
var heal_indicator: Node3D
var shield_indicator: Node3D
var revive_indicator: Node3D

# Signals
signal unit_healed(target: Unit, amount: float)
signal unit_shielded(target: Unit, shield_amount: float)
signal unit_revived(target: Unit, success: bool)
signal buff_applied(target: Unit, buff_type: String, duration: float)
signal emergency_heal_used(target: Unit)
signal triage_updated(patients: Array)

func _ready() -> void:
	archetype = "medic"
	system_prompt = "You are a support medic unit. Your role is to heal and support allies through healing, shields, revival, and buffs. You cannot attack enemies but can provide critical medical support. Stay behind cover and prioritize keeping your team alive."
	
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
	movement_speed = 10.0
	
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
	
	# Create visual indicators
	_create_visual_indicators()
	
	# Update visual for medic
	_update_medic_visual()

func _create_visual_indicators() -> void:
	"""Create visual indicators for medic abilities"""
	# Heal indicator
	heal_indicator = MeshInstance3D.new()
	heal_indicator.name = "HealIndicator"
	heal_indicator.mesh = SphereMesh.new()
	heal_indicator.mesh.radius = 0.5
	heal_indicator.position = Vector3(0, 2, 0)
	heal_indicator.visible = false
	
	var heal_material = StandardMaterial3D.new()
	heal_material.albedo_color = Color.GREEN
	heal_material.emission_enabled = true
	heal_material.emission = Color.GREEN * 0.5
	heal_indicator.material_override = heal_material
	
	add_child(heal_indicator)
	
	# Shield indicator
	shield_indicator = MeshInstance3D.new()
	shield_indicator.name = "ShieldIndicator"
	shield_indicator.mesh = SphereMesh.new()
	shield_indicator.mesh.radius = 0.6
	shield_indicator.position = Vector3(0, 2.5, 0)
	shield_indicator.visible = false
	
	var shield_material = StandardMaterial3D.new()
	shield_material.albedo_color = Color.BLUE
	shield_material.flags_transparent = true
	shield_material.albedo_color.a = 0.5
	shield_material.emission_enabled = true
	shield_material.emission = Color.BLUE * 0.3
	shield_indicator.material_override = shield_material
	
	add_child(shield_indicator)
	
	# Revive indicator
	revive_indicator = MeshInstance3D.new()
	revive_indicator.name = "ReviveIndicator"
	revive_indicator.mesh = CylinderMesh.new()
	revive_indicator.mesh.height = 0.2
	revive_indicator.mesh.top_radius = 1.0
	revive_indicator.mesh.bottom_radius = 1.0
	revive_indicator.position = Vector3(0, 0.1, 0)
	revive_indicator.visible = false
	
	var revive_material = StandardMaterial3D.new()
	revive_material.albedo_color = Color.YELLOW
	revive_material.emission_enabled = true
	revive_material.emission = Color.YELLOW * 0.4
	revive_indicator.material_override = revive_material
	
	add_child(revive_indicator)

func _update_medic_visual() -> void:
	# Find mesh instance for visual updates
	var mesh_instance = find_child("UnitMesh") as MeshInstance3D
	if mesh_instance:
		# Keep medic normal size
		mesh_instance.scale = Vector3(1.0, 1.0, 1.0)
		
		# Different color scheme
		var material = mesh_instance.material_override as StandardMaterial3D
		if material:
			if team_id == 1:
				material.albedo_color = Color.WHITE  # White for team 1 (medical)
			else:
				material.albedo_color = Color.GRAY  # Gray for team 2

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Update ability timers
	_update_ability_timers(delta)
	
	# Regenerate medical supplies
	_regenerate_supplies(delta)
	
	# Handle healing
	if is_healing and current_heal_target:
		_handle_healing(delta)
	
	# Handle reviving
	if is_reviving and revive_target:
		_handle_reviving(delta)
	
	# Auto-heal system
	if auto_heal_enabled:
		_auto_heal_system(delta)
	
	# Update active shields
	_update_active_shields(delta)
	
	# Update active buffs
	_update_active_buffs(delta)

func _update_ability_timers(delta: float) -> void:
	"""Update cooldown timers for abilities"""
	if emergency_heal_cooldown_timer > 0:
		emergency_heal_cooldown_timer -= delta
	
	if shield_cooldown_timer > 0:
		shield_cooldown_timer -= delta
	
	if revive_cooldown_timer > 0:
		revive_cooldown_timer -= delta
	
	if buff_cooldown_timer > 0:
		buff_cooldown_timer -= delta
	
	if revive_timer > 0:
		revive_timer -= delta
		if revive_timer <= 0:
			_complete_revive()

func _regenerate_supplies(delta: float) -> void:
	"""Regenerate medical supplies over time"""
	if medical_supplies < max_medical_supplies:
		medical_supplies += supply_regeneration_rate * delta
		medical_supplies = min(medical_supplies, max_medical_supplies)

func _handle_healing(delta: float) -> void:
	"""Handle healing process"""
	if not current_heal_target or current_heal_target.is_dead:
		is_healing = false
		current_heal_target = null
		return
	
	# Check if still in range
	var distance = global_position.distance_to(current_heal_target.global_position)
	if distance > heal_range:
		is_healing = false
		current_heal_target = null
		return
	
	# Apply healing
	var heal_amount = heal_rate * delta
	current_heal_target.heal(heal_amount)
	
	# Consume supplies
	medical_supplies -= heal_amount * 0.5
	
	# Visual feedback
	if heal_indicator:
		heal_indicator.visible = true
		var tween = create_tween()
		tween.tween_property(heal_indicator, "scale", Vector3(1.2, 1.2, 1.2), 0.3)
		tween.tween_property(heal_indicator, "scale", Vector3(1.0, 1.0, 1.0), 0.3)
	
	# Check if healing complete
	if current_heal_target.current_health >= current_heal_target.max_health:
		_complete_heal()

func _handle_reviving(delta: float) -> void:
	"""Handle reviving process"""
	if not revive_target:
		is_reviving = false
		return
	
	# Visual feedback during reviving
	if revive_indicator:
		revive_indicator.visible = true
		var progress = 1.0 - (revive_timer / revive_duration)
		revive_indicator.scale = Vector3(progress, 1.0, progress)

func _auto_heal_system(delta: float) -> void:
	"""Automatically heal nearby injured allies"""
	if is_healing or is_reviving:
		return
	
	# Find nearby injured allies
	var injured_allies = []
	var all_units = get_tree().get_nodes_in_group("units")
	
	for unit in all_units:
		if unit == self or unit.team_id != team_id or unit.is_dead:
			continue
		
		var distance = global_position.distance_to(unit.global_position)
		if distance <= heal_range:
			var health_pct = unit.get_health_percentage()
			if health_pct < heal_priority_threshold:
				injured_allies.append({
					"unit": unit,
					"health_pct": health_pct,
					"distance": distance
				})
	
	# Sort by priority (lowest health first)
	injured_allies.sort_custom(func(a, b): return a.health_pct < b.health_pct)
	
	# Update triage list
	triage_patients = injured_allies.map(func(data): return data.unit)
	triage_updated.emit(triage_patients)
	
	# Start healing highest priority target
	if not injured_allies.is_empty():
		var target_data = injured_allies[0]
		if Time.get_ticks_msec() / 1000.0 - last_heal_time >= heal_cooldown:
			heal_unit(target_data.unit)

func _update_active_shields(delta: float) -> void:
	"""Update active shield durations"""
	var expired_shields = []
	
	for unit_id in active_shields:
		var shield_data = active_shields[unit_id]
		shield_data.time_remaining -= delta
		
		if shield_data.time_remaining <= 0:
			expired_shields.append(unit_id)
	
	# Remove expired shields
	for unit_id in expired_shields:
		_remove_shield(unit_id)

func _update_active_buffs(delta: float) -> void:
	"""Update active buff durations"""
	var expired_buffs = []
	
	for unit_id in active_buffs:
		var buff_data = active_buffs[unit_id]
		buff_data.time_remaining -= delta
		
		if buff_data.time_remaining <= 0:
			expired_buffs.append(unit_id)
	
	# Remove expired buffs
	for unit_id in expired_buffs:
		_remove_buff(unit_id)

# Enhanced Medic Abilities
func heal_unit(target: Unit) -> bool:
	"""Heal target unit"""
	if not target or target.is_dead or target.team_id != team_id:
		print("Medic %s: Invalid heal target" % unit_id)
		return false
	
	if medical_supplies < 10.0:
		print("Medic %s: Insufficient medical supplies" % unit_id)
		return false
	
	var distance = global_position.distance_to(target.global_position)
	if distance > heal_range:
		print("Medic %s: Target too far to heal" % unit_id)
		return false
	
	if target.current_health >= target.max_health:
		print("Medic %s: Target already at full health" % unit_id)
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_heal_time < heal_cooldown:
		print("Medic %s: Heal on cooldown" % unit_id)
		return false
	
	# Start healing
	is_healing = true
	current_heal_target = target
	last_heal_time = current_time
	
	print("Medic %s: Started healing %s" % [unit_id, target.unit_id])
	return true

func emergency_heal(target: Unit) -> bool:
	"""Emergency heal with large amount"""
	if not target or target.is_dead or target.team_id != team_id:
		print("Medic %s: Invalid emergency heal target" % unit_id)
		return false
	
	if emergency_heal_cooldown_timer > 0:
		print("Medic %s: Emergency heal on cooldown" % unit_id)
		return false
	
	if medical_supplies < 30.0:
		print("Medic %s: Insufficient supplies for emergency heal" % unit_id)
		return false
	
	var distance = global_position.distance_to(target.global_position)
	if distance > heal_range:
		print("Medic %s: Target too far for emergency heal" % unit_id)
		return false
	
	# Apply emergency heal
	target.heal(emergency_heal_amount)
	
	# Consume supplies
	medical_supplies -= 25.0
	
	# Set cooldown
	emergency_heal_cooldown_timer = emergency_heal_cooldown
	
	# Visual effect
	_create_emergency_heal_effect(target.global_position)
	
	print("Medic %s: Emergency heal on %s for %.1f health" % [unit_id, target.unit_id, emergency_heal_amount])
	emergency_heal_used.emit(target)
	unit_healed.emit(target, emergency_heal_amount)
	
	return true

func shield_unit(target: Unit) -> bool:
	"""Apply shield to target unit"""
	if not target or target.is_dead or target.team_id != team_id:
		print("Medic %s: Invalid shield target" % unit_id)
		return false
	
	if shield_cooldown_timer > 0:
		print("Medic %s: Shield on cooldown" % unit_id)
		return false
	
	if medical_supplies < 20.0:
		print("Medic %s: Insufficient supplies for shield" % unit_id)
		return false
	
	var distance = global_position.distance_to(target.global_position)
	if distance > heal_range:
		print("Medic %s: Target too far for shield" % unit_id)
		return false
	
	# Remove existing shield if any
	if target.unit_id in active_shields:
		_remove_shield(target.unit_id)
	
	# Apply shield
	var shield_data = {
		"unit": target,
		"strength": shield_strength,
		"time_remaining": shield_duration
	}
	active_shields[target.unit_id] = shield_data
	
	# Visual effect
	_create_shield_effect(target)
	
	# Consume supplies
	medical_supplies -= 15.0
	
	# Set cooldown
	shield_cooldown_timer = shield_cooldown
	
	print("Medic %s: Shielded %s for %.1f strength" % [unit_id, target.unit_id, shield_strength])
	unit_shielded.emit(target, shield_strength)
	
	return true

func revive_unit(target: Unit) -> bool:
	"""Revive fallen unit"""
	if not target or not target.is_dead or target.team_id != team_id:
		print("Medic %s: Invalid revive target" % unit_id)
		return false
	
	if revive_cooldown_timer > 0:
		print("Medic %s: Revive on cooldown" % unit_id)
		return false
	
	if medical_supplies < 50.0:
		print("Medic %s: Insufficient supplies for revive" % unit_id)
		return false
	
	var distance = global_position.distance_to(target.global_position)
	if distance > revive_range:
		print("Medic %s: Target too far for revive" % unit_id)
		return false
	
	# Start reviving process
	is_reviving = true
	revive_target = target
	revive_timer = revive_duration
	
	# Move to target if needed
	if distance > 2.0:
		move_to(target.global_position)
	
	print("Medic %s: Starting revive of %s" % [unit_id, target.unit_id])
	return true

func apply_buff(target: Unit, buff_type: String) -> bool:
	"""Apply buff to target unit"""
	if not target or target.is_dead or target.team_id != team_id:
		print("Medic %s: Invalid buff target" % unit_id)
		return false
	
	if buff_cooldown_timer > 0:
		print("Medic %s: Buff on cooldown" % unit_id)
		return false
	
	if medical_supplies < 15.0:
		print("Medic %s: Insufficient supplies for buff" % unit_id)
		return false
	
	var distance = global_position.distance_to(target.global_position)
	if distance > heal_range:
		print("Medic %s: Target too far for buff" % unit_id)
		return false
	
	# Remove existing buff if any
	if target.unit_id in active_buffs:
		_remove_buff(target.unit_id)
	
	# Apply buff
	var buff_data = {
		"unit": target,
		"type": buff_type,
		"time_remaining": buff_duration
	}
	active_buffs[target.unit_id] = buff_data
	
	# Apply buff effects
	_apply_buff_effects(target, buff_type)
	
	# Consume supplies
	medical_supplies -= 10.0
	
	# Set cooldown
	buff_cooldown_timer = buff_cooldown
	
	print("Medic %s: Applied %s buff to %s" % [unit_id, buff_type, target.unit_id])
	buff_applied.emit(target, buff_type, buff_duration)
	
	return true

func area_heal(radius: float = 0.0) -> bool:
	"""Area of effect heal"""
	if medical_supplies < 40.0:
		print("Medic %s: Insufficient supplies for area heal" % unit_id)
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_aoe_heal_time < aoe_heal_cooldown:
		print("Medic %s: Area heal on cooldown" % unit_id)
		return false
	
	var heal_radius = radius if radius > 0 else aoe_heal_radius
	var healed_units = []
	
	# Find all units in range
	var all_units = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if unit == self or unit.team_id != team_id or unit.is_dead:
			continue
		
		var distance = global_position.distance_to(unit.global_position)
		if distance <= heal_radius:
			var heal_amount = heal_rate * 2.0  # Area heal is stronger
			unit.heal(heal_amount)
			healed_units.append(unit)
			unit_healed.emit(unit, heal_amount)
	
	# Create area heal effect
	_create_area_heal_effect(heal_radius)
	
	# Consume supplies
	medical_supplies -= 30.0
	
	# Set cooldown
	last_aoe_heal_time = current_time
	
	print("Medic %s: Area heal affected %d units" % [unit_id, healed_units.size()])
	return true

func _complete_heal() -> void:
	"""Complete healing process"""
	if not is_healing or not current_heal_target:
		return
	
	is_healing = false
	var target = current_heal_target
	current_heal_target = null
	
	# Hide indicator
	if heal_indicator:
		heal_indicator.visible = false
	
	print("Medic %s: Completed healing %s" % [unit_id, target.unit_id])
	unit_healed.emit(target, heal_rate)

func _complete_revive() -> void:
	"""Complete reviving process"""
	if not is_reviving or not revive_target:
		return
	
	var target = revive_target
	var success = true
	
	# Attempt to revive
	if target.has_method("revive"):
		target.revive()
		target.heal(target.max_health * 0.5)  # Revive with 50% health
	else:
		success = false
	
	# Clean up
	is_reviving = false
	revive_target = null
	revive_timer = 0.0
	
	# Set cooldown
	revive_cooldown_timer = revive_cooldown
	
	# Consume supplies
	medical_supplies -= 40.0
	
	# Hide indicator
	if revive_indicator:
		revive_indicator.visible = false
	
	print("Medic %s: Revive %s (success: %s)" % [unit_id, target.unit_id, success])
	unit_revived.emit(target, success)

func _apply_buff_effects(target: Unit, buff_type: String) -> void:
	"""Apply buff effects to target"""
	match buff_type:
		"speed":
			if target.has_method("set_movement_speed"):
				target.set_movement_speed(target.movement_speed * 1.5)
		"damage":
			if target.has_method("set_attack_damage"):
				target.set_attack_damage(target.attack_damage * 1.3)
		"defense":
			if target.has_method("set_defense"):
				target.set_defense(target.defense * 1.4)
		"regen":
			# Continuous health regeneration
			pass

func _remove_shield(unit_id: String) -> void:
	"""Remove shield from unit"""
	if unit_id in active_shields:
		var shield_data = active_shields[unit_id]
		active_shields.erase(unit_id)
		print("Medic %s: Shield expired on %s" % [unit_id, shield_data.unit.unit_id])

func _remove_buff(unit_id: String) -> void:
	"""Remove buff from unit"""
	if unit_id in active_buffs:
		var buff_data = active_buffs[unit_id]
		var target = buff_data.unit
		
		# Remove buff effects
		_remove_buff_effects(target, buff_data.type)
		
		active_buffs.erase(unit_id)
		print("Medic %s: Buff %s expired on %s" % [unit_id, buff_data.type, target.unit_id])

func _remove_buff_effects(target: Unit, buff_type: String) -> void:
	"""Remove buff effects from target"""
	match buff_type:
		"speed":
			if target.has_method("set_movement_speed"):
				target.set_movement_speed(target.movement_speed / 1.5)
		"damage":
			if target.has_method("set_attack_damage"):
				target.set_attack_damage(target.attack_damage / 1.3)
		"defense":
			if target.has_method("set_defense"):
				target.set_defense(target.defense / 1.4)

func _create_emergency_heal_effect(position: Vector3) -> void:
	"""Create emergency heal visual effect"""
	var effect = MeshInstance3D.new()
	effect.name = "EmergencyHealEffect"
	effect.mesh = SphereMesh.new()
	effect.mesh.radius = 1.5
	effect.position = position
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.GREEN
	material.emission_enabled = true
	material.emission = Color.GREEN * 2.0
	effect.material_override = material
	
	get_tree().current_scene.add_child(effect)
	
	# Animate effect
	var tween = create_tween()
	tween.tween_property(effect, "scale", Vector3(3.0, 3.0, 3.0), 0.5)
	tween.parallel().tween_property(effect, "material_override:albedo_color:a", 0.0, 0.5)
	tween.tween_callback(func(): effect.queue_free())

func _create_shield_effect(target: Unit) -> void:
	"""Create shield visual effect"""
	var effect = MeshInstance3D.new()
	effect.name = "ShieldEffect"
	effect.mesh = SphereMesh.new()
	effect.mesh.radius = 2.0
	effect.position = Vector3(0, 0, 0)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.BLUE
	material.flags_transparent = true
	material.albedo_color.a = 0.3
	material.emission_enabled = true
	material.emission = Color.BLUE * 0.5
	effect.material_override = material
	
	target.add_child(effect)
	
	# Animate shield
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(effect, "scale", Vector3(1.1, 1.1, 1.1), 1.0)
	tween.tween_property(effect, "scale", Vector3(1.0, 1.0, 1.0), 1.0)

func _create_area_heal_effect(radius: float) -> void:
	"""Create area heal visual effect"""
	var effect = MeshInstance3D.new()
	effect.name = "AreaHealEffect"
	effect.mesh = SphereMesh.new()
	effect.mesh.radius = radius
	effect.mesh.height = 0.5
	effect.position = Vector3(0, 0.25, 0)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.GREEN
	material.flags_transparent = true
	material.albedo_color.a = 0.2
	material.emission_enabled = true
	material.emission = Color.GREEN * 0.3
	effect.material_override = material
	
	add_child(effect)
	
	# Animate effect
	var tween = create_tween()
	tween.tween_property(effect, "scale", Vector3(1.2, 1.2, 1.2), 1.0)
	tween.parallel().tween_property(effect, "material_override:albedo_color:a", 0.0, 1.0)
	tween.tween_callback(func(): effect.queue_free())

# Public ability interface for plan executor
func get_available_abilities() -> Array[String]:
	"""Get list of available abilities"""
	var abilities = []
	
	if Time.get_ticks_msec() / 1000.0 - last_heal_time >= heal_cooldown:
		abilities.append("heal")
	
	if emergency_heal_cooldown_timer <= 0:
		abilities.append("emergency_heal")
	
	if shield_cooldown_timer <= 0:
		abilities.append("shield")
	
	if revive_cooldown_timer <= 0:
		abilities.append("revive")
	
	if buff_cooldown_timer <= 0:
		abilities.append("buff")
	
	if Time.get_ticks_msec() / 1000.0 - last_aoe_heal_time >= aoe_heal_cooldown:
		abilities.append("area_heal")
	
	return abilities

func get_ability_cooldown(ability: String) -> float:
	"""Get cooldown time for specific ability"""
	match ability:
		"heal":
			return max(0.0, heal_cooldown - (Time.get_ticks_msec() / 1000.0 - last_heal_time))
		"emergency_heal":
			return emergency_heal_cooldown_timer
		"shield":
			return shield_cooldown_timer
		"revive":
			return revive_cooldown_timer
		"buff":
			return buff_cooldown_timer
		"area_heal":
			return max(0.0, aoe_heal_cooldown - (Time.get_ticks_msec() / 1000.0 - last_aoe_heal_time))
		_:
			return 0.0

func is_ability_available(ability: String) -> bool:
	"""Check if ability is available"""
	return get_ability_cooldown(ability) <= 0.0

func get_medical_status() -> Dictionary:
	"""Get current medical status"""
	return {
		"supplies": medical_supplies,
		"max_supplies": max_medical_supplies,
		"healing": is_healing,
		"reviving": is_reviving,
		"active_shields": active_shields.size(),
		"active_buffs": active_buffs.size(),
		"triage_patients": triage_patients.size()
	}

func get_triage_list() -> Array[Unit]:
	"""Get current triage patient list"""
	return triage_patients.duplicate()

func get_active_shields() -> Dictionary:
	"""Get active shields data"""
	return active_shields.duplicate()

func get_active_buffs() -> Dictionary:
	"""Get active buffs data"""
	return active_buffs.duplicate() 