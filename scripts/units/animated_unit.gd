# AnimatedUnit.gd - Enhanced unit with animated character models
class_name AnimatedUnit
extends Unit

const MODEL_PATHS = {
	"scout": "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/character-a.glb",
	"tank": "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/character-h.glb",
	"sniper": "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/character-d.glb",
	"medic": "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/character-p.glb",
	"engineer": "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/character-o.glb",
	"turret": "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/character-h.glb" # Placeholder model
}

var animation_player: AnimationPlayer
var model_container: Node3D
const WeaponDatabase = preload("res://scripts/units/weapon_database.gd")
var weapon_db = WeaponDatabase.new()

# Charge shot visual effects
var charge_effect_node: Node3D = null
var charge_intensity: float = 0.0

func _ready() -> void:
	super._ready()
	
	model_container = $ModelContainer
	
	_load_model()
	call_deferred("_attach_weapon")

func _load_archetype_stats() -> void:
	# This is now handled by the base Unit class
	super._load_archetype_stats()

func _load_model() -> void:
	# Remove any existing model
	for child in model_container.get_children():
		child.queue_free()

	var model_path = MODEL_PATHS.get(archetype, MODEL_PATHS["scout"])
	var model_scene = load(model_path)
	
	if model_scene:
		var model_instance = model_scene.instantiate()
		model_container.add_child(model_instance)
		model_container.rotation_degrees.y = 180.0
		
		# Find the animation player in the new model
		animation_player = model_instance.find_child("AnimationPlayer", true, false)
		if not animation_player:
			print("ERROR: AnimationPlayer not found in model %s" % model_path)
			
		play_animation("Idle")
	else:
		print("ERROR: Could not load model for archetype %s at path %s" % [archetype, model_path])

func play_animation(animation_name: String):
	if not animation_player:
		print("DEBUG: No animation player for unit %s, cannot play '%s'" % [unit_id, animation_name])
		return
	
	# Add debug output for death animations specifically
	if animation_name in ["Die", "Death", "die"]:
		print("DEBUG: Unit %s attempting to play death animation: '%s'" % [unit_id, animation_name])
		
	# First try exact match
	if animation_player.has_animation(animation_name):
		if animation_name in ["Die", "Death", "die"]:
			print("DEBUG: Playing exact match death animation: '%s'" % animation_name)
		animation_player.play(animation_name)
		return
	
	# Get all available animations
	var available_animations = animation_player.get_animation_list()
	
	# Try case-insensitive match
	for anim in available_animations:
		if anim.to_lower() == animation_name.to_lower():
			if animation_name in ["Die", "Death", "die"]:
				print("DEBUG: Playing case-insensitive match death animation: '%s'" % anim)
			animation_player.play(anim)
			return
	
	# Animation mappings based on ACTUAL Kenney Blocky Characters animations
	# Available: RESET, attack-kick-left, attack-kick-right, attack-melee-left, attack-melee-right, 
	# die, drive, emote-no, emote-yes, holding-both, holding-both-shoot, holding-left, 
	# holding-left-shoot, holding-right, holding-right-shoot, idle, interact-left, 
	# interact-right, pick-up, sit, sprint, static, walk, wheelchair-*
	var animation_mappings = {
		"Run": ["sprint", "walk"],
		"Walk": ["walk", "sprint"],
		"Idle": ["idle", "static"],
		"Attack": ["holding-both-shoot", "holding-left-shoot", "holding-right-shoot", "attack-melee-left", "attack-melee-right", "attack-kick-left"],
		"Die": ["die", "static", "idle"],  # Die animation exists!
		"Death": ["die", "static", "idle"],
		"Sprint": ["sprint", "walk"],
		"Shoot": ["holding-both-shoot", "holding-left-shoot", "holding-right-shoot"],
		"Kick": ["attack-kick-left", "attack-kick-right"],
		"Melee": ["attack-melee-left", "attack-melee-right"],
		"Interact": ["interact-left", "interact-right", "pick-up"],
		"Emote": ["emote-yes", "emote-no"]
	}
	
	# Try mapped fallbacks
	if animation_name in animation_mappings:
		for fallback in animation_mappings[animation_name]:
			if animation_player.has_animation(fallback):
				if animation_name in ["Die", "Death", "die"]:
					print("DEBUG: Playing mapped fallback death animation: '%s' (for requested '%s')" % [fallback, animation_name])
				animation_player.play(fallback)
				return
	
	# Final fallback - play the first available animation if nothing else works
	if available_animations.size() > 0:
		if animation_name in ["Die", "Death", "die"]:
			print("WARN: Using final fallback '%s' for death animation '%s'" % [available_animations[0], animation_name])
		animation_player.play(available_animations[0])
		print("INFO: Using fallback animation '%s' for requested '%s'" % [available_animations[0], animation_name])
	else:
		print("WARN: No animations available for '%s'" % animation_name)

