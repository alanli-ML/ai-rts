# SniperUnit.gd
class_name SniperUnit
extends AnimatedUnit

@export var charge_time: float = 2.0
var charge_timer: float = 0.0

func _ready() -> void:
	archetype = "sniper"
	super._ready()
	system_prompt = "You are a long-range precision sniper. Your top priority is eliminating high-value targets from a safe distance, especially those trying to capture or defend control points. Find a good vantage point overlooking a contested control point and provide overwatch for your team. High-value targets include enemy snipers, medics, and engineers. Use your `charge_shot` ability on stationary or high-health targets. Always maintain maximum distance from the enemy. If enemies get too close, retreat to a safer position. You are not a front-line fighter."

func _physics_process(delta: float):
	if current_state == GameEnums.UnitState.CHARGING_SHOT:
		can_move = false
		if not is_instance_valid(target_unit):
			current_state = GameEnums.UnitState.IDLE
			action_complete = true
		else:
			look_at(target_unit.global_position, Vector3.UP)
			charge_timer -= delta
			if charge_timer <= 0:
				if weapon_attachment and weapon_attachment.has_method("fire"):
					# Fire with bonus damage
					var original_damage = weapon_attachment.damage
					weapon_attachment.damage *= 2.5
					weapon_attachment.fire()
					weapon_attachment.damage = original_damage # Reset damage
				current_state = GameEnums.UnitState.IDLE
				action_complete = true
	else:
		can_move = true

	super._physics_process(delta)

# --- Action Placeholders ---

func charge_shot(params: Dictionary):
	var target_id = params.get("target_id")
	if target_id == null:
		print("Sniper %s: No target specified for charge_shot." % unit_id)
		action_complete = true
		return

	var game_state = get_node("/root/DependencyContainer").get_game_state()
	if not game_state:
		action_complete = true
		return

	var target = game_state.units.get(target_id)
	if is_instance_valid(target) and not target.is_dead:
		target_unit = target
		current_state = GameEnums.UnitState.CHARGING_SHOT
		charge_timer = charge_time
		print("%s is charging a precision shot against %s." % [unit_id, str(target_id)])
	else:
		print("Sniper %s: Invalid target for charge_shot: %s" % [unit_id, str(target_id)])
		action_complete = true

func find_cover(_params: Dictionary):
	print("%s is finding a high-ground cover position." % unit_id)
	pass