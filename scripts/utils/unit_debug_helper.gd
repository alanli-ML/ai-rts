# UnitDebugHelper.gd - Debug utility for inspecting unit assets
class_name UnitDebugHelper
extends Node

# Character model paths
const CHARACTER_BASE_PATH = "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/"
const CHARACTER_MODELS = {
	"scout": "character-a.glb",
	"tank": "character-h.glb", 
	"sniper": "character-d.glb",
	"medic": "character-p.glb",
	"engineer": "character-o.glb"
}

func inspect_all_character_animations() -> Dictionary:
	"""Inspect animations available in all character models"""
	var results = {}
	
	print("\n=== CHARACTER ANIMATION INSPECTION ===")
	
	for archetype in CHARACTER_MODELS:
		var model_name = CHARACTER_MODELS[archetype]
		var model_path = CHARACTER_BASE_PATH + model_name
		var animations = inspect_character_animations(archetype, model_path)
		results[archetype] = animations
		
		print("\n%s (%s):" % [archetype.capitalize(), model_name])
		if animations.size() > 0:
			for anim in animations:
				print("  - %s" % anim)
		else:
			print("  No animations found or model failed to load")
	
	print("\n=====================================")
	return results

func inspect_character_animations(archetype: String, model_path: String) -> Array:
	"""Inspect animations available in a specific character model"""
	var animations = []
	
	# Try to load the model
	var model_scene = load(model_path)
	if not model_scene:
		print("ERROR: Failed to load model at %s" % model_path)
		return animations
	
	# Instantiate the model
	var model_instance = model_scene.instantiate()
	if not model_instance:
		print("ERROR: Failed to instantiate model from %s" % model_path)
		return animations
	
	# Find the animation player
	var animation_player = model_instance.find_child("AnimationPlayer", true, false)
	if not animation_player:
		print("WARNING: No AnimationPlayer found in %s" % model_path)
		# Try alternative names
		animation_player = model_instance.find_child("AnimationTree", true, false)
		if not animation_player:
			animation_player = model_instance.find_child("Animator", true, false)
	
	if animation_player and animation_player is AnimationPlayer:
		var animation_list = animation_player.get_animation_list()
		for anim_name in animation_list:
			animations.append(anim_name)
			var animation = animation_player.get_animation(anim_name)
			if animation:
				print("    %s: %.2fs, %d tracks" % [anim_name, animation.length, animation.get_track_count()])
	else:
		print("WARNING: No valid AnimationPlayer found in %s" % model_path)
	
	# Clean up
	model_instance.queue_free()
	
	return animations

func inspect_character_materials(archetype: String, model_path: String) -> Dictionary:
	"""Inspect materials used in a character model"""
	var material_info = {"mesh_instances": [], "materials": []}
	
	# Try to load the model
	var model_scene = load(model_path)
	if not model_scene:
		print("ERROR: Failed to load model at %s" % model_path)
		return material_info
	
	# Instantiate the model  
	var model_instance = model_scene.instantiate()
	if not model_instance:
		print("ERROR: Failed to instantiate model from %s" % model_path)
		return material_info
	
	print("\n%s Materials (%s):" % [archetype.capitalize(), model_path])
	
	# Find all MeshInstance3D nodes
	var mesh_instances = _find_all_mesh_instances(model_instance)
	for mesh_instance in mesh_instances:
		var mesh_info = {
			"name": mesh_instance.name,
			"mesh": null,
			"materials": []
		}
		
		if mesh_instance.mesh:
			mesh_info.mesh = mesh_instance.mesh.resource_path
			
			# Check surface materials
			for surface_idx in range(mesh_instance.mesh.get_surface_count()):
				var material = mesh_instance.get_surface_override_material(surface_idx)
				if not material:
					material = mesh_instance.mesh.surface_get_material(surface_idx)
				
				if material:
					mesh_info.materials.append({
						"surface": surface_idx,
						"material_type": material.get_class(),
						"resource_path": material.resource_path if material.resource_path else "built-in"
					})
				else:
					mesh_info.materials.append({
						"surface": surface_idx,
						"material_type": "None",
						"resource_path": "missing"
					})
		
		material_info.mesh_instances.append(mesh_info)
		print("  MeshInstance: %s" % mesh_instance.name)
		print("    Mesh: %s" % (mesh_info.mesh if mesh_info.mesh else "None"))
		for mat_info in mesh_info.materials:
			print("    Surface %d: %s (%s)" % [mat_info.surface, mat_info.material_type, mat_info.resource_path])
	
	# Clean up
	model_instance.queue_free()
	
	return material_info

