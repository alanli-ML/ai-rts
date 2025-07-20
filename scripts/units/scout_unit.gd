# ScoutUnit.gd
class_name ScoutUnit
extends AnimatedUnit

var is_stealthed: bool = false
var was_stealthed: bool = false
@export var stealth_duration: float = 10.0
@export var stealth_cooldown: float = 15.0
var stealth_timer: float = 0.0
var stealth_cooldown_timer: float = 0.0

func _ready() -> void:
	archetype = "scout"
	super._ready()
	system_prompt = "You are a fast, stealthy scout. Your primary mission is reconnaissance. Identify which control points are undefended and capture them. Use your speed to quickly move between points. Your secondary mission is to find the enemy, identify their composition (especially high-value targets like snipers and engineers), and report their position, especially near contested control points. Use your `activate_stealth` ability to escape danger or to capture a point unnoticed. Avoid direct combat unless you have a clear advantage. Prioritize survival."

func _physics_process(delta: float):
	if is_stealthed:
		stealth_timer -= delta
		if stealth_timer <= 0:
			deactivate_stealth()
	
	if stealth_cooldown_timer > 0:
		stealth_cooldown_timer -= delta

	super._physics_process(delta)

	# If we are the host, manage our own visuals.
	if multiplayer.is_server() and DisplayServer.get_name() != "headless":
		if is_stealthed != was_stealthed:
			var model_container = get_node_or_null("ModelContainer")
			if model_container:
				if is_stealthed:
					_set_model_transparency(model_container, 0.3)
				else:
					_set_model_transparency(model_container, 1.0)
			was_stealthed = is_stealthed

# --- Action Implementation ---

func activate_stealth(_params: Dictionary):
	if stealth_cooldown_timer > 0: return
	is_stealthed = true
	stealth_timer = stealth_duration
	stealth_cooldown_timer = stealth_cooldown
	print("%s is activating stealth." % unit_id)
	
	if multiplayer.is_server():
		get_tree().get_root().get_node("UnifiedMain").rpc("ability_visuals_rpc", unit_id, "stealth_on")

func deactivate_stealth():
	if not is_stealthed: return
	is_stealthed = false
	stealth_timer = 0
	print("%s is no longer stealthed." % unit_id)
	
	if multiplayer.is_server():
		get_tree().get_root().get_node("UnifiedMain").rpc("ability_visuals_rpc", unit_id, "stealth_off")

func sabotage(_params: Dictionary):
	print("%s is sabotaging a target." % unit_id)
	pass

# Override attack to break stealth
func attack_target(target: Unit):
	if is_stealthed:
		deactivate_stealth()
	super.attack_target(target)

# --- Visual Effect Helpers (for host) ---