# ScoutUnit.gd
class_name ScoutUnit
extends AnimatedUnit

# Scout-specific properties
var stealth_mode: bool = false
var stealth_cooldown: float = 15.0
var stealth_timer: float = 0.0

func _ready() -> void:
	archetype = "scout"
	super._ready()
	# Scout-specific setup can go here

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if stealth_timer > 0:
		stealth_timer -= delta
	
	if stealth_mode:
		# Logic for stealth, e.g., energy drain
		pass

func activate_stealth(duration: float = 10.0) -> bool:
	if stealth_mode or stealth_timer > 0:
		return false
	
	stealth_mode = true
	stealth_timer = stealth_cooldown
	
	# Apply visual effect
	modulate.a = 0.5
	
	await get_tree().create_timer(duration).timeout
	deactivate_stealth()
	
	return true

func deactivate_stealth() -> void:
	if not stealth_mode:
		return
	
	stealth_mode = false
	modulate.a = 1.0