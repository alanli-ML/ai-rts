# EngineerUnit.gd
class_name EngineerUnit
extends AnimatedUnit

# Engineer-specific properties
var repair_range: float = 5.0
var repair_rate: float = 15.0
var repair_cooldown: float = 2.0
var last_repair_time: float = 0.0

func _ready() -> void:
	archetype = "engineer"
	super._ready()
	_setup_engineer_abilities()

func _setup_engineer_abilities() -> void:
	# Stats are loaded from GameConstants in base Unit class
	pass

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# Auto-repair logic can go here for buildings
	_auto_repair_system(delta)

func _auto_repair_system(_delta: float) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_repair_time < repair_cooldown:
		return

	# In a real game, you would find nearby damaged buildings
	# For now, this is a placeholder.
	
func repair_building(target: Node3D) -> bool:
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return false
		
	if target.current_health >= target.max_health:
		return false

	if global_position.distance_to(target.global_position) <= repair_range:
		target.take_damage(-repair_rate) # Negative damage to repair
		return true

	return false