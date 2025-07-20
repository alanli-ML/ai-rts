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

func _attach_weapon():
	# Custom weapon attachment for turrets - mount blaster-e on top of tank
	print("DEBUG: Turret creating top-mounted weapon attachment")
	
	var WeaponAttachmentScene = preload("res://scenes/units/WeaponAttachment.tscn")
	weapon_attachment = WeaponAttachmentScene.instantiate()
	weapon_attachment.name = "TurretWeapon"
	add_child(weapon_attachment)
	
	# Equip blaster-e specifically for turrets
	var success = weapon_attachment.equip_weapon(self, "blaster-e", team_id)
	if success:
		# Position the weapon on top of the tank model
		_position_turret_weapon()
		print("DEBUG: Turret successfully mounted blaster-e weapon on top")
		
		# Connect weapon signals
		if weapon_attachment.has_signal("weapon_fired"):
			weapon_attachment.weapon_fired.connect(_on_weapon_fired)
	else:
		print("DEBUG: Turret failed to mount weapon, cleaning up")
		if weapon_attachment:
			weapon_attachment.queue_free()
			weapon_attachment = null

func _position_turret_weapon():
	"""Position the weapon on top of the tank model"""
	if not weapon_attachment:
		return
	
	# Position weapon on top of the tank model (lowered from 2.0 to 1.5)
	# The tank model is scaled 2.5x, so we need to account for that
	weapon_attachment.position = Vector3(0, 0.5, 0.65)  # Slightly lower on the tank
	weapon_attachment.rotation_degrees = Vector3(0, 180, 0)  # Rotate 180° to face correct direction
	weapon_attachment.scale = Vector3(0.5, 0.5, 0.5)  # Scale up the weapon to match tank size
	
	print("DEBUG: Positioned turret weapon at %s with rotation %s and scale %s" % [weapon_attachment.position, weapon_attachment.rotation_degrees, weapon_attachment.scale])

func _on_weapon_fired(weapon_type: String, damage: float):
	"""Handle weapon fired signal for turret weapon effects"""
	print("DEBUG: Turret weapon fired - %s dealing %.1f damage" % [weapon_type, damage])
	
	# Trigger any turret-specific firing effects here if needed
	# For now, the weapon attachment handles muzzle flash and projectiles

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
		# Face the target for proper aiming and visual consistency
		# Note: Turret model itself won't rotate, but this helps aiming logic.
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