func update_client_visuals(server_velocity: Vector3, _delta: float) -> void:
	# Don't update visuals if unit is dead - death animation should not be interrupted
	if is_dead:
		return
	
	# The parent (AnimatedUnit) is now rotated by ClientDisplayManager.
	# We just need to play the correct animation based on velocity and state.
	if server_velocity.length_squared() > 0.01:
		play_animation("Run")
	else:
		if current_state == GameEnums.UnitState.CHARGING_SHOT:
			_handle_charging_shot_animation()
		elif current_state == GameEnums.UnitState.ATTACKING:
			play_animation("Attack")
		else:
			play_animation("Idle")

func _on_script_changed():
	if Engine.is_editor_hint():
		_load_model()

func _physics_process(delta: float):
	super._physics_process(delta)
	
	# Skip all animation logic if dead - death animation is handled by trigger_death_sequence()
	if is_dead:
		return

	# Handle charge shot visual effects
	_update_charge_effects(delta)

	# If we are the server but not headless, we are the host. Animate ourselves.
	# Pure clients will have their visuals updated by ClientDisplayManager.
	if multiplayer.is_server() and DisplayServer.get_name() != "headless":
		# The parent Unit node is now rotated by the new logic in unit.gd.
		# The model_container is rotated 180 degrees at load time to face forward.
		# This host-only logic just needs to manage animations based on state and velocity.
		if current_state == GameEnums.UnitState.CHARGING_SHOT:
			_handle_charging_shot_animation()
		elif current_state == GameEnums.UnitState.ATTACKING:
			play_animation("Attack")
		elif velocity.length_squared() > 0.01:
			play_animation("Run")
		else:
			play_animation("Idle")

func _handle_charging_shot_animation():
	"""Handle animations and effects for charging shot state"""
	# Play aiming/charging animation - try holding weapon animations first
	if animation_player:
		if animation_player.has_animation("holding-both"):
			animation_player.play("holding-both")
		elif animation_player.has_animation("holding-right"):
			animation_player.play("holding-right")
		else:
			play_animation("Attack")  # Fallback to attack pose
	
	# Create or update charging visual effects
	if not charge_effect_node:
		_create_charge_effect()

func _update_charge_effects(delta: float):
	"""Update charging visual effects intensity"""
	if current_state == GameEnums.UnitState.CHARGING_SHOT:
		# Get charge progress from the sniper unit if available
		var charge_progress = 0.0
		if has_method("get_charge_progress"):
			charge_progress = call("get_charge_progress")
		else:
			# Fallback: estimate based on timer if accessible
			if is_instance_valid(self) and self.get("charge_timer") != null and self.get("charge_time") != null:
				var charge_timer = self.get("charge_timer") 
				var charge_time = self.get("charge_time")
				if charge_time > 0:
					charge_progress = 1.0 - (charge_timer / charge_time)
		
		charge_intensity = charge_progress
		_update_charge_visual_intensity()
	else:
		# Gradually fade out charge effects
		if charge_intensity > 0:
			charge_intensity = max(0, charge_intensity - delta * 3.0)
			_update_charge_visual_intensity()
		
		# Remove charge effect when intensity reaches zero
		if charge_intensity <= 0 and charge_effect_node:
			charge_effect_node.queue_free()
			charge_effect_node = null

