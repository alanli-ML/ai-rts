# WeaponAttachment.gd - Modular weapon system for animated units
class_name WeaponAttachment
extends Node3D

const WeaponDatabase = preload("res://scripts/units/weapon_database.gd")
var weapon_db = WeaponDatabase.new()

# Weapon properties
var weapon_model: Node3D
var weapon_type: String = "blaster-a"
var archetype_specific: bool = true
var attachment_bone: String = "hand_right"
var attachment_bone_id: int = -1

# Weapon attachments
var scope: Node3D
var clip: Node3D
var accessories: Array[Node3D] = []

# Weapon statistics
var damage: float = 25.0
var range: float = 15.0
var fire_rate: float = 1.0
var accuracy: float = 0.85
var reload_time: float = 2.0

# Attachment points
var scope_attachment_point: Node3D
var clip_attachment_point: Node3D
var muzzle_point: Node3D

# Weapon state
var is_equipped: bool = false
var is_firing: bool = false
var current_ammo: int = 30
var max_ammo: int = 30
var last_fire_time: float = 0.0

# Projectile
const PROJECTILE_SCENE = preload("res://scenes/fx/Projectile.tscn")

# Parent references
var parent_unit: Node3D
var parent_skeleton: Skeleton3D
var logger

# Team colors for weapon materials
var team_colors: Dictionary = {
	1: Color(0.2, 0.4, 1.0),    # Blue team
	2: Color(1.0, 0.3, 0.2),    # Red team
	3: Color(0.2, 1.0, 0.4),    # Green team
	4: Color(1.0, 0.8, 0.2)     # Yellow team
}

# Weapon asset paths
const WEAPON_BASE_PATH = "res://assets/kenney/kenney_blaster-kit-2/Models/GLB format/"
const ATTACHMENT_MODELS = {
	"scope_large_a": "scope-large-a.glb",
	"scope_large_b": "scope-large-b.glb",
	"scope_small": "scope-small.glb",
	"clip_large": "clip-large.glb",
	"clip_small": "clip-small.glb"
}

# Signals
signal weapon_equipped(weapon_type: String)
signal weapon_fired(weapon_type: String, damage: float)
signal weapon_reloaded(weapon_type: String, ammo: int)
signal attachment_added(attachment_type: String)
signal weapon_attachment_failed(reason: String)

func _ready() -> void:
	# Setup logger
	_setup_logger()
	
	# Create attachment points
	_create_attachment_points()
	
	if logger:
		logger.debug("WeaponAttachment", "Weapon attachment system initialized")
	else:
		print("WeaponAttachment: Weapon attachment system initialized")

func _setup_logger() -> void:
	"""Setup logger reference from dependency container"""
	if has_node("/root/DependencyContainer"):
		var dependency_container = get_node("/root/DependencyContainer")
		if dependency_container.has_method("get_logger"):
			logger = dependency_container.get_logger()

func _create_attachment_points() -> void:
	"""Create attachment points for weapon accessories"""
	# Scope attachment point
	scope_attachment_point = Node3D.new()
	scope_attachment_point.name = "ScopeAttachmentPoint"
	scope_attachment_point.position = Vector3(0, 0.1, 0.2)
	add_child(scope_attachment_point)
	
	# Clip attachment point
	clip_attachment_point = Node3D.new()
	clip_attachment_point.name = "ClipAttachmentPoint"
	clip_attachment_point.position = Vector3(0, -0.1, 0.1)
	add_child(clip_attachment_point)
	
	# Muzzle point for effects
	muzzle_point = Node3D.new()
	muzzle_point.name = "MuzzlePoint"
	muzzle_point.position = Vector3(0, 0, 0.5)
	add_child(muzzle_point)

