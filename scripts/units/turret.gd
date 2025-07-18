# scripts/units/turret.gd
class_name Turret
extends AnimatedUnit # Inherit from AnimatedUnit to get model/weapon attachment

func _ready():
	archetype = "turret"
	super._ready()
	can_move = false # Turrets cannot move
	
	# Customize collision shape for turret
	var collision_shape_node = get_node_or_null("CollisionShape3D")
	if collision_shape_node:
		var cylinder_shape = CylinderShape3D.new()
		cylinder_shape.height = 2.0
		cylinder_shape.radius = 1.5
		collision_shape_node.shape = cylinder_shape
		collision_shape_node.position.y = 1.0 # Center the shape vertically

func _physics_process(delta: float):
	# Turrets do not use the complex behavior matrix evaluation or movement from parent classes.
	# Their logic is simple: find and attack the closest enemy.
	
	# This logic only runs on the server
	if not multiplayer.is_server():
		return

	if is_dead:
		return

	# Simple AI: find closest enemy in range and attack
	var game_state = get_node_or_null("/root/DependencyContainer/GameState")
	if not game_state:
		return
		
	var enemies = game_state.get_units_in_radius(global_position, attack_range, team_id)
	var closest_enemy = _get_closest_valid_enemy(enemies)
	
	if is_instance_valid(closest_enemy):
		target_unit = closest_enemy
		# Turret model itself won't rotate, but this helps aiming logic.
		# A separate "turret head" node could be rotated in a more advanced implementation.
		look_at(closest_enemy.global_position, Vector3.UP)
		_attempt_attack_target(closest_enemy)
	else:
		target_unit = null
		
	# Turrets do not move, so no move_and_slide() or navigation logic is called.

func die():
	if is_dead: return
	is_dead = true
	
	# Emit the died signal so ServerGameState can clean it up
	unit_died.emit(unit_id)
	
	# On the server, just queue_free. No respawn logic.
	# The server_game_state will handle removing it from the units dictionary.
	if multiplayer.is_server():
		queue_free()