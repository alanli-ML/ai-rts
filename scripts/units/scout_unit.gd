# ScoutUnit.gd
class_name ScoutUnit
extends AnimatedUnit

var is_stealthed: bool = false
@export var stealth_duration: float = 10.0
@export var stealth_cooldown: float = 15.0
var stealth_timer: float = 0.0
var stealth_cooldown_timer: float = 0.0

func _ready() -> void:
	archetype = "scout"
	super._ready()
	system_prompt = "You are a fast, stealthy scout. Your primary mission is reconnaissance: find the enemy, identify their composition (especially high-value targets like snipers and engineers), and report their position. Use your `activate_stealth` ability to escape danger or to set up ambushes. Avoid direct combat unless you have a clear advantage. Prioritize survival above all else."

func _physics_process(delta: float):
	if is_stealthed:
		stealth_timer -= delta
		if stealth_timer <= 0:
			deactivate_stealth()
	
	if stealth_cooldown_timer > 0:
		stealth_cooldown_timer -= delta

	super._physics_process(delta)

# --- Action Implementation ---

func activate_stealth(_params: Dictionary):
	if stealth_cooldown_timer > 0: return
	is_stealthed = true
	stealth_timer = stealth_duration
	stealth_cooldown_timer = stealth_cooldown
	print("%s is activating stealth." % unit_id)

func deactivate_stealth():
	if not is_stealthed: return
	is_stealthed = false
	stealth_timer = 0
	print("%s is no longer stealthed." % unit_id)

func sabotage(_params: Dictionary):
	print("%s is sabotaging a target." % unit_id)
	pass

# Override attack to break stealth
func attack_target(target: Unit):
	if is_stealthed:
		deactivate_stealth()
	super.attack_target(target)