func equip_weapon(unit: Node3D, weapon_variant: String, team_id: int = 1) -> bool:
	"""Equip a weapon to a unit"""
	#print("DEBUG: WeaponAttachment.equip_weapon() called - unit: %s, weapon: %s, team: %d" % [unit.name if unit else "null", weapon_variant, team_id])
	if not unit:
		_log_error("Cannot equip weapon: unit is null")
		return false
	
	parent_unit = unit
	weapon_type = weapon_variant
	
	# Get skeleton from unit
	if unit.has_method("get_skeleton"):
		parent_skeleton = unit.get_skeleton()
		#print("DEBUG: WeaponAttachment.equip_weapon() - unit has get_skeleton method, result: %s" % ("found" if parent_skeleton else "null"))
	else:
		print("DEBUG: WeaponAttachment.equip_weapon() - unit has no get_skeleton method")
	
	# Load weapon model
	#print("DEBUG: WeaponAttachment.equip_weapon() - loading weapon model")
	if not _load_weapon_model(weapon_variant):
		_log_error("Failed to load weapon model: %s" % weapon_variant)
		return false
	
	# Try skeleton attachment first, fall back to static if no skeleton
	var attachment_success = false
	if parent_skeleton:
		#print("DEBUG: WeaponAttachment.equip_weapon() - attempting skeleton attachment")
		attachment_success = _attach_to_skeleton()
		#print("DEBUG: WeaponAttachment.equip_weapon() - skeleton attachment result: %s" % ("success" if attachment_success else "failed"))
	
	if not attachment_success:
		#print("DEBUG: WeaponAttachment.equip_weapon() - attempting static fallback attachment")
		# Use static fallback positioning
		attachment_success = _attach_weapon_static_fallback()
		#print("DEBUG: WeaponAttachment.equip_weapon() - static attachment result: %s" % ("success" if attachment_success else "failed"))
	
	if not attachment_success:
		_log_error("Failed to attach weapon using any method")
		return false
	
	# Apply team colors
	#print("DEBUG: WeaponAttachment.equip_weapon() - applying team colors")
	_apply_team_colors(team_id)
	
	# Load weapon stats
	#print("DEBUG: WeaponAttachment.equip_weapon() - loading weapon stats")
	_load_weapon_stats(weapon_variant)
	
	is_equipped = true
	
	if logger:
		logger.info("WeaponAttachment", "Equipped weapon %s to unit %s" % [weapon_variant, unit.name])
	else:
		print("WeaponAttachment: Equipped weapon %s to unit %s" % [weapon_variant, unit.name])
	
	#print("DEBUG: WeaponAttachment.equip_weapon() - weapon equipped successfully (damage: %.1f, ammo: %d/%d)" % [damage, current_ammo, max_ammo])
	weapon_equipped.emit(weapon_type)
	return true

func _load_weapon_model(weapon_variant: String) -> bool:
	"""Load the weapon model from assets"""
	var weapon_path = WEAPON_BASE_PATH + weapon_variant + ".glb"
	
	# Try to load the weapon scene
	var weapon_scene = load(weapon_path)
	if not weapon_scene:
		_log_error("Failed to load weapon asset: %s" % weapon_path)
		# Try fallback weapon if available
		weapon_scene = _try_fallback_weapon(weapon_variant)
		if not weapon_scene:
			return false
	
	# Remove existing weapon model
	if weapon_model and is_instance_valid(weapon_model):
		weapon_model.queue_free()
		weapon_model = null
	
	# Instantiate weapon model with error checking
	weapon_model = weapon_scene.instantiate()
	if not weapon_model:
		_log_error("Failed to instantiate weapon model: %s" % weapon_variant)
		return false
		
	weapon_model.name = "WeaponModel"
	
	# Scale weapon appropriately
	var scale_factor = 1.0  # Weapons are already properly scaled
	weapon_model.scale = Vector3(scale_factor, scale_factor, scale_factor)
	
	# Add to scene with error checking
	if is_inside_tree():
		add_child(weapon_model)
	else:
		_log_error("WeaponAttachment not in scene tree - cannot add weapon model")
		weapon_model.queue_free()
		weapon_model = null
		return false
	
	return true

