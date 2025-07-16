# TextureManager.gd - Manual texture assignment for Kenny assets
class_name TextureManager
extends Node

# Texture paths for characters
const CHARACTER_TEXTURE_BASE_PATH = "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/Textures/"
const WEAPON_TEXTURE_BASE_PATH = "res://assets/kenney/kenney_blaster-kit-2/Models/GLB format/Textures/"

# Character texture mapping
const CHARACTER_TEXTURES = {
	"character-a": "texture-a.png",
	"character-b": "texture-b.png", 
	"character-c": "texture-c.png",
	"character-d": "texture-d.png",
	"character-e": "texture-e.png",
	"character-f": "texture-f.png",
	"character-g": "texture-g.png",
	"character-h": "texture-h.png",
	"character-i": "texture-i.png",
	"character-j": "texture-j.png",
	"character-k": "texture-k.png",
	"character-l": "texture-l.png",
	"character-m": "texture-m.png",
	"character-n": "texture-n.png",
	"character-o": "texture-o.png",
	"character-p": "texture-p.png",
	"character-q": "texture-q.png",
	"character-r": "texture-r.png"
}

# All weapons use the same texture
const WEAPON_TEXTURE = "colormap.png"

var logger

func _ready() -> void:
	_setup_logger()
	
	if logger:
		logger.info("TextureManager", "Texture Manager initialized")
	else:
		print("TextureManager: Texture Manager initialized")

func _setup_logger() -> void:
	"""Setup logger reference from dependency container"""
	if has_node("/root/DependencyContainer"):
		var dependency_container = get_node("/root/DependencyContainer")
		if dependency_container.has_method("get_logger"):
			logger = dependency_container.get_logger()

func apply_character_texture(character_model: Node3D, character_variant: String) -> bool:
	"""Apply the correct texture to a character model"""
	if not character_model:
		_log_error("Character model is null")
		return false
	
	var texture_filename = CHARACTER_TEXTURES.get(character_variant, "")
	if texture_filename.is_empty():
		_log_error("No texture found for character variant: %s" % character_variant)
		return false
	
	var texture_path = CHARACTER_TEXTURE_BASE_PATH + texture_filename
	var texture = load(texture_path)
	
	if not texture:
		_log_error("Failed to load texture: %s" % texture_path)
		return false
	
	# Apply texture to all mesh instances in the character model
	var mesh_instances = _get_mesh_instances_recursive(character_model)
	var applied_count = 0
	
	for mesh_instance in mesh_instances:
		if _apply_texture_to_mesh(mesh_instance, texture):
			applied_count += 1
	
	if logger:
		logger.info("TextureManager", "Applied texture %s to %d mesh instances for %s" % [texture_filename, applied_count, character_variant])
	else:
		print("TextureManager: Applied texture %s to %d mesh instances for %s" % [texture_filename, applied_count, character_variant])
	
	return applied_count > 0

func apply_weapon_texture(weapon_model: Node3D) -> bool:
	"""Apply the weapon texture to a weapon model"""
	if not weapon_model:
		_log_error("Weapon model is null")
		return false
	
	var texture_path = WEAPON_TEXTURE_BASE_PATH + WEAPON_TEXTURE
	var texture = load(texture_path)
	
	if not texture:
		_log_error("Failed to load weapon texture: %s" % texture_path)
		return false
	
	# Apply texture to all mesh instances in the weapon model
	var mesh_instances = _get_mesh_instances_recursive(weapon_model)
	var applied_count = 0
	
	for mesh_instance in mesh_instances:
		if _apply_texture_to_mesh(mesh_instance, texture):
			applied_count += 1
	
	if logger:
		logger.info("TextureManager", "Applied weapon texture to %d mesh instances" % applied_count)
	else:
		print("TextureManager: Applied weapon texture to %d mesh instances" % applied_count)
	
	return applied_count > 0

func apply_team_color_with_texture(character_model: Node3D, character_variant: String, team_color: Color) -> bool:
	"""Apply both the base texture and team color overlay"""
	if not apply_character_texture(character_model, character_variant):
		return false
	
	# Apply team color overlay while preserving the base texture
	var mesh_instances = _get_mesh_instances_recursive(character_model)
	
	for mesh_instance in mesh_instances:
		if mesh_instance.material_override:
			var material = mesh_instance.material_override as StandardMaterial3D
			if material:
				# Apply team color as modulation
				material.albedo_color = material.albedo_color.lerp(team_color, 0.3)
				material.emission_enabled = true
				material.emission = team_color * 0.1
	
	return true

