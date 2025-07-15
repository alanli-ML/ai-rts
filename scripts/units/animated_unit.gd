# AnimatedUnit.gd - Enhanced unit with animated character models
class_name AnimatedUnit
extends Unit

# Character model properties
var character_model: Node3D
var current_character_variant: String = "character-a"
var character_mesh_instances: Array[MeshInstance3D] = []

# Dependencies
var logger
var texture_manager: Node  # Changed from TextureManager to Node

# Weapon system
var weapon_attachment: WeaponAttachment
var weapon_database: WeaponDatabase
var current_weapon_type: String = ""
var is_weapon_equipped: bool = false

# Team identification
var team_material: StandardMaterial3D
var original_materials: Array[StandardMaterial3D] = []
var team_color_overlay: Color = Color.WHITE

# Animation system
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var animation_controller: Node  # New advanced animation controller
var current_animation: String = "idle"
var is_animation_playing: bool = false

# Character-to-archetype mapping
const CHARACTER_ASSIGNMENTS = {
	"scout": ["character-a", "character-c", "character-e", "character-g"],
	"soldier": ["character-b", "character-f", "character-h", "character-l"],
	"tank": ["character-j", "character-k", "character-n", "character-o"],
	"sniper": ["character-d", "character-i", "character-m", "character-q"],
	"medic": ["character-p", "character-r"],
	"engineer": ["character-a", "character-b", "character-c"]
}

# Team color schemes
const TEAM_COLORS = {
	1: Color(0.2, 0.4, 1.0),    # Blue team
	2: Color(1.0, 0.3, 0.2),    # Red team
	3: Color(0.2, 1.0, 0.4),    # Green team
	4: Color(1.0, 0.8, 0.2)     # Yellow team
}

# Animation names (based on Kenny character animations)
const ANIMATION_NAMES = {
	"idle": "idle",
	"walk": "walk",
	"run": "run",
	"attack": "attack",
	"reload": "reload",
	"ability": "ability",
	"death": "death"
}

# Performance settings
var lod_distance: float = 30.0
var is_in_lod_range: bool = true
var update_animations: bool = true

# Movement settings
var movement_threshold: float = 0.5

# Signals
signal character_loaded(character_variant: String)
signal animation_finished(animation_name: String)
signal team_color_applied(team_id: int, color: Color)
signal weapon_equipped(weapon_type: String)
signal weapon_fired(weapon_type: String, damage: float)
signal weapon_reloaded(weapon_type: String, new_ammo: int)
signal movement_completed(final_position: Vector3)

func _setup_logger() -> void:
	"""Setup logger reference from dependency container"""
	if has_node("/root/DependencyContainer"):
		var dependency_container = get_node("/root/DependencyContainer")
		if dependency_container.has_method("get_logger"):
			logger = dependency_container.get_logger()

func _ready() -> void:
	# Call parent _ready first
	super._ready()
	
	# Get logger from dependency container
	_setup_logger()
	
	# Setup weapon system
	_setup_weapon_system()
	
	# Load character model after parent setup
	_load_character_model()
	
	# Apply team colors
	_apply_team_colors()
	
	# Setup animation system
	_setup_animation_system()
	
	# Equip weapon after character is loaded
	_equip_archetype_weapon()
	
	if logger:
		logger.info("AnimatedUnit", "Animated unit %s (%s) ready with character %s" % [unit_id, archetype, current_character_variant])
	else:
		print("AnimatedUnit: Animated unit %s (%s) ready with character %s" % [unit_id, archetype, current_character_variant])

