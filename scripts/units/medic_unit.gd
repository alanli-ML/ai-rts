# MedicUnit.gd
class_name MedicUnit
extends AnimatedUnit

@export var use_healing_projectiles: bool = true # Whether to use projectiles for ranged healing
@export var projectile_heal_range: float = 25.0 # Maximum range for projectile healing
@export var healing_cooldown: float = 0.5 # Cooldown between healing actions

var last_heal_time: float = 0.0

func _ready() -> void:
	archetype = "medic"
	super._ready()
	system_prompt = "You are a combat medic. Your primary directive is to keep your teammates alive. Your squad will often be fighting over control points; stay near them and use your `heal_ally` ability on any injured ally. Prioritize healing units that are under fire or have the lowest health, especially those capturing a point. You should avoid direct combat and position yourself safely behind your teammates during engagements at control points."

# --- Action Implementation ---

func heal_ally(params: Dictionary):
	var target_id = params.get("target_id", "")
	if target_id.is_empty():
		print("Medic %s: No target specified for heal command." % unit_id)
		return
	
	# Check healing cooldown
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_heal_time < healing_cooldown:
		print("Medic %s: Healing on cooldown (%.1fs remaining)" % [unit_id, healing_cooldown - (current_time - last_heal_time)])
		return
		
	GameConstants.debug_print("Medic %s heal_ally called with target: %s" % [unit_id, target_id], "UNITS")

	var game_state = get_node("/root/DependencyContainer").get_game_state()
	if not game_state:
		return

	var target = game_state.units.get(target_id)
	
	# Validate target
	if not is_instance_valid(target) or target.is_dead:
		# print("Medic %s: Heal target %s is not valid." % [unit_id, target_id])  # TEMPORARILY DISABLED
		return
	if target.team_id != self.team_id:
		# print("Medic %s: Cannot heal enemy target %s." % [unit_id, target_id])  # TEMPORARILY DISABLED
		return
	if target.get_health_percentage() >= 1.0:
		# print("Medic %s: Target %s is already at full health." % [unit_id, target_id])  # TEMPORARILY DISABLED
		return

	var distance_to_target = global_position.distance_to(target.global_position)
	
	# Check if we can use healing projectiles for ranged healing
	if use_healing_projectiles and distance_to_target <= projectile_heal_range and distance_to_target > attack_range:
		# Launch healing projectile for ranged healing
		if has_method("launch_healing_projectile"):
			call("launch_healing_projectile", target.global_position)
			last_heal_time = current_time
			print("%s launched healing projectile at %s (range: %.1f)" % [unit_id, target_id, distance_to_target])
		return
	
	# Set state to HEALING for direct healing
	self.target_unit = target
	self.current_state = GameEnums.UnitState.HEALING
	last_heal_time = current_time
	print("%s is moving to heal target %s." % [unit_id, target_id])


func triage(_params: Dictionary):
	print("%s is performing triage on nearby allies." % unit_id)
	pass