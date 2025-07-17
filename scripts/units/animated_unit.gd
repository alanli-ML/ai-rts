# AnimatedUnit.gd - Enhanced unit with animated character models
class_name AnimatedUnit
extends Unit

const MODEL_PATHS = {
	"scout": "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/character-a.glb",
	"tank": "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/character-h.glb",
	"sniper": "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/character-d.glb",
	"medic": "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/character-p.glb",
	"engineer": "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/character-o.glb"
}

var animation_player: AnimationPlayer
var model_container: Node3D
const WeaponDatabase = preload("res://scripts/units/weapon_database.gd")
var weapon_db = WeaponDatabase.new()

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
	
	# Animation mappings for fallbacks based on actual Kenney animations
	var animation_mappings = {
		"Run": ["sprint", "walk"],  # No "Run" exists, use sprint or walk
		"Walk": ["walk", "sprint"],
		"Idle": ["idle", "static"],
		"Attack": ["holding-both-shoot", "holding-left-shoot", "holding-right-shoot", "attack-melee-left", "attack-melee-right"],
		"Die": ["die"],
		"Death": ["die"],  # Map Death to die
		"Sprint": ["sprint", "walk"],
		"Shoot": ["holding-both-shoot", "holding-left-shoot", "holding-right-shoot"]
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
		if current_state == GameEnums.UnitState.ATTACKING:
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

	# If we are the server but not headless, we are the host. Animate ourselves.
	# Pure clients will have their visuals updated by ClientDisplayManager.
	if multiplayer.is_server() and DisplayServer.get_name() != "headless":
		# The parent Unit node is now rotated by the new logic in unit.gd.
		# The model_container is rotated 180 degrees at load time to face forward.
		# This host-only logic just needs to manage animations based on state and velocity.
		if current_state == GameEnums.UnitState.ATTACKING:
			play_animation("Attack")
		elif velocity.length_squared() > 0.01:
			play_animation("Run")
		else:
			play_animation("Idle")

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
	if is_dead: return # Already dead

	print("DEBUG: AnimatedUnit %s (%s) starting death sequence" % [unit_id, archetype])
	
	# Prevent further actions
	is_dead = true
	set_collision_layer_value(1, false) # No more selection/raycast hits
	
	_play_death_sound()
	
	# Connect to animation finished signal if not already connected
	if animation_player and not animation_player.is_connected("animation_finished", _on_death_animation_finished):
		animation_player.animation_finished.connect(_on_death_animation_finished)
	
	# Play death animation with debug feedback
	if animation_player:
		var available_anims = animation_player.get_animation_list()
		print("DEBUG: Available animations for death: %s" % available_anims)
		if animation_player.has_animation("die"):
			print("DEBUG: Playing 'die' animation directly")
			animation_player.play("die")
		else:
			print("DEBUG: Using fallback animation system for 'Die'")
			play_animation("Die")
	else:
		print("DEBUG: No animation player found for death sequence")
	
	# Don't stop physics process immediately - let death animation play
	# We'll handle cleanup in _on_death_animation_finished()

func _on_death_animation_finished(animation_name: String):
	"""Handle completion of death animation"""
	if animation_name == "die":
		print("DEBUG: Death animation completed for unit %s" % unit_id)
		
		# Now stop physics processing and disable further updates
		set_physics_process(false)
		
		# Optional: Add a slight delay before fading or removing
		await get_tree().create_timer(1.0).timeout
		
		# Fade out the unit gradually
		_fade_out_unit()

func _fade_out_unit():
	"""Gradually fade out the unit after death animation"""
	print("DEBUG: Starting fade out for unit %s" % unit_id)
	
	# Create a fade tween
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 2.0)
	
	# Wait for fade to complete then make completely invisible
	await tween.finished
	visible = false
	print("DEBUG: Unit %s fully faded out" % unit_id)

func _play_death_sound():
	var audio_manager = get_node_or_null("/root/DependencyContainer/AudioManager")
	if audio_manager:
		# In the future, this could be archetype-specific from the database
		audio_manager.play_sound_3d("res://assets/audio/sfx/unit_death_01.wav", global_position)