func _setup_weapon_system() -> void:
	"""Setup the weapon system components"""
	# Create texture manager first
	var texture_manager_script = load("res://scripts/units/texture_manager.gd")
	texture_manager = texture_manager_script.new()
	texture_manager.name = "TextureManager"
	add_child(texture_manager)
	
	# Create animation controller
	var animation_controller_script = load("res://scripts/units/animation_controller.gd")
	animation_controller = animation_controller_script.new()
	animation_controller.name = "AnimationController"
	add_child(animation_controller)
	
	# Connect animation controller signals
	animation_controller.animation_state_changed.connect(_on_animation_state_changed)
	animation_controller.animation_event_triggered.connect(_on_animation_event_triggered)
	animation_controller.animation_loop_completed.connect(_on_animation_loop_completed)
	
	# Create weapon database
	weapon_database = WeaponDatabase.new()
	weapon_database.name = "WeaponDatabase"
	add_child(weapon_database)
	
	# Create weapon attachment system
	weapon_attachment = WeaponAttachment.new()
	weapon_attachment.name = "WeaponAttachment"
	add_child(weapon_attachment)
	
	# Connect weapon signals
	weapon_attachment.weapon_equipped.connect(_on_weapon_equipped)
	weapon_attachment.weapon_fired.connect(_on_weapon_fired)
	weapon_attachment.weapon_reloaded.connect(_on_weapon_reloaded)
	weapon_attachment.weapon_attachment_failed.connect(_on_weapon_attachment_failed)

func _load_character_model() -> void:
	"""Load and setup the character model based on archetype"""
	
	# First, remove placeholder elements created by Unit base class
	await _remove_placeholder_elements()
	
	# Select character variant based on archetype
	var character_variants = CHARACTER_ASSIGNMENTS.get(archetype, ["character-a"])
	current_character_variant = character_variants[randi() % character_variants.size()]
	
	# Load character GLB file
	var character_path = "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/%s.glb" % current_character_variant
	var character_scene = load(character_path)
	
	if not character_scene:
		if logger:
			logger.error("AnimatedUnit", "Failed to load character model: %s" % character_path)
		else:
			print("AnimatedUnit ERROR: Failed to load character model: %s" % character_path)
		return
	
	# Instantiate character model
	character_model = character_scene.instantiate()
	if not character_model:
		if logger:
			logger.error("AnimatedUnit", "Failed to instantiate character model: %s" % character_path)
		else:
			print("AnimatedUnit ERROR: Failed to instantiate character model: %s" % character_path)
		return
	
	# Configure model
	character_model.name = "CharacterModel"
	var scale_factor = 2.0  # Kenny models are small, scale them up
	character_model.scale = Vector3.ONE * scale_factor
	
	# Add model to unit using call_deferred to avoid timing issues
	call_deferred("add_child", character_model)
	
	# Wait for model to be added to tree
	await get_tree().process_frame
	
	# Now create collision shape for the character model
	_create_character_collision_shape(scale_factor)
	
	# Find mesh instances for material management
	_collect_mesh_instances()
	
	# Find animation components
	_find_animation_components()
	
	# Apply texture to character
	if texture_manager:
		texture_manager.apply_character_texture(character_model, current_character_variant)
	
	if logger:
		logger.info("AnimatedUnit", "Character model loaded: %s (scale: %s)" % [current_character_variant, scale_factor])
	else:
		print("AnimatedUnit: Character model loaded: %s (scale: %s)" % [current_character_variant, scale_factor])
	
	character_loaded.emit(current_character_variant)

func _remove_placeholder_elements() -> void:
	"""Remove placeholder mesh and collision shape created by Unit base class"""
	
	# Wait a frame to ensure Unit._ready() has completed
	await get_tree().process_frame
	
	# Remove ALL existing children that are placeholder elements
	var children_to_remove = []
	
	for child in get_children():
		# Remove placeholder MeshInstance3D (usually cylinder)
		if child is MeshInstance3D and (child.name == "UnitMesh" or child.name.contains("Mesh")):
			children_to_remove.append(child)
			if logger:
				logger.info("AnimatedUnit", "Queuing placeholder mesh '%s' for removal" % child.name)
			else:
				print("AnimatedUnit: Queuing placeholder mesh '%s' for removal" % child.name)
		
		# Remove placeholder CollisionShape3D
		elif child is CollisionShape3D and child.name == "CollisionShape3D":
			children_to_remove.append(child)
			if logger:
				logger.info("AnimatedUnit", "Queuing placeholder collision shape '%s' for removal" % child.name)
			else:
				print("AnimatedUnit: Queuing placeholder collision shape '%s' for removal" % child.name)
	
	# Actually remove the placeholder elements
	for child in children_to_remove:
		child.queue_free()
	
	# Wait another frame to ensure removal is processed
	await get_tree().process_frame
	
	if logger:
		logger.info("AnimatedUnit", "Removed %d placeholder elements" % children_to_remove.size())
	else:
		print("AnimatedUnit: Removed %d placeholder elements" % children_to_remove.size())