func update_charge_data(charge_timer: float, charge_time: float):
	"""Update charge data received from server for client units"""
	set("charge_timer", charge_timer)
	set("charge_time", charge_time)

func _create_charge_effect():
	"""Create visual charging effect (scope glint, energy buildup, etc.)"""
	if charge_effect_node:
		return
	
	# Create a glowing sphere effect above the weapon/unit
	charge_effect_node = Node3D.new()
	charge_effect_node.name = "ChargeEffect"
	add_child(charge_effect_node)
	
	# Position above the unit
	charge_effect_node.position = Vector3(0, 2.5, 0)
	
	# Create a glowing sphere mesh
	var sphere_mesh = MeshInstance3D.new()
	sphere_mesh.mesh = SphereMesh.new()
	sphere_mesh.mesh.radius = 0.1
	sphere_mesh.mesh.height = 0.2
	charge_effect_node.add_child(sphere_mesh)
	
	# Create glowing material
	var glow_material = StandardMaterial3D.new()
	glow_material.albedo_color = Color.CYAN
	glow_material.emission_enabled = true
	glow_material.emission = Color.CYAN
	glow_material.flags_transparent = true
	sphere_mesh.material_override = glow_material
	
	# Add pulsing effect
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(sphere_mesh, "scale", Vector3(1.2, 1.2, 1.2), 0.5)
	tween.tween_property(sphere_mesh, "scale", Vector3(0.8, 0.8, 0.8), 0.5)

func _update_charge_visual_intensity():
	"""Update the visual intensity of the charging effect"""
	if not charge_effect_node:
		return
	
	var sphere_mesh = charge_effect_node.get_child(0) as MeshInstance3D
	if not sphere_mesh or not sphere_mesh.material_override:
		return
	
	var material = sphere_mesh.material_override as StandardMaterial3D
	if not material:
		return
	
	# Update glow intensity based on charge progress
	var base_color = Color.CYAN
	var intensity = 1.0 + (charge_intensity * 4.0)  # Scale from 1.0 to 5.0
	
	material.emission = base_color * intensity
	material.albedo_color = base_color * (0.5 + charge_intensity * 0.5)
	
	# Update scale based on charge intensity
	var scale_factor = 0.5 + (charge_intensity * 1.5)  # Scale from 0.5 to 2.0
	charge_effect_node.scale = Vector3(scale_factor, scale_factor, scale_factor)
	
	# Update opacity
	material.albedo_color.a = 0.3 + (charge_intensity * 0.7)

func play_charged_shot_effect():
	"""Play special effects when the charged shot is fired"""
	print("DEBUG: Playing charged shot firing effect for unit %s" % unit_id)
	
	# Play enhanced shooting animation
	if animation_player:
		if animation_player.has_animation("holding-both-shoot"):
			animation_player.play("holding-both-shoot")
		elif animation_player.has_animation("holding-right-shoot"):
			animation_player.play("holding-right-shoot")
		else:
			play_animation("Attack")
	
	# Create enhanced muzzle flash effect
	_create_enhanced_muzzle_flash()
	
	# Play charged shot sound
	_play_charged_shot_sound()
	
	# Remove charge effect immediately
	if charge_effect_node:
		charge_effect_node.queue_free()
		charge_effect_node = null
	charge_intensity = 0.0