func _try_fallback_weapon(weapon_variant: String) -> PackedScene:
	"""Try to load a fallback weapon if the requested one fails"""
	# Try basic blaster variants as fallbacks
	var fallback_weapons = ["blaster-a", "blaster-b", "blaster-c"]
	
	for fallback in fallback_weapons:
		if fallback != weapon_variant:  # Don't try the same weapon again
			var fallback_path = WEAPON_BASE_PATH + fallback + ".glb"
			var fallback_scene = load(fallback_path)
			if fallback_scene:
				if logger:
					logger.warning("WeaponAttachment", "Using fallback weapon %s for %s" % [fallback, weapon_variant])
				else:
					print("WeaponAttachment: Using fallback weapon %s for %s" % [fallback, weapon_variant])
				return fallback_scene
	
	return null

func _attach_to_skeleton() -> bool:
	"""Attach weapon to character skeleton"""
	if not parent_skeleton:
		return false
	
	# Get hand bone ID
	if parent_unit.has_method("get_hand_bone_id"):
		attachment_bone_id = parent_unit.get_hand_bone_id()
	else:
		# Try to find hand bone manually
		attachment_bone_id = _find_hand_bone()
	
	if attachment_bone_id == -1:
		_log_error("No hand bone found for weapon attachment")
		return false
	
	# Create a BoneAttachment3D node
	var bone_attachment = BoneAttachment3D.new()
	bone_attachment.name = "WeaponBoneAttachment"
	bone_attachment.bone_name = parent_skeleton.get_bone_name(attachment_bone_id)
	bone_attachment.bone_idx = attachment_bone_id
	
	# Add bone attachment to skeleton
	parent_skeleton.add_child(bone_attachment)
	
	# Reparent this weapon attachment to the bone attachment
	get_parent().remove_child(self)
	bone_attachment.add_child(self)
	
	# Adjust weapon position and rotation for proper grip
	_adjust_weapon_positioning()
	
	return true

func _find_hand_bone() -> int:
	"""Find the hand bone for weapon attachment"""
	if not parent_skeleton:
		return -1
	
	# Common hand bone names to try
	var hand_bone_names = [
		"hand_right", "Hand_R", "RightHand", "hand.R",
		"hand_r", "HandR", "Right_Hand", "R_Hand"
	]
	
	for bone_name in hand_bone_names:
		var bone_id = parent_skeleton.find_bone(bone_name)
		if bone_id != -1:
			return bone_id
	
	return -1

func _adjust_weapon_positioning() -> void:
	"""Adjust weapon position and rotation for proper grip"""
	# Standard weapon positioning (can be customized per weapon type)
	position = Vector3(0.05, 0.05, 0.1)  # Slight offset from hand
	rotation_degrees = Vector3(0, -90, 0)  # Rotate to face forward (-Z)
	
	# Weapon-specific adjustments
	match weapon_type:
		"blaster-a", "blaster-b", "blaster-c":  # Pistols
			position = Vector3(0.02, 0.02, 0.08)
			rotation_degrees = Vector3(0, 90, 0)
		"blaster-d", "blaster-i", "blaster-m":  # Rifles
			position = Vector3(0.08, 0.08, 0.15)
			rotation_degrees = Vector3(0, 90, 0)
		"blaster-j", "blaster-k", "blaster-n":  # Heavy weapons
			position = Vector3(0.1, 0.1, 0.2)
			rotation_degrees = Vector3(0, 90, 0)
		_:  # Default positioning
			position = Vector3(0.05, 0.05, 0.1)
			rotation_degrees = Vector3(0, 90, 0)

func _apply_team_colors(team_id: int) -> void:
	"""Apply team colors to weapon materials"""
	if not weapon_model:
		return
	
	var team_color = team_colors.get(team_id, Color.WHITE)
	
	# Find all mesh instances in weapon model
	var mesh_instances = _get_mesh_instances_recursive(weapon_model)
	
	for mesh_instance in mesh_instances:
		if not is_instance_valid(mesh_instance) or not mesh_instance.mesh:
			continue
			
		# Get existing material or create from mesh surface material
		var material = mesh_instance.get_surface_override_material(0)
		
		# If no override material, try to get the mesh's built-in material
		if not material and mesh_instance.mesh.surface_get_material(0):
			material = mesh_instance.mesh.surface_get_material(0)
		
		# Create new material if none exists
		if not material:
			material = StandardMaterial3D.new()
			# Set base weapon appearance
			material.albedo_color = Color(0.6, 0.6, 0.6)  # Base weapon color
			material.metallic = 0.6
			material.roughness = 0.4
			material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		
		# Always duplicate material to avoid affecting other instances
		if material:
			material = material.duplicate()
			
			# Apply team color accent
			if material is StandardMaterial3D:
				var std_material = material as StandardMaterial3D
				std_material.emission_enabled = true
				std_material.emission = team_color * 0.1
				std_material.metallic = 0.6
				std_material.roughness = 0.4
			
			mesh_instance.set_surface_override_material(0, material)