func _create_character_collision_shape(scale_factor: float) -> void:
	"""Create collision shape that matches the character model dimensions"""
	
	# Create new collision shape for the character
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "CharacterCollisionShape3D"  # Use different name than placeholder
	
	# Use a box shape that better represents the character dimensions
	var box_shape = BoxShape3D.new()
	# Kenny characters are roughly 1 unit wide, 2 units tall, 1 unit deep
	# Scale according to the character model scale
	box_shape.size = Vector3(
		1.0 * scale_factor,   # Width
		2.0 * scale_factor,   # Height 
		1.0 * scale_factor    # Depth
	)
	collision_shape.shape = box_shape
	
	# Position the collision shape to match character center
	collision_shape.position.y = 1.0 * scale_factor  # Center at character height/2
	
	# Add collision shape to unit using call_deferred to avoid timing issues
	call_deferred("add_child", collision_shape)
	
	# Set collision layers for selection detection after the shape is added
	call_deferred("_configure_collision_layers")
	
	if logger:
		logger.info("AnimatedUnit", "Created character collision shape: size %s, position %s" % [box_shape.size, collision_shape.position])
	else:
		print("AnimatedUnit: Created character collision shape: size %s, position %s" % [box_shape.size, collision_shape.position])

func _configure_collision_layers() -> void:
	"""Configure collision layers for proper selection detection"""
	
	# Wait a frame to ensure collision shape is fully added
	await get_tree().process_frame
	
	# Set collision layers for selection detection
	# Layer 1 is used by the selection system for raycast detection
	collision_layer = 1  # This unit exists on layer 1 (selection layer)
	collision_mask = 2   # This unit collides with layer 2 (environment/terrain)
	
	if logger:
		logger.info("AnimatedUnit", "Configured collision layers: layer %d, mask %d" % [collision_layer, collision_mask])
	else:
		print("AnimatedUnit: Configured collision layers: layer %d, mask %d" % [collision_layer, collision_mask])

func _find_animation_components() -> void:
	"""Find animation player and skeleton in the character model"""
	if not character_model:
		return
	
	# Search for AnimationPlayer
	animation_player = _find_child_recursive(character_model, "AnimationPlayer") as AnimationPlayer
	if not animation_player:
		if logger:
			logger.warning("AnimatedUnit", "No AnimationPlayer found in character model %s" % current_character_variant)
		else:
			print("AnimatedUnit WARNING: No AnimationPlayer found in character model %s" % current_character_variant)
	
	# Search for Skeleton3D
	skeleton = _find_child_recursive(character_model, "Skeleton3D") as Skeleton3D
	if not skeleton:
		if logger:
			logger.warning("AnimatedUnit", "No Skeleton3D found in character model %s" % current_character_variant)
		else:
			print("AnimatedUnit WARNING: No Skeleton3D found in character model %s" % current_character_variant)
	
	# Initialize animation controller if we have an animation player
	if animation_player and animation_controller:
		animation_controller.initialize(self, character_model, animation_player)

func _find_child_recursive(node: Node, child_name: String) -> Node:
	"""Recursively find a child node by name"""
	if node.name == child_name:
		return node
	
	for child in node.get_children():
		var result = _find_child_recursive(child, child_name)
		if result:
			return result
	
	return null