func apply_weapon_texture_with_team_color(weapon_model: Node3D, team_color: Color) -> bool:
	"""Apply weapon texture with team color accent"""
	if not apply_weapon_texture(weapon_model):
		return false
	
	# Apply team color accent
	var mesh_instances = _get_mesh_instances_recursive(weapon_model)
	
	for mesh_instance in mesh_instances:
		if mesh_instance.material_override:
			var material = mesh_instance.material_override as StandardMaterial3D
			if material:
				# Apply subtle team color accent
				material.emission_enabled = true
				material.emission = team_color * 0.1
				material.metallic = 0.6
				material.roughness = 0.4
	
	return true

func _apply_texture_to_mesh(mesh_instance: MeshInstance3D, texture: Texture2D) -> bool:
	"""Apply texture to a specific mesh instance"""
	if not mesh_instance or not texture or not mesh_instance.mesh:
		return false
	
	# Get existing material or create from mesh surface material
	var material = mesh_instance.get_surface_override_material(0)
	
	# If no override material, try to get the mesh's built-in material
	if not material and mesh_instance.mesh.surface_get_material(0):
		material = mesh_instance.mesh.surface_get_material(0)
		
	# Create new material if none exists
	if not material:
		material = StandardMaterial3D.new()
	
	# Always duplicate material to avoid affecting other instances
	material = material.duplicate()
	
	# Apply the texture and set up material properties
	if material is StandardMaterial3D:
		var std_material = material as StandardMaterial3D
		std_material.albedo_texture = texture
		std_material.albedo_color = Color.WHITE  # Reset color to white so texture shows properly
		std_material.metallic = 0.0
		std_material.roughness = 0.7
		std_material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		
		# Set the material to the mesh instance
		mesh_instance.set_surface_override_material(0, std_material)
		return true
	
	return false

func _get_mesh_instances_recursive(node: Node) -> Array[MeshInstance3D]:
	"""Recursively collect all MeshInstance3D nodes"""
	var mesh_instances: Array[MeshInstance3D] = []
	
	if node is MeshInstance3D:
		mesh_instances.append(node as MeshInstance3D)
	
	for child in node.get_children():
		mesh_instances.append_array(_get_mesh_instances_recursive(child))
	
	return mesh_instances

func debug_texture_info(model: Node3D, model_name: String) -> Dictionary:
	"""Get debug information about textures on a model"""
	var mesh_instances = _get_mesh_instances_recursive(model)
	var texture_info = {
		"model_name": model_name,
		"mesh_instance_count": mesh_instances.size(),
		"materials": []
	}
	
	for i in range(mesh_instances.size()):
		var mesh_instance = mesh_instances[i]
		var material_info = {
			"mesh_index": i,
			"has_material": mesh_instance.material_override != null,
			"material_type": str(mesh_instance.material_override.get_class()) if mesh_instance.material_override else "none",
			"has_albedo_texture": false,
			"albedo_color": Color.WHITE
		}
		
		if mesh_instance.material_override and mesh_instance.material_override is StandardMaterial3D:
			var material = mesh_instance.material_override as StandardMaterial3D
			material_info.has_albedo_texture = material.albedo_texture != null
			material_info.albedo_color = material.albedo_color
		
		texture_info.materials.append(material_info)
	
	return texture_info

func preload_all_character_textures() -> Dictionary:
	"""Preload all character textures for performance"""
	var loaded_textures = {}
	
	for character_variant in CHARACTER_TEXTURES:
		var texture_filename = CHARACTER_TEXTURES[character_variant]
		var texture_path = CHARACTER_TEXTURE_BASE_PATH + texture_filename
		var texture = load(texture_path)
		
		if texture:
			loaded_textures[character_variant] = texture
			if logger:
				logger.debug("TextureManager", "Preloaded texture for %s" % character_variant)
		else:
			if logger:
				logger.warning("TextureManager", "Failed to preload texture for %s: %s" % [character_variant, texture_path])
	
	return loaded_textures

func preload_weapon_texture() -> Texture2D:
	"""Preload the weapon texture"""
	var texture_path = WEAPON_TEXTURE_BASE_PATH + WEAPON_TEXTURE
	var texture = load(texture_path)
	
	if texture:
		if logger:
			logger.debug("TextureManager", "Preloaded weapon texture")
	else:
		if logger:
			logger.warning("TextureManager", "Failed to preload weapon texture: %s" % texture_path)
	
	return texture

func get_available_character_variants() -> Array[String]:
	"""Get list of all available character variants"""
	var variants: Array[String] = []
	for variant in CHARACTER_TEXTURES.keys():
		variants.append(variant)
	return variants

func _log_error(message: String) -> void:
	"""Log error message"""
	if logger:
		logger.error("TextureManager", message)
	else:
		print("TextureManager ERROR: %s" % message) 