func _get_mesh_instances_recursive(node: Node) -> Array[MeshInstance3D]:
	"""Recursively collect all MeshInstance3D nodes"""
	var mesh_instances: Array[MeshInstance3D] = []
	
	if node is MeshInstance3D:
		mesh_instances.append(node as MeshInstance3D)
	
	for child in node.get_children():
		mesh_instances.append_array(_get_mesh_instances_recursive(child))
	
	return mesh_instances

func _load_weapon_stats(weapon_variant: String) -> void:
	"""Load weapon statistics based on variant"""
	# Base stats
	damage = 25.0
	range = 15.0
	fire_rate = 1.0
	accuracy = 0.85
	reload_time = 2.0
	max_ammo = 30
	
	# Weapon-specific stats
	match weapon_variant:
		"blaster-a", "blaster-b", "blaster-c":  # Pistols
			damage = 20.0
			range = 12.0
			fire_rate = 1.5
			accuracy = 0.9
			reload_time = 1.5
			max_ammo = 15
		"blaster-d", "blaster-i", "blaster-m":  # Rifles
			damage = 35.0
			range = 25.0
			fire_rate = 0.8
			accuracy = 0.95
			reload_time = 2.5
			max_ammo = 20
		"blaster-j", "blaster-k", "blaster-n":  # Heavy weapons
			damage = 50.0
			range = 20.0
			fire_rate = 0.5
			accuracy = 0.8
			reload_time = 3.0
			max_ammo = 10
		"blaster-p", "blaster-r":  # Support weapons
			damage = 15.0
			range = 10.0
			fire_rate = 2.0
			accuracy = 0.85
			reload_time = 1.8
			max_ammo = 25
		_:  # Default stats
			damage = 25.0
			range = 15.0
			fire_rate = 1.0
			accuracy = 0.85
			reload_time = 2.0
			max_ammo = 30
	
	# Set current ammo to max
	current_ammo = max_ammo

func add_attachment(attachment_type: String) -> bool:
	"""Add an attachment to the weapon"""
	if not weapon_model:
		_log_error("Cannot add attachment: no weapon equipped")
		return false
	
	var attachment_model_file = ATTACHMENT_MODELS.get(attachment_type, "")
	if attachment_model_file.is_empty():
		_log_error("Unknown attachment type: %s" % attachment_type)
		return false
	
	var attachment_path = WEAPON_BASE_PATH + attachment_model_file
	var attachment_scene = load(attachment_path)
	
	if not attachment_scene:
		_log_error("Failed to load attachment asset: %s" % attachment_path)
		return false
	
	var attachment_node = attachment_scene.instantiate()
	if not attachment_node:
		_log_error("Failed to instantiate attachment: %s" % attachment_type)
		return false
		
	attachment_node.name = attachment_type
	
	# Attach to appropriate point with error checking
	if attachment_type.begins_with("scope"):
		if scope_attachment_point and is_instance_valid(scope_attachment_point):
			scope_attachment_point.add_child(attachment_node)
			scope = attachment_node
			# Improve accuracy with scope
			accuracy = min(accuracy + 0.1, 1.0)
		else:
			_log_error("Scope attachment point not available")
			attachment_node.queue_free()
			return false
	elif attachment_type.begins_with("clip"):
		if clip_attachment_point and is_instance_valid(clip_attachment_point):
			clip_attachment_point.add_child(attachment_node)
			clip = attachment_node
			# Increase ammo capacity
			max_ammo = int(max_ammo * 1.5)
			current_ammo = max_ammo
		else:
			_log_error("Clip attachment point not available")
			attachment_node.queue_free()
			return false
	else:
		_log_error("Unknown attachment category: %s" % attachment_type)
		attachment_node.queue_free()
		return false
	
	accessories.append(attachment_node)
	
	if logger:
		logger.info("WeaponAttachment", "Added attachment %s to weapon %s" % [attachment_type, weapon_type])
	else:
		print("WeaponAttachment: Added attachment %s to weapon %s" % [attachment_type, weapon_type])
	
	attachment_added.emit(attachment_type)
	return true