func _collect_mesh_instances() -> void:
	"""Find and collect all mesh instances in the character model"""
	character_mesh_instances.clear()
	
	if not character_model:
		return
		
	# Recursively find all MeshInstance3D nodes
	_collect_mesh_instances_recursive(character_model)
	
	if logger:
		logger.info("AnimatedUnit", "Found %d mesh instances in character model" % character_mesh_instances.size())
	else:
		print("AnimatedUnit: Found %d mesh instances in character model" % character_mesh_instances.size())

func _collect_mesh_instances_recursive(node: Node) -> void:
	"""Recursively collect mesh instances from a node tree"""
	if node is MeshInstance3D:
		character_mesh_instances.append(node as MeshInstance3D)
	
	for child in node.get_children():
		_collect_mesh_instances_recursive(child)

func _apply_team_colors() -> void:
	"""Apply team colors to the character model while preserving textures"""
	if not character_model or not texture_manager:
		return
	
	var team_color = TEAM_COLORS.get(team_id, Color.WHITE)
	team_color_overlay = team_color
	
	# Use texture manager to apply team colors with texture preservation
	texture_manager.apply_team_color_with_texture(character_model, current_character_variant, team_color)
	
	if logger:
		logger.info("AnimatedUnit", "Applied team color %s to unit %s with texture preservation" % [team_color, unit_id])
	else:
		print("AnimatedUnit: Applied team color %s to unit %s with texture preservation" % [team_color, unit_id])
	team_color_applied.emit(team_id, team_color)

func _setup_animation_system() -> void:
	"""Setup the animation system"""
	if not animation_player:
		return
	
	# Connect animation finished signal
	if not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)
	
	# Start with idle animation
	play_animation("idle", true)

func _equip_archetype_weapon() -> void:
	"""Equip weapon based on unit archetype"""
	if not weapon_database or not weapon_attachment:
		if logger:
			logger.warning("AnimatedUnit", "Weapon system not ready for unit %s" % unit_id)
		else:
			print("AnimatedUnit WARNING: Weapon system not ready for unit %s" % unit_id)
		return
	
	# Get weapon for archetype
	var weapon_type = weapon_database.get_weapon_for_archetype(archetype, "primary")
	
	# Equip weapon
	if weapon_attachment.equip_weapon(self, weapon_type, team_id):
		current_weapon_type = weapon_type
		is_weapon_equipped = true
		
		# Add recommended attachments
		var recommended_attachments = weapon_database.get_recommended_attachments(archetype, weapon_type)
		for attachment in recommended_attachments:
			if randf() < 0.6:  # 60% chance to add each recommended attachment
				weapon_attachment.add_attachment(attachment)
		
		if logger:
			logger.info("AnimatedUnit", "Equipped weapon %s with attachments to unit %s" % [weapon_type, unit_id])
		else:
			print("AnimatedUnit: Equipped weapon %s with attachments to unit %s" % [weapon_type, unit_id])
	else:
		if logger:
			logger.error("AnimatedUnit", "Failed to equip weapon %s to unit %s" % [weapon_type, unit_id])
		else:
			print("AnimatedUnit ERROR: Failed to equip weapon %s to unit %s" % [weapon_type, unit_id])

func _create_fallback_model() -> void:
	"""Create a fallback model if character loading fails"""
	if logger:
		logger.warning("AnimatedUnit", "Creating fallback model for unit %s" % unit_id)
	else:
		print("AnimatedUnit WARNING: Creating fallback model for unit %s" % unit_id)
	
	# Create a simple colored capsule as fallback
	var fallback_mesh = MeshInstance3D.new()
	fallback_mesh.name = "FallbackMesh"
	fallback_mesh.mesh = CapsuleMesh.new()
	fallback_mesh.mesh.height = 2.0
	fallback_mesh.mesh.top_radius = 0.5
	fallback_mesh.mesh.bottom_radius = 0.5
	
	var material = StandardMaterial3D.new()
	material.albedo_color = TEAM_COLORS.get(team_id, Color.WHITE)
	fallback_mesh.material_override = material
	
	add_child(fallback_mesh)
	character_model = fallback_mesh