func _find_all_mesh_instances(node: Node) -> Array:
	"""Recursively find all MeshInstance3D nodes"""
	var mesh_instances = []
	
	if node is MeshInstance3D:
		mesh_instances.append(node)
	
	for child in node.get_children():
		mesh_instances.append_array(_find_all_mesh_instances(child))
	
	return mesh_instances

func get_suggested_animation_mapping() -> Dictionary:
	"""Get suggested animation mappings based on common animation names"""
	return {
		"Idle": ["Idle", "idle", "T-Pose", "TPose", "Rest", "Stand", "Default"],
		"Walk": ["Walk", "walk", "Walking", "walking", "Move", "move"],
		"Run": ["Run", "run", "Running", "running", "Sprint", "sprint", "Fast", "fast"],
		"Attack": ["Attack", "attack", "Fire", "fire", "Shoot", "shoot", "Action", "action"],
		"Death": ["Death", "death", "Die", "die", "Dead", "dead", "Fall", "fall"]
	}

func test_animation_fallbacks(archetype: String) -> void:
	"""Test animation fallback system for a specific archetype"""
	var model_path = CHARACTER_BASE_PATH + CHARACTER_MODELS[archetype]
	var available_animations = inspect_character_animations(archetype, model_path)
	var suggested_mappings = get_suggested_animation_mapping()
	
	print("\n=== ANIMATION FALLBACK TEST for %s ===" % archetype.to_upper())
	print("Available animations: %s" % str(available_animations))
	
	for desired_anim in suggested_mappings:
		print("\nLooking for '%s' animation:" % desired_anim)
		var found = false
		
		# Check exact match first
		for available_anim in available_animations:
			if available_anim == desired_anim:
				print("  ✓ Exact match: %s" % available_anim)
				found = true
				break
		
		if not found:
			# Check case-insensitive match
			for available_anim in available_animations:
				if available_anim.to_lower() == desired_anim.to_lower():
					print("  ✓ Case-insensitive match: %s" % available_anim)
					found = true
					break
		
		if not found:
			# Check suggested alternatives
			var alternatives = suggested_mappings[desired_anim]
			for alt in alternatives:
				for available_anim in available_animations:
					if available_anim.to_lower() == alt.to_lower():
						print("  ✓ Alternative match: %s (for %s)" % [available_anim, alt])
						found = true
						break
				if found:
					break
		
		if not found:
			print("  ✗ No suitable animation found for '%s'" % desired_anim)
	
	print("=======================================")

# Console commands for debugging
func debug_all_animations() -> void:
	"""Debug command to inspect all character animations"""
	inspect_all_character_animations()

func debug_animation_fallbacks() -> void:
	"""Debug command to test animation fallbacks for all archetypes"""
	for archetype in CHARACTER_MODELS:
		test_animation_fallbacks(archetype)

func debug_materials() -> void:
	"""Debug command to inspect materials for all character models"""
	print("\n=== CHARACTER MATERIALS INSPECTION ===")
	
	for archetype in CHARACTER_MODELS:
		var model_path = CHARACTER_BASE_PATH + CHARACTER_MODELS[archetype]
		inspect_character_materials(archetype, model_path)
	
	print("\n======================================") 