func can_fire() -> bool:
	"""Check if weapon can fire"""
	#print("DEBUG: WeaponAttachment.can_fire() - checking conditions")
	if not is_equipped:
		#print("DEBUG: WeaponAttachment.can_fire() - weapon not equipped")
		return false
	
	if current_ammo <= 0:
		#print("DEBUG: WeaponAttachment.can_fire() - no ammo (%d)" % current_ammo)
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_last_fire = current_time - last_fire_time
	var fire_cooldown = 1.0 / fire_rate
	
	if time_since_last_fire < fire_cooldown:
		#print("DEBUG: WeaponAttachment.can_fire() - on cooldown (%.1fs since last fire, need %.1fs)" % [time_since_last_fire, fire_cooldown])
		return false
	
	#print("DEBUG: WeaponAttachment.can_fire() - all checks passed, can fire")
	return true

func fire() -> Dictionary:
	"""Fire the weapon and return fire data"""
	#print("DEBUG: WeaponAttachment.fire() called - checking if can fire")
	if not can_fire():
		#print("DEBUG: WeaponAttachment.fire() - cannot fire, returning empty")
		return {}
	
	#print("DEBUG: WeaponAttachment.fire() - firing weapon %s" % weapon_type)
	current_ammo -= 1
	last_fire_time = Time.get_ticks_msec() / 1000.0
	is_firing = true
	
	var fire_data = {
		"damage": damage,
		"range": range,
		"accuracy": accuracy,
		"muzzle_position": muzzle_point.global_position,
		"weapon_type": weapon_type,
		"ammo_remaining": current_ammo
	}
	
	#print("DEBUG: WeaponAttachment.fire() - creating effects and spawning projectile")
	
	# Create muzzle flash effect
	_create_muzzle_flash()

	_spawn_projectile()
	_play_fire_sound()
	
	weapon_fired.emit(weapon_type, damage)
	
	# Auto-reload if empty
	if current_ammo <= 0:
		#print("DEBUG: WeaponAttachment.fire() - weapon empty, starting auto-reload")
		_auto_reload()
	
	#print("DEBUG: WeaponAttachment.fire() - completed successfully")
	return fire_data

func _create_muzzle_flash() -> void:
	"""Create muzzle flash effect"""
	if not muzzle_point:
		return
	
	var muzzle_flash = MeshInstance3D.new()
	muzzle_flash.name = "MuzzleFlash"
	muzzle_flash.mesh = SphereMesh.new()
	muzzle_flash.mesh.radius = 0.05
	muzzle_flash.mesh.height = 0.1
	
	var flash_material = StandardMaterial3D.new()
	flash_material.albedo_color = Color.YELLOW
	flash_material.emission_enabled = true
	flash_material.emission = Color.YELLOW * 3.0
	flash_material.flags_transparent = true
	muzzle_flash.material_override = flash_material
	
	muzzle_point.add_child(muzzle_flash)
	
	# Animate muzzle flash
	var tween = create_tween()
	tween.tween_property(muzzle_flash, "scale", Vector3(2.0, 2.0, 2.0), 0.05)
	tween.tween_property(muzzle_flash, "scale", Vector3(0.1, 0.1, 0.1), 0.05)
	tween.tween_callback(func(): muzzle_flash.queue_free())