func play_animation(animation_name: String, force: bool = false) -> void:
	"""Play animation using the advanced animation controller"""
	if not animation_controller:
		# Fallback to basic animation system
		_play_basic_animation(animation_name, force)
		return
	
	# Map old animation names to animation controller events
	match animation_name:
		"idle":
			if is_moving:
				animation_controller.stop_moving()
			# Idle is the default state, no specific event needed
		"walk":
			animation_controller.start_moving(1.0)  # Low speed for walk
		"run":
			animation_controller.start_moving(4.0)  # High speed for run
		"attack":
			animation_controller.start_attack()
		"reload":
			animation_controller.start_reload()
		_:
			# For unknown animations, use the basic system
			_play_basic_animation(animation_name, force)

func _play_basic_animation(animation_name: String, force: bool = false) -> void:
	"""Fallback basic animation system for compatibility"""
	if not animation_player:
		return
	
	if not force and current_animation == animation_name and is_animation_playing:
		return
	
	current_animation = animation_name
	
	if animation_player.has_animation(animation_name):
		animation_player.play(animation_name)
		is_animation_playing = true
		
		if logger:
			logger.debug("AnimatedUnit", "Playing animation %s for unit %s" % [animation_name, unit_id])
		else:
			print("AnimatedUnit: Playing animation %s for unit %s" % [animation_name, unit_id])
	else:
		if logger:
			logger.warning("AnimatedUnit", "Animation %s not found for character %s" % [animation_name, current_character_variant])
		else:
			print("AnimatedUnit WARNING: Animation %s not found for character %s" % [animation_name, current_character_variant])

# Note: play_animation_sequence removed - AnimationController handles sequences automatically

func _on_animation_finished(animation_name: String) -> void:
	"""Handle animation finished event"""
	# This signal is now handled by AnimationController.animation_loop_completed
	pass

func _on_animation_state_changed(old_state: int, new_state: int) -> void:
	"""Handle animation state changes"""
	# Get state names using method calls instead of enum access
	var old_state_name = "UNKNOWN"
	var new_state_name = "UNKNOWN"
	
	if animation_controller and animation_controller.has_method("get_current_state_name"):
		# We can't easily get the old state name, so we'll use the current one
		new_state_name = animation_controller.get_current_state_name()
		old_state_name = "PREVIOUS_STATE"  # Placeholder
		
	if logger:
		logger.debug("AnimatedUnit", "Unit %s animation: %s → %s" % [unit_id, old_state_name, new_state_name])
	else:
		print("AnimatedUnit: Unit %s animation: %s → %s" % [unit_id, old_state_name, new_state_name])
	
	# Handle state-specific logic using string comparison
	if new_state_name == "DEATH":
		# Disable further interactions
		set_process(false)
	elif new_state_name == "ATTACK":
		# Ensure weapon is firing
		if weapon_attachment and not weapon_attachment.is_firing:
			weapon_attachment.fire_weapon()
	elif new_state_name == "VICTORY":
		# Could trigger celebration effects here
		pass

func _on_animation_event_triggered(event: int) -> void:
	"""Handle animation events"""
	# Use simple event logging without trying to access enum names
	if logger:
		logger.debug("AnimatedUnit", "Unit %s animation event triggered: %s" % [unit_id, event])

func _on_animation_loop_completed(animation_name: String) -> void:
	"""Handle animation loop completion"""
	# This replaces the old animation_finished signal handler
	pass

func _physics_process(delta: float) -> void:
	# Call parent physics process
	super._physics_process(delta)
	
	# Update LOD if needed
	_update_lod()

# Note: _update_context_animation removed - AnimationController handles this automatically

func _update_lod() -> void:
	"""Update level of detail based on camera distance"""
	if not character_model:
		return
	
	# Find camera
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	var distance = global_position.distance_to(camera.global_position)
	var was_in_range = is_in_lod_range
	is_in_lod_range = distance < lod_distance
	
	# Update animation updates based on distance
	if was_in_range != is_in_lod_range:
		update_animations = is_in_lod_range
		if animation_player:
			animation_player.speed_scale = 1.0 if is_in_lod_range else 0.5