func _create_enhanced_muzzle_flash():
	"""Create an enhanced muzzle flash for charged shots"""
	if not weapon_attachment:
		return
	
	var muzzle_point = weapon_attachment.get("muzzle_point")
	if not muzzle_point:
		return
	
	# Create larger, more intense muzzle flash
	var enhanced_flash = MeshInstance3D.new()
	enhanced_flash.name = "EnhancedMuzzleFlash"
	enhanced_flash.mesh = SphereMesh.new()
	enhanced_flash.mesh.radius = 0.15  # Larger than normal
	enhanced_flash.mesh.height = 0.3
	
	var flash_material = StandardMaterial3D.new()
	flash_material.albedo_color = Color(1.0, 0.8, 0.3, 0.8)  # Orange-yellow
	flash_material.emission_enabled = true
	flash_material.emission = Color(1.0, 0.8, 0.3) * 5.0  # Very bright
	flash_material.flags_transparent = true
	enhanced_flash.material_override = flash_material
	
	muzzle_point.add_child(enhanced_flash)
	
	# Animate enhanced muzzle flash
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(enhanced_flash, "scale", Vector3(3.0, 3.0, 3.0), 0.1)
	tween.tween_property(enhanced_flash, "scale", Vector3(0.1, 0.1, 0.1), 0.2)
	tween.tween_property(enhanced_flash, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func(): if is_instance_valid(enhanced_flash): enhanced_flash.queue_free())

func _play_charged_shot_sound():
	"""Play enhanced sound effect for charged shot"""
	var audio_manager = get_node_or_null("/root/DependencyContainer/AudioManager")
	if audio_manager:
		# Try to play a special charged shot sound, fallback to regular shot
		if audio_manager.has_method("play_sound_3d"):
			# First try charged shot sound
			audio_manager.play_sound_3d("res://assets/audio/sfx/charged_shot.wav", global_position)
			# If that doesn't exist, the audio manager should fallback gracefully

func get_skeleton() -> Skeleton3D:
	if model_container and model_container.get_child_count() > 0:
		var model_instance = model_container.get_child(0)
		if model_instance:
			return model_instance.find_child("Skeleton3D", true, false)
	return null

func _attach_weapon():
	# Get weapon attachment from parent Unit class
	print("DEBUG: AnimatedUnit._attach_weapon() called for unit %s (archetype: %s)" % [unit_id, archetype])
	if not weapon_attachment:
		print("DEBUG: AnimatedUnit._attach_weapon() - creating new weapon attachment")
		var WeaponAttachmentScene = preload("res://scenes/units/WeaponAttachment.tscn")
		weapon_attachment = WeaponAttachmentScene.instantiate()
		weapon_attachment.name = "WeaponAttachment"
		add_child(weapon_attachment)

		var weapon_type = weapon_db.get_weapon_for_archetype(archetype)
		print("DEBUG: AnimatedUnit._attach_weapon() - selected weapon type: %s" % weapon_type)
		
		var success = weapon_attachment.equip_weapon(self, weapon_type, team_id)
		if not success:
			print("DEBUG: AnimatedUnit._attach_weapon() - Failed to attach weapon to %s" % unit_id)
			if weapon_attachment:
				weapon_attachment.queue_free()
				weapon_attachment = null
		else:
			print("DEBUG: AnimatedUnit._attach_weapon() - Successfully attached weapon %s to unit %s" % [weapon_type, unit_id])
	else:
		print("DEBUG: AnimatedUnit._attach_weapon() - weapon attachment already exists")

func trigger_death_sequence():
	# Allow death sequence to run even if already marked as dead
	# This ensures visual effects play when unit dies
	print("DEBUG: AnimatedUnit %s (%s) starting death sequence" % [unit_id, archetype])
	
	# Prevent further actions and ensure dead state
	is_dead = true
	# NOTE: Collision is now disabled in the base Unit.die() method
	# No need to disable collision here - it's handled centrally
	
	# Add immediate visual feedback that the unit is dead
	_apply_immediate_death_effects()
	
	_play_death_sound()
	
	# Connect to animation finished signal if not already connected
	if animation_player and not animation_player.is_connected("animation_finished", _on_death_animation_finished):
		animation_player.animation_finished.connect(_on_death_animation_finished)
	
	var death_animation_played = false
	
	# Play death animation - Kenney models have a "die" animation!
	if animation_player:
		var available_anims = animation_player.get_animation_list()
		print("DEBUG: Available animations for death: %s" % available_anims)
		
		# The Kenney models have a "die" animation, so let's use it
		if animation_player.has_animation("die"):
			print("DEBUG: Playing Kenney 'die' animation (0.33s)")
			animation_player.play("die")
			death_animation_played = true
		else:
			# Fallback to our animation mapping system
			print("DEBUG: 'die' animation not found, using fallback system")
			play_animation("Die")  # This will try die, static, idle
			# Start visual effects immediately since fallback might be static
			call_deferred("_start_death_visual_effects")
	else:
		print("DEBUG: No animation player found for death sequence")
		# No animation player, go straight to visual effects
		call_deferred("_start_death_visual_effects")

