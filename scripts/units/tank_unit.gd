# TankUnit.gd
class_name TankUnit
extends AnimatedUnit

# Shield properties
var shield_active: bool = false
var shield_health: float = 0.0
@export var max_shield_health: float = 100.0
@export var shield_cooldown: float = 15.0
var shield_cooldown_timer: float = 0.0
var shield_node: Node3D = null

# Taunt properties
@export var taunt_cooldown: float = 20.0  # 20 second cooldown
var taunt_cooldown_timer: float = 0.0
var taunt_range: float = 35.0  # Range for taunt effect (slightly larger than vision)

func _ready() -> void:
	archetype = "tank"
	super._ready()
	system_prompt = "You are a heavy tank, the spearhead of our assault. Your job is to lead the charge to capture and hold control points. Use your heavy armor to absorb damage and protect your allies as you push onto contested points. Use `activate_shield` when engaging multiple enemies or facing heavy fire on a control point. Use `taunt_enemies` to draw enemy fire away from your allies and force enemies to focus on you. Always try to be at the front of your squad, drawing enemy fire. Your goal is to break through enemy lines and create space for your teammates to secure objectives."

func _physics_process(delta: float):
	if shield_cooldown_timer > 0:
		shield_cooldown_timer -= delta
	if taunt_cooldown_timer > 0:
		taunt_cooldown_timer -= delta
	super._physics_process(delta)

	# If we are the host, manage our own visuals.
	if multiplayer.is_server() and DisplayServer.get_name() != "headless":
		if shield_active and not is_instance_valid(shield_node):
			var shield_scene = preload("res://scenes/fx/ShieldEffect.tscn")
			shield_node = shield_scene.instantiate()
			add_child(shield_node)
		elif not shield_active and is_instance_valid(shield_node):
			shield_node.queue_free()
			shield_node = null

# --- Action Implementation ---

func activate_shield(_params: Dictionary):
	if shield_cooldown_timer > 0:
		return # Ability is on cooldown
	shield_active = true
	shield_health = max_shield_health
	shield_cooldown_timer = shield_cooldown
	print("%s activated its shield." % unit_id)

func taunt_enemies(_params: Dictionary):
	# Check if ability is on cooldown
	if taunt_cooldown_timer > 0:
		#print("%s taunt is on cooldown (%.1f seconds remaining)" % [unit_id, taunt_cooldown_timer])
		return
	
	print("%s is taunting nearby enemies!" % unit_id)
	
	# Start cooldown
	taunt_cooldown_timer = taunt_cooldown
	
	# Play taunt animation
	if has_method("play_animation"):
		play_animation("Emote")
	
	# Display speech bubble with taunting message
	_trigger_taunt_speech()
	
	# Find and taunt all enemies in range
	var taunted_count = _taunt_enemies_in_range()
	
	print("%s taunted %d enemies" % [unit_id, taunted_count])

func _trigger_taunt_speech():
	"""Display a speech bubble with taunting message"""
	var taunt_messages = [
		"Come at me!",
		"I'm right here!",
		"Focus fire on me!",
		"Over here, cowards!",
		"Can't handle a real tank?",
		"Bring it on!"
	]
	
	var speech_text = taunt_messages[randi() % taunt_messages.size()]
	
	# Find the speech bubble manager and display the taunt
	var speech_manager = get_node_or_null("/root/DependencyContainer/SpeechBubbleManager")
	if speech_manager and speech_manager.has_method("show_speech_bubble"):
		speech_manager.show_speech_bubble(unit_id, speech_text, team_id)
	
	# Also trigger via the server's speech system for network sync
	var plan_executor = get_node_or_null("/root/DependencyContainer/PlanExecutor")
	if plan_executor and plan_executor.has_signal("speech_triggered"):
		plan_executor.speech_triggered.emit(unit_id, speech_text)

func _taunt_enemies_in_range() -> int:
	"""Make all enemies in taunt range attack this tank"""
	var game_state = get_node("/root/DependencyContainer").get_game_state()
	if not game_state:
		return 0
	
	var taunted_count = 0
	
	# Find all enemy units in range
	for unit_id_key in game_state.units:
		var enemy_unit = game_state.units[unit_id_key]
		if not is_instance_valid(enemy_unit):
			continue
		
		# Skip if same team or if unit is dead
		if enemy_unit.team_id == self.team_id or enemy_unit.is_dead:
			continue
		
		# Check if enemy is in taunt range
		var distance = global_position.distance_to(enemy_unit.global_position)
		if distance <= taunt_range:
			# Make the enemy target this tank
			if enemy_unit.has_method("attack_target"):
				enemy_unit.attack_target(self)
				taunted_count += 1
				print("DEBUG: Taunted enemy %s to attack %s" % [enemy_unit.unit_id, self.unit_id])
	
	return taunted_count

func get_taunt_cooldown_remaining() -> float:
	"""Get remaining cooldown time for taunt ability"""
	return max(0.0, taunt_cooldown_timer)

func is_taunt_ready() -> bool:
	"""Check if taunt ability is ready to use"""
	return taunt_cooldown_timer <= 0.0

# Override take_damage to use the shield
func take_damage(damage: float) -> void:
	if is_dead: return
	
	if shield_active:
		var damage_to_shield = min(shield_health, damage)
		shield_health -= damage_to_shield
		damage -= damage_to_shield
		if shield_health <= 0:
			shield_active = false
			print("%s's shield was broken." % unit_id)
			
	if damage > 0:
		super.take_damage(damage) # Call the original method in Unit.gd