# Weapon system integration
func attack_target(target: Unit) -> void:
	"""Enhanced attack with weapon system"""
	if not target or current_health <= 0 or target.current_health <= 0:
		return
	
	if not is_weapon_equipped or not weapon_attachment:
		# Fall back to parent attack if no weapon
		super.attack_target(target)
		return
	
	var distance = global_position.distance_to(target.global_position)
	var weapon_stats = weapon_attachment.get_weapon_stats()
	var weapon_range = weapon_stats.get("range", attack_range)
	
	if distance > weapon_range:
		# Move closer to target
		move_to(target.global_position)
		target_unit = target
		return
	
	# Check if weapon can fire
	if not weapon_attachment.can_fire():
		return
	
	# Fire weapon
	var fire_data = weapon_attachment.fire()
	if fire_data.is_empty():
		return
	
	# Apply damage with weapon stats
	var weapon_damage = fire_data.get("damage", attack_damage)
	var weapon_accuracy = fire_data.get("accuracy", 0.85)
	
	# Apply accuracy check
	if randf() <= weapon_accuracy:
		target.take_damage(weapon_damage)
		
		if logger:
			logger.debug("AnimatedUnit", "Unit %s hit %s with %s for %s damage" % [unit_id, target.unit_id, current_weapon_type, weapon_damage])
		else:
			print("AnimatedUnit: Unit %s hit %s with %s for %s damage" % [unit_id, target.unit_id, current_weapon_type, weapon_damage])
		
		# Play attack animation
		play_animation("attack")
	else:
		if logger:
			logger.debug("AnimatedUnit", "Unit %s missed %s with %s" % [unit_id, target.unit_id, current_weapon_type])
		else:
			print("AnimatedUnit: Unit %s missed %s with %s" % [unit_id, target.unit_id, current_weapon_type])
	
	change_state(GameEnums.UnitState.ATTACKING)

func get_character_variant() -> String:
	"""Get the current character variant"""
	return current_character_variant

func get_animation_state() -> String:
	"""Get the current animation state"""
	if animation_controller and animation_controller.has_method("get_current_state_name"):
		return animation_controller.get_current_state_name()
	else:
		return current_animation  # Fallback to basic animation state

func get_skeleton() -> Skeleton3D:
	"""Get the character skeleton for weapon attachment"""
	return skeleton

func get_hand_bone_id() -> int:
	"""Get the bone ID for the right hand (for weapon attachment)"""
	if not skeleton:
		return -1
	
	# Common hand bone names to try
	var hand_bone_names = ["hand_right", "Hand_R", "RightHand", "hand.R"]
	
	for bone_name in hand_bone_names:
		var bone_id = skeleton.find_bone(bone_name)
		if bone_id != -1:
			return bone_id
	
	if logger:
		logger.warning("AnimatedUnit", "No hand bone found for weapon attachment on %s" % current_character_variant)
	else:
		print("AnimatedUnit WARNING: No hand bone found for weapon attachment on %s" % current_character_variant)
	return -1

func get_weapon_stats() -> Dictionary:
	"""Get current weapon statistics"""
	if not weapon_attachment:
		return {}
	
	return weapon_attachment.get_weapon_stats()

func get_weapon_muzzle_position() -> Vector3:
	"""Get weapon muzzle position for projectile effects"""
	if not weapon_attachment:
		return global_position
	
	return weapon_attachment.get_muzzle_position()

func set_team_color_intensity(intensity: float) -> void:
	"""Set the intensity of team color overlay"""
	intensity = clamp(intensity, 0.0, 1.0)
	
	for i in range(character_mesh_instances.size()):
		if i < original_materials.size():
			var mesh_instance = character_mesh_instances[i]
			var original_material = original_materials[i]
			var material = mesh_instance.material_override as StandardMaterial3D
			
			if material and original_material:
				var team_color = TEAM_COLORS.get(team_id, Color.WHITE)
				material.albedo_color = original_material.albedo_color.lerp(team_color, intensity * 0.3)
				material.emission = team_color * intensity * 0.1

