# ScoutUnit.gd
class_name ScoutUnit
extends AnimatedUnit

var is_stealthed: bool = false
var was_stealthed: bool = false
@export var stealth_duration: float = 10.0
@export var stealth_cooldown: float = 15.0
var stealth_timer: float = 0.0
var stealth_cooldown_timer: float = 0.0

func _ready() -> void:
	archetype = "scout"
	super._ready()
	system_prompt = "You are a fast, stealthy scout. Your primary mission is reconnaissance. Identify which control points are undefended and capture them. Use your speed to quickly move between points. Your secondary mission is to find the enemy, identify their composition (especially high-value targets like snipers and engineers), and report their position, especially near contested control points. Use your `activate_stealth` ability to escape danger or to capture a point unnoticed. Avoid direct combat unless you have a clear advantage. Prioritize survival."

func _physics_process(delta: float):
	if is_stealthed:
		stealth_timer -= delta
		if stealth_timer <= 0:
			deactivate_stealth()
	
	if stealth_cooldown_timer > 0:
		stealth_cooldown_timer -= delta

	super._physics_process(delta)

	# If we are the host, manage our own visuals.
	if multiplayer.is_server() and DisplayServer.get_name() != "headless":
		if is_stealthed != was_stealthed:
			var model_container = get_node_or_null("ModelContainer")
			if model_container:
				if is_stealthed:
					_set_model_transparency(model_container, 0.3)
				else:
					_set_model_transparency(model_container, 1.0)
			was_stealthed = is_stealthed

# --- Action Implementation ---

func activate_stealth(_params: Dictionary):
	if stealth_cooldown_timer > 0: return
	is_stealthed = true
	stealth_timer = stealth_duration
	stealth_cooldown_timer = stealth_cooldown
	print("%s is activating stealth." % unit_id)
	action_complete = true

func deactivate_stealth():
	if not is_stealthed: return
	is_stealthed = false
	stealth_timer = 0
	print("%s is no longer stealthed." % unit_id)

func sabotage(_params: Dictionary):
	print("%s is sabotaging a target." % unit_id)
	pass

# Override attack to break stealth
func attack_target(target: Unit):
	if is_stealthed:
		deactivate_stealth()
	super.attack_target(target)

# --- Visual Effect Helpers (for host) ---

func _set_model_transparency(container: Node3D, alpha_value: float) -> void:
	"""Set transparency for all MeshInstance3D nodes in the model container"""
	if not is_instance_valid(container):
		return
	
	# Find all MeshInstance3D nodes recursively
	var mesh_instances = _find_all_mesh_instances(container)
	
	for mesh_instance in mesh_instances:
		if not is_instance_valid(mesh_instance):
			continue
		
		# Skip if no mesh or surfaces
		if not mesh_instance.mesh or mesh_instance.get_surface_override_material_count() == 0:
			continue
			
		# Get existing material or create from mesh surface material
		var material = mesh_instance.get_surface_override_material(0)
		
		# If no override material, try to get the mesh's built-in material
		if not material and mesh_instance.mesh.surface_get_material(0):
			material = mesh_instance.mesh.surface_get_material(0)
			
		# If still no material, create a basic one with proper initialization
		if not material:
			material = StandardMaterial3D.new()
			# Set basic material properties to avoid null parameter errors
			material.albedo_color = Color.WHITE
			material.metallic = 0.0
			material.roughness = 0.7
			material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		
		# Always duplicate the material to avoid affecting other instances
		if material:
			material = material.duplicate()
			mesh_instance.set_surface_override_material(0, material)
			
			# Apply transparency settings
			if material is StandardMaterial3D:
				var std_material = material as StandardMaterial3D
				if alpha_value < 1.0:
					std_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					std_material.albedo_color.a = alpha_value
				else:
					std_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					std_material.albedo_color.a = 1.0

func _find_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	"""Recursively find all MeshInstance3D nodes"""
	var mesh_instances: Array[MeshInstance3D] = []
	
	if node is MeshInstance3D:
		mesh_instances.append(node as MeshInstance3D)
	
	for child in node.get_children():
		mesh_instances.append_array(_find_all_mesh_instances(child))
	
	return mesh_instances