func _on_death_animation_finished(animation_name: String):
	"""Handle completion of death animation"""
	# Check if this was the death animation (Kenney models use "die")
	if animation_name == "die":
		print("DEBUG: Kenney death animation 'die' completed for unit %s" % unit_id)
		_start_death_visual_effects()
	# Handle other potential death-related animations as fallback
	elif animation_name.to_lower() in ["death", "fall", "hurt"]:
		print("DEBUG: Fallback death animation '%s' completed for unit %s" % [animation_name, unit_id])
		_start_death_visual_effects()

func _start_death_visual_effects():
	"""Start the visual death effects sequence"""
	print("DEBUG: Starting death visual effects for unit %s" % unit_id)
	
	# Note: Keep physics processing enabled for respawn timer countdown
	
	# Add death effects (rotation, scale, etc.)
	_apply_death_effects()
	
	# Wait a moment, then fade out
	await get_tree().create_timer(0.5).timeout
	_fade_out_unit()

func _apply_immediate_death_effects():
	"""Apply immediate visual changes when unit dies (before animation)"""
	print("DEBUG: Applying immediate death effects for unit %s" % unit_id)
	
	# Note: Don't disable physics processing here as it will be re-enabled for respawn countdown
	# The respawn system will manage physics processing state
	
	# Immediately start darkening the unit (check if modulate exists)
	if has_method("set_modulate"):
		self.modulate = Color(0.7, 0.7, 0.7, 1.0)  # Darker/grayer immediately
	elif "modulate" in self:
		self.modulate = Color(0.7, 0.7, 0.7, 1.0)
	else:
		print("DEBUG: Unit %s does not support modulate property, skipping color change" % unit_id)
	
	# Slightly reduce scale immediately to show impact
	if model_container:
		model_container.scale = Vector3(0.95, 0.95, 0.95)

func _apply_death_effects():
	"""Apply visual death effects like rotation and scaling"""
	if not model_container:
		return
	
	# Create a death effect tween
	var death_tween = create_tween()
	death_tween.set_parallel(true)
	
	# Slight rotation and scale down effect
	death_tween.tween_property(model_container, "rotation_degrees:z", 90.0, 1.0)
	death_tween.tween_property(model_container, "scale", Vector3(0.8, 0.8, 0.8), 1.0)
	
	# Continue darkening the unit (check if modulate exists)
	if has_method("set_modulate") or "modulate" in self:
		death_tween.tween_property(self, "modulate", Color(0.5, 0.5, 0.5, 1.0), 0.8)
	else:
		print("DEBUG: Skipping modulate tween for unit %s (property not available)" % unit_id)

func _fade_out_unit():
	"""Gradually fade out the unit after death animation"""
	print("DEBUG: Starting fade out for unit %s" % unit_id)
	
	# Check if we can fade using modulate
	if has_method("set_modulate") or "modulate" in self:
		# Create a fade tween
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 2.0)
		
		# Wait for fade to complete then make completely invisible
		await tween.finished
	else:
		# Fallback: just wait a bit then make invisible
		print("DEBUG: Modulate not available, using fallback fade for unit %s" % unit_id)
		await get_tree().create_timer(2.0).timeout
	
	visible = false
	print("DEBUG: Unit %s fully faded out" % unit_id)