func die() -> void:
	"""Override die to play death animation"""
	if not is_dead:
		play_animation("death")
		await animation_finished
	
	# Call parent die function
	super.die()

# Weapon signal handlers
func _on_weapon_equipped(weapon_type: String) -> void:
	"""Handle weapon equipped event"""
	current_weapon_type = weapon_type
	is_weapon_equipped = true
	
	# Apply weapon texture
	if weapon_attachment and weapon_attachment.weapon_model and texture_manager:
		var team_color = TEAM_COLORS.get(team_id, Color.WHITE)
		texture_manager.apply_weapon_texture_with_team_color(weapon_attachment.weapon_model, team_color)
	
	weapon_equipped.emit(weapon_type)
	
	if logger:
		logger.info("AnimatedUnit", "Weapon %s equipped to unit %s with textures" % [weapon_type, unit_id])
	else:
		print("AnimatedUnit: Weapon %s equipped to unit %s with textures" % [weapon_type, unit_id])

func _on_weapon_fired(weapon_type: String, damage: float) -> void:
	"""Handle weapon fired event with animation integration"""
	if animation_controller and animation_controller.has_method("start_attack"):
		# Start attack animation if not already attacking
		# We'll use method calls instead of trying to access enum values
		var current_state_name = animation_controller.get_current_state_name() if animation_controller.has_method("get_current_state_name") else ""
		
		if current_state_name != "ATTACK" and current_state_name != "ATTACK_MOVING":
			animation_controller.start_attack()
	
	weapon_fired.emit(weapon_type, damage)
	
	if logger:
		logger.debug("AnimatedUnit", "Unit %s fired weapon %s for %s damage" % [unit_id, weapon_type, damage])
	else:
		print("AnimatedUnit: Unit %s fired weapon %s for %s damage" % [unit_id, weapon_type, damage])

func _on_weapon_reloaded(weapon_type: String, new_ammo: int) -> void:
	"""Handle weapon reloaded event with animation integration"""
	if animation_controller:
		animation_controller.finish_reload()
	
	weapon_reloaded.emit(weapon_type, new_ammo)
	
	if logger:
		logger.info("AnimatedUnit", "Unit %s reloaded weapon %s (ammo: %s)" % [unit_id, weapon_type, new_ammo])
	else:
		print("AnimatedUnit: Unit %s reloaded weapon %s (ammo: %s)" % [unit_id, weapon_type, new_ammo])

func _on_weapon_attachment_failed(reason: String) -> void:
	"""Handle weapon attachment failure"""
	if logger:
		logger.error("AnimatedUnit", "Weapon attachment failed for unit %s: %s" % [unit_id, reason])
	else:
		print("AnimatedUnit ERROR: Weapon attachment failed for unit %s: %s" % [unit_id, reason])

# Debug functions
func debug_list_animations() -> Array[String]:
	"""List all available animations for debugging"""
	var animations: Array[String] = []
	if animation_player:
		var animation_list = animation_player.get_animation_list()
		for animation_name in animation_list:
			animations.append(animation_name)
	return animations

func debug_character_info() -> Dictionary:
	"""Get comprehensive debug information about the animated unit"""
	var base_info = {
		"unit_id": unit_id,
		"archetype": archetype,
		"team_id": team_id,
		"current_character_variant": current_character_variant,
		"character_loaded": character_model != null,
		"health": "%s/%s" % [current_health, max_health],
		"state": GameEnums.UnitState.keys()[current_state],
		"position": global_position
	}
	
	# Add animation controller debug info
	if animation_controller:
		base_info["animation_controller"] = animation_controller.debug_info()
	else:
		base_info["animation_controller"] = {"status": "not_available"}
	
	# Add weapon info
	if weapon_attachment:
		base_info["weapon_info"] = {
			"is_equipped": weapon_attachment.is_weapon_equipped,
			"weapon_type": current_weapon_type,
			"ammo": "%s/%s" % [weapon_attachment.current_ammo, weapon_attachment.max_ammo],
			"attachments": weapon_attachment.attachment_count,
			"muzzle_position": weapon_attachment.get_muzzle_position()
		}
	
	# Add texture manager info
	if texture_manager:
		base_info["texture_manager"] = {"status": "available"}
	
	return base_info

