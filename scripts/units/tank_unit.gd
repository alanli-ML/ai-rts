# TankUnit.gd
class_name TankUnit
extends AnimatedUnit

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
	super._ready()
	_setup_tank_abilities()

func _setup_tank_abilities() -> void:
	# Tank-specific stats are loaded from GameConstants in the base Unit class
	# This function can be used for unique visual setup or ability initialization.
	pass

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if shield_timer > 0:
		shield_timer -= delta
		if shield_timer <= 0 and shield_active:
			deactivate_shield()

func take_damage(damage: float) -> void:
	var reduced_damage = damage * (1.0 - armor_bonus)
	if shield_active:
		reduced_damage *= 0.5
	super.take_damage(reduced_damage)

func activate_shield() -> void:
	if shield_timer > 0:
		return
	shield_active = true
	shield_timer = shield_duration
	modulate = Color(0.8, 0.8, 1.2, 1.0)
	await get_tree().create_timer(shield_duration).timeout
	if shield_active:
		deactivate_shield()

func deactivate_shield() -> void:
	shield_active = false
	shield_timer = shield_cooldown
	modulate = Color.WHITE

func taunt_enemies() -> void:
	is_taunting = true
	var nearby_enemies = get_tree().get_nodes_in_group("units")
	for node in nearby_enemies:
		if node is Unit and node.team_id != self.team_id:
			if global_position.distance_to(node.global_position) <= taunt_range:
				# Logic to make 'node' target this unit would go here
				pass
	await get_tree().create_timer(3.0).timeout
	is_taunting = false