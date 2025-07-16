# MedicUnit.gd
class_name MedicUnit
extends AnimatedUnit

# Medic-specific properties
var heal_range: float = 15.0
var heal_rate: float = 10.0
var heal_cooldown: float = 2.0
var last_heal_time: float = 0.0

func _ready() -> void:
	archetype = "medic"
	super._ready()
	_setup_medic_abilities()

func _setup_medic_abilities() -> void:
	# Stats are loaded from GameConstants in base Unit class
	# This is for unique abilities
	pass

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# Auto-heal logic can go here
	_auto_heal_system(delta)

func _auto_heal_system(_delta: float):
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_heal_time < heal_cooldown:
		return

	var allies = get_tree().get_nodes_in_group("units")
	for ally in allies:
		if ally is Unit and ally.team_id == self.team_id and ally != self:
			if ally.current_health < ally.max_health:
				if global_position.distance_to(ally.global_position) <= heal_range:
					heal_unit(ally)
					last_heal_time = current_time
					break # Heal one ally at a time

func heal_unit(target: Unit) -> bool:
	if not is_instance_valid(target) or target.is_dead or target.team_id != self.team_id:
		return false
	
	if target.current_health >= target.max_health:
		return false
	
	target.take_damage(-heal_rate) # Negative damage to heal
	return true