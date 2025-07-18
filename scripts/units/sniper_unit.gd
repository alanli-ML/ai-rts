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
				# Play enhanced visual effects before firing
				if has_method("play_charged_shot_effect"):
					play_charged_shot_effect()
				
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

func get_charge_progress() -> float:
	"""Return the current charge progress (0.0 to 1.0) for visual effects"""
	if current_state != GameEnums.UnitState.CHARGING_SHOT or charge_time <= 0:
		return 0.0
	
	return 1.0 - (charge_timer / charge_time)

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
		
		# Play charging sound effect
		_play_charging_sound()
	else:
		print("Sniper %s: Invalid target for charge_shot: %s" % [unit_id, str(target_id)])
		action_complete = true

func _play_charging_sound():
	"""Play sound effect when starting to charge a shot"""
	var audio_manager = get_node_or_null("/root/DependencyContainer/AudioManager")
	if audio_manager and audio_manager.has_method("play_sound_3d"):
		# Try to play charging sound - audio manager should handle fallbacks
		audio_manager.play_sound_3d("res://assets/audio/sfx/charge_start.wav", global_position)

func find_cover(_params: Dictionary):
	print("%s is finding a high-ground cover position." % unit_id)
	pass