func _spawn_projectile() -> void:
	"""
	Spawns a logical projectile on the server and tells clients to spawn a
	visual-only projectile via RPC.
	"""
	if not PROJECTILE_SCENE or not is_instance_valid(muzzle_point):
		_log_error("Cannot spawn projectile - scene or muzzle point is missing or invalid.")
		return

	if not muzzle_point.is_inside_tree():
		_log_error("Cannot spawn projectile - muzzle point is not in the scene tree. Aborting fire.")
		return

	# This projectile is server-side only, for logic and collision.
	var projectile = PROJECTILE_SCENE.instantiate()
	
	# Set projectile properties
	projectile.damage = damage
	projectile.speed = 50.0 + (range * 2.0)
	projectile.shooter_team_id = parent_unit.team_id if parent_unit else 1
	projectile.lifetime = range / 20.0
	
	# Calculate direction (forward from muzzle point)
	var muzzle_transform = muzzle_point.global_transform
	var forward_direction = -muzzle_transform.basis.z
	
	# Add some accuracy variation (cone of fire)
	var accuracy_spread = (1.0 - accuracy) * 0.2 # Max deviation angle in radians
	var spread_x = randf_range(-accuracy_spread, accuracy_spread)
	var spread_y = randf_range(-accuracy_spread, accuracy_spread)
	
	# Rotate the forward vector by random amounts around the muzzle's local up and right axes
	var final_direction = forward_direction.rotated(muzzle_transform.basis.y, spread_x).rotated(muzzle_transform.basis.x, spread_y)

	projectile.direction = final_direction.normalized()
	
	# Position projectile at muzzle
	projectile.global_position = muzzle_point.global_position
	
	# Add logical projectile to server's scene tree
	get_tree().root.add_child(projectile)

	# RPC to clients to spawn their own visual-only projectile
	var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
	if root_node:
		root_node.rpc("spawn_visual_projectile_rpc", muzzle_point.global_position, projectile.direction, projectile.shooter_team_id, projectile.speed, projectile.lifetime)

	if logger:
		# logger.debug("WeaponAttachment", "Spawned logical projectile and sent RPC for visual projectile.")  # TEMPORARILY DISABLED
		pass

func _auto_reload() -> void:
	"""Auto-reload weapon when empty"""
	if current_ammo > 0:
		return
	
	# Start reload timer
	await get_tree().create_timer(reload_time).timeout
	
	current_ammo = max_ammo
	
	if logger:
		logger.debug("WeaponAttachment", "Reloaded weapon %s" % weapon_type)
	else:
		print("WeaponAttachment: Reloaded weapon %s" % weapon_type)
	
	weapon_reloaded.emit(weapon_type, current_ammo)

func get_weapon_stats() -> Dictionary:
	"""Get current weapon statistics"""
	return {
		"weapon_type": weapon_type,
		"damage": damage,
		"range": range,
		"fire_rate": fire_rate,
		"accuracy": accuracy,
		"reload_time": reload_time,
		"current_ammo": current_ammo,
		"max_ammo": max_ammo,
		"is_equipped": is_equipped,
		"attachments": accessories.size()
	}

func get_muzzle_position() -> Vector3:
	"""Get the muzzle position for projectile spawning"""
	if muzzle_point:
		return muzzle_point.global_position
	return global_position

func unequip_weapon() -> void:
	"""Unequip the weapon"""
	if weapon_model:
		weapon_model.queue_free()
		weapon_model = null
	
	# Clear attachments
	for attachment in accessories:
		if attachment and is_instance_valid(attachment):
			attachment.queue_free()
	accessories.clear()
	
	scope = null
	clip = null
	is_equipped = false
	
	if logger:
		logger.info("WeaponAttachment", "Unequipped weapon %s" % weapon_type)
	else:
		print("WeaponAttachment: Unequipped weapon %s" % weapon_type)

func _log_error(message: String) -> void:
	"""Log error message"""
	if logger:
		logger.error("WeaponAttachment", message)
	else:
		print("WeaponAttachment ERROR: %s" % message)
	
	weapon_attachment_failed.emit(message)

# Debug functions
func debug_weapon_info() -> Dictionary:
	"""Get debug information about the weapon"""
	return {
		"weapon_type": weapon_type,
		"is_equipped": is_equipped,
		"attachment_bone_id": attachment_bone_id,
		"has_skeleton": parent_skeleton != null,
		"has_weapon_model": weapon_model != null,
		"muzzle_position": get_muzzle_position(),
		"attachments": accessories.size(),
		"weapon_stats": get_weapon_stats()
	} 