# Add a flag to track movement state for animation controller
var was_moving: bool = false 

# Add the missing methods for movement, damage, and death integration

# Override the movement handling from the base Unit class
func _handle_movement(delta: float) -> void:
	"""Handle unit movement with animation integration"""
	if not is_moving or not movement_target:
		if animation_controller and was_moving:
			animation_controller.stop_moving()
			was_moving = false
		return
	
	var distance_to_target = global_position.distance_to(movement_target)
	
	if distance_to_target < movement_threshold:
		# Reached target
		is_moving = false
		movement_target = Vector3.ZERO
		
		if animation_controller:
			animation_controller.stop_moving()
			was_moving = false
		
		if logger:
			logger.debug("AnimatedUnit", "Unit %s reached movement target" % unit_id)
		else:
			print("AnimatedUnit: Unit %s reached movement target" % unit_id)
		
		movement_completed.emit(global_position)
		return
	
	# Calculate movement
	var direction = (movement_target - global_position).normalized()
	var movement_distance = movement_speed * delta
	
	# Move towards target
	global_position = global_position.move_toward(movement_target, movement_distance)
	
	# Update animation controller with movement data
	if animation_controller:
		if not was_moving:
			animation_controller.start_moving(movement_speed, direction)
			was_moving = true
		else:
			# Update speed if it changed significantly
			if abs(animation_controller.current_speed - movement_speed) > 0.5:
				animation_controller.update_speed(movement_speed)

# Override damage handling from base Unit class
func take_damage(damage: float) -> void:
	"""Take damage with animation integration"""
	if current_health <= 0:
		return  # Already dead
	
	var old_health = current_health
	current_health = max(0, current_health - damage)
	
	# Notify animation controller of damage
	if animation_controller:
		animation_controller.take_damage(damage, current_health, max_health)
	
	if logger:
		logger.info("AnimatedUnit", "Unit %s took %s damage (%s -> %s HP)" % [unit_id, damage, old_health, current_health])
	else:
		print("AnimatedUnit: Unit %s took %s damage (%s -> %s HP)" % [unit_id, damage, old_health, current_health])
	
	health_changed.emit(unit_id, current_health)
	
	# Handle death
	if current_health <= 0:
		_handle_death()

func _handle_death() -> void:
	"""Handle unit death with animation"""
	if current_state == GameEnums.UnitState.DEAD:
		return  # Already handled
	
	current_state = GameEnums.UnitState.DEAD
	
	# Trigger death animation
	if animation_controller:
		animation_controller.die()
	
	if logger:
		logger.info("AnimatedUnit", "Unit %s died" % unit_id)
	else:
		print("AnimatedUnit: Unit %s died" % unit_id)
	
	unit_died.emit(unit_id)

# Enhanced auto-reload with animation integration
func _handle_auto_reload() -> void:
	"""Handle automatic reloading when out of ammo"""
	if weapon_attachment and weapon_attachment.current_ammo <= 0:
		if animation_controller:
			animation_controller.start_reload()
		
		weapon_attachment.reload_weapon()

# Override the move_to method to integrate with AnimationController
func move_to(target: Vector3) -> void:
	"""Move to target position with animation integration"""
	# Call parent implementation first
	super.move_to(target)
	
	# Additional animation controller logic handled in _handle_movement()

# Fix the _find_node_recursive method (was incorrectly named in the earlier edit)
func _find_node_recursive(node: Node, target_name: String) -> Node:
	"""Recursively find a node by name"""
	if node.name == target_name:
		return node
	
	for child in node.get_children():
		var result = _find_node_recursive(child, target_name)
		if result:
			return result
	
	return null 