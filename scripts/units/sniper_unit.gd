# SniperUnit.gd
class_name SniperUnit
extends AnimatedUnit

# Sniper-specific properties
var is_scoped: bool = false
var charge_time: float = 2.0
var is_charging_shot: bool = false
var charge_timer: float = 0.0
var last_shot_time: float = 0.0
var shot_cooldown: float = 3.0

func _ready() -> void:
	archetype = "sniper"
	super._ready()
	# Sniper-specific setup can go here
	
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_charging_shot:
		charge_timer += delta
		if charge_timer >= charge_time:
			_fire_charged_shot()

func charge_precision_shot(target: Unit) -> bool:
	if not is_instance_valid(target) or is_charging_shot:
		return false
	
	is_charging_shot = true
	charge_timer = 0.0
	return true

func _fire_charged_shot() -> void:
	if not is_charging_shot: return
	is_charging_shot = false
	charge_timer = 0.0
	
	# Find a target and fire. In a real scenario, the target would be stored.
	var enemies = get_tree().get_nodes_in_group("units")
	for enemy in enemies:
		if enemy is Unit and enemy.team_id != self.team_id:
			if global_position.distance_to(enemy.global_position) <= attack_range:
				_fire_precision_shot(enemy, true)
				break

func _fire_precision_shot(target: Unit, is_charged: bool = false) -> bool:
	if not is_instance_valid(target) or target.is_dead:
		return false
	
	if global_position.distance_to(target.global_position) > attack_range:
		return false
	
	var damage = attack_damage
	if is_charged:
		damage *= 1.5
	
	target.take_damage(damage)
	last_shot_time = Time.get_ticks_msec() / 1000.0
	return true