func _attach_weapon_static_fallback() -> bool:
	"""Fallback method to attach weapon without skeleton using static positioning"""
	if not parent_unit or not weapon_model:
		return false
	
	# Remove this weapon attachment from its current parent
	if get_parent():
		get_parent().remove_child(self)
	
	# Add directly to the character model or unit
	var attachment_parent = parent_unit.model_container if "model_container" in parent_unit and is_instance_valid(parent_unit.model_container) else parent_unit
	attachment_parent.add_child(self)
	
	# Set static weapon positioning based on archetype and weapon type
	_set_static_weapon_position()
	
	if logger:
		logger.info("WeaponAttachment", "Using static fallback attachment for weapon %s" % weapon_type)
	else:
		print("WeaponAttachment: Using static fallback attachment for weapon %s" % weapon_type)
	
	return true

func _set_static_weapon_position() -> void:
	"""Set weapon position based on character archetype and weapon type"""
	# Get parent unit archetype for positioning
	var archetype = parent_unit.archetype if parent_unit.has_method("archetype") else "soldier"
	
	# Base positions for different archetypes (right hand estimated positions)
	var base_positions = {
		"scout": Vector3(0.3, 0.8, 0.2),      # Light, agile stance
		"soldier": Vector3(0.35, 0.9, 0.25),  # Standard military stance  
		"tank": Vector3(0.4, 0.85, 0.3),      # Heavy, lower stance
		"sniper": Vector3(0.32, 0.95, 0.28),  # Precision, higher stance
		"medic": Vector3(0.28, 0.85, 0.22),   # Support, closer stance
		"engineer": Vector3(0.33, 0.88, 0.26) # Utility, balanced stance
	}
	
	# Base rotations for different weapon types
	var base_rotations = {
		"pistol": Vector3(0, 180, -10),    # Slight downward angle
		"rifle": Vector3(0, 180, 0),       # Horizontal
		"sniper": Vector3(0, 180, 5),      # Slight upward angle
		"heavy": Vector3(0, 180, -5),      # Slight downward for stability
		"support": Vector3(0, 180, -8),    # Supportive angle
		"carbine": Vector3(0, 180, -3),    # Slight downward
		"smg": Vector3(0, 180, -12),       # More downward angle
		"marksman": Vector3(0, 180, 3),    # Slight upward
		"utility": Vector3(0, 180, -6)     # Utility angle
	}
	
	# Get weapon category from weapon name
	var weapon_category = "rifle"
	if weapon_type.begins_with("blaster-"):
		var weapon_suffix = weapon_type.split("-")[1]
		match weapon_suffix:
			"a", "c":  # Pistols
				weapon_category = "pistol"
			"d", "i", "m":  # Snipers  
				weapon_category = "sniper"
			"j", "k", "n":  # Heavy weapons
				weapon_category = "heavy"
			"p", "r":  # Support weapons
				weapon_category = "support"
			"g":  # SMG
				weapon_category = "smg"
			"h", "e":  # Carbines
				weapon_category = "carbine"
			"q":  # Marksman
				weapon_category = "marksman"
			"o":  # Utility
				weapon_category = "utility"
			_:  # Default rifles
				weapon_category = "rifle"
	
	# Set position and rotation
	position = base_positions.get(archetype, Vector3(0.35, 0.9, 0.25))
	rotation_degrees = base_rotations.get(weapon_category, Vector3(0, 90, 0))
	
	# Add slight random variation for visual diversity
	position += Vector3(
		randf_range(-0.02, 0.02),
		randf_range(-0.02, 0.02), 
		randf_range(-0.02, 0.02)
	)
	rotation_degrees.z += randf_range(-3, 3) 