func _play_death_sound():
	var audio_manager = get_node_or_null("/root/DependencyContainer/AudioManager")
	if audio_manager:
		# In the future, this could be archetype-specific from the database
		audio_manager.play_sound_3d("res://assets/audio/sfx/unit_death_01.wav", global_position)

func trigger_respawn_sequence():
	"""Called when unit respawns - visual effects for revival"""
	print("DEBUG: AnimatedUnit %s (%s) starting respawn sequence" % [unit_id, archetype])
	
	# CRITICAL: This method is called AFTER _set_initial_facing_direction() in the base Unit class
	# The Unit transform is correctly rotated toward the enemy base, but we need to ensure
	# the model_container maintains its 180° Y rotation for proper forward-facing orientation
	
	# Make unit visible again and reset visual state
	visible = true
	
	# Reset modulate if available (try model container first, then self)
	var modulate_reset = false
	if model_container and "modulate" in model_container:
		model_container.modulate = Color.WHITE
		modulate_reset = true
	elif "modulate" in self:
		self.modulate = Color.WHITE
		modulate_reset = true
	elif has_method("set_modulate"):
		self.modulate = Color.WHITE
		modulate_reset = true
	
	if not modulate_reset:
		print("DEBUG: Modulate not available for unit %s, skipping color reset" % unit_id)
	
	# Reset model container (preserve 180° Y rotation for proper forward facing)
	if model_container:
		model_container.scale = Vector3.ONE
		model_container.rotation_degrees = Vector3(0, 180, 0)  # Maintain proper forward orientation
		print("DEBUG: Unit %s model container rotation reset to proper forward orientation (0, 180, 0)" % unit_id)
	
	# NOTE: Collision is now re-enabled in the base Unit._handle_respawn() method
	# No need to enable collision here - it's handled centrally
	
	# Apply respawn visual effects
	_apply_respawn_effects()
	
	# Play respawn animation if available
	if animation_player and animation_player.has_animation("idle"):
		animation_player.play("idle")
	else:
		play_animation("Idle")
	
	print("DEBUG: Unit %s respawn sequence completed" % unit_id)

func _apply_respawn_effects():
	"""Apply visual effects for respawn"""
	# Start with slightly enlarged scale and fade in
	if model_container:
		model_container.scale = Vector3(1.2, 1.2, 1.2)
		var respawn_tween = create_tween()
		respawn_tween.set_parallel(true)
		
		# Scale back to normal
		respawn_tween.tween_property(model_container, "scale", Vector3.ONE, 0.5)
		
		# Add a brief glow effect (try model container first, then self)
		var glow_applied = false
		if model_container and "modulate" in model_container:
			respawn_tween.tween_property(model_container, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.2)
			respawn_tween.tween_property(model_container, "modulate", Color.WHITE, 0.3)
			glow_applied = true
		elif "modulate" in self:
			respawn_tween.tween_property(self, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.2)
			respawn_tween.tween_property(self, "modulate", Color.WHITE, 0.3)
			glow_applied = true
		elif has_method("set_modulate"):
			respawn_tween.tween_property(self, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.2)
			respawn_tween.tween_property(self, "modulate", Color.WHITE, 0.3)
			glow_applied = true
		
		if not glow_applied:
			print("DEBUG: Skipping glow effect for unit %s (modulate not available)" % unit_id)

func debug_list_available_animations() -> void:
	"""Debug method to list all available animations for this unit"""
	if not animation_player:
		print("DEBUG: No animation player available for unit %s" % unit_id)
		return
	
	var available_anims = animation_player.get_animation_list()
	print("DEBUG: Unit %s (%s) available animations: %s" % [unit_id, archetype, available_anims])
	
	# Also check for death-related animations specifically
	var death_candidates = ["die", "death", "fall", "hurt", "damage", "knockout"]
	var found_death_anims = []
	for candidate in death_candidates:
		if animation_player.has_animation(candidate):
			found_death_anims.append(candidate)
	
	if found_death_anims.size() > 0:
		print("DEBUG: Found death-related animations: %s" % found_death_anims)
	else:
		print("DEBUG: No death-related animations found - will use visual effects only")