func update_weapon_for_animation(animation_name: String) -> void:
	"""Update weapon position based on current animation"""
	if not is_equipped or not weapon_model:
		return
	
	# Animation-specific weapon adjustments
	var animation_offsets = {
		"idle": Vector3(0, 0, 0),           # Base position
		"walk": Vector3(0.02, -0.05, 0.01), # Slight movement sway
		"run": Vector3(0.04, -0.08, 0.02),  # More movement
		"attack": Vector3(0.1, 0.05, 0.15), # Forward thrust
		"reload": Vector3(-0.05, -0.1, -0.05), # Pull back for reload
		"ability": Vector3(0.02, 0.02, 0.05)  # Slight raise
	}
	
	var animation_rotation_offsets = {
		"idle": Vector3(0, 0, 0),
		"walk": Vector3(0, 0, -2),
		"run": Vector3(0, 0, -5),
		"attack": Vector3(-10, 0, 5),
		"reload": Vector3(15, -10, -15),
		"ability": Vector3(-5, 0, 3)
	}
	
	# Apply animation-based adjustments
	var base_position = _get_base_weapon_position()
	var base_rotation = _get_base_weapon_rotation()
	
	var pos_offset = animation_offsets.get(animation_name, Vector3.ZERO)
	var rot_offset = animation_rotation_offsets.get(animation_name, Vector3.ZERO)
	
	# Smoothly transition to new position
	var tween = create_tween()
	tween.tween_property(self, "position", base_position + pos_offset, 0.2)
	tween.parallel().tween_property(self, "rotation_degrees", base_rotation + rot_offset, 0.2)

func _get_base_weapon_position() -> Vector3:
	"""Get the base weapon position for current archetype"""
	var archetype = parent_unit.archetype if parent_unit and parent_unit.has_method("archetype") else "soldier"
	var base_positions = {
		"scout": Vector3(0.3, 0.8, 0.2),
		"soldier": Vector3(0.35, 0.9, 0.25),
		"tank": Vector3(0.4, 0.85, 0.3),
		"sniper": Vector3(0.32, 0.95, 0.28),
		"medic": Vector3(0.28, 0.85, 0.22),
		"engineer": Vector3(0.33, 0.88, 0.26)
	}
	return base_positions.get(archetype, Vector3(0.35, 0.9, 0.25))

func _play_fire_sound():
	var specs = weapon_db.get_weapon_specs(weapon_type)
	var sound_path = specs.get("fire_sound", "")
	
	if not sound_path.is_empty():
		var audio_manager = get_node_or_null("/root/DependencyContainer/AudioManager")
		if audio_manager:
			audio_manager.play_sound_3d(sound_path, muzzle_point.global_position)
		else:
			if logger: logger.warning("WeaponAttachment", "AudioManager not found")

func _get_base_weapon_rotation() -> Vector3:
	"""Get the base weapon rotation for current weapon type"""
	# Get weapon type from stored weapon stats or default to rifle
	var weapon_category = "rifle"
	
	# Try to determine weapon category from weapon name
	if weapon_type.begins_with("blaster-"):
		var weapon_suffix = weapon_type.split("-")[1]
		match weapon_suffix:
			"a", "c":  # Pistols
				weapon_category = "pistol"
			"d", "i", "m":  # Snipers  
				weapon_category = "sniper"
			"j", "k", "n":  # Heavy weapons
				weapon_category = "heavy"
			"p", "r":  # Support weapons
				weapon_category = "support"
			"g":  # SMG
				weapon_category = "smg"
			"h", "e":  # Carbines
				weapon_category = "carbine"
			"q":  # Marksman
				weapon_category = "marksman"
			"o":  # Utility
				weapon_category = "utility"
			_:  # Default rifles
				weapon_category = "rifle"
	
	var base_rotations = {
		"pistol": Vector3(0, -90, -10),
		"rifle": Vector3(0, -90, 0),
		"sniper": Vector3(0, -90, 5),
		"heavy": Vector3(0, -90, -5),
		"support": Vector3(0, -90, -8),
		"carbine": Vector3(0, -90, -3),
		"smg": Vector3(0, -90, -12),
		"marksman": Vector3(0, -90, 3),
		"utility": Vector3(0, -90, -6)
	}
	return base_rotations.get(weapon_category, Vector3(0, -90, 0))