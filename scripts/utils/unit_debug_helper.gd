# UnitDebugHelper.gd - Debugging utilities for unit instantiation issues
class_name UnitDebugHelper
extends Node

static func debug_unit_type(unit: Node) -> Dictionary:
	"""Comprehensive unit type debugging information"""
	var debug_info = {
		"node_type": unit.get_class(),
		"script_path": "",
		"is_unit_check": unit is Unit,
		"is_character_body_check": unit is CharacterBody3D,
		"has_unit_properties": false,
		"has_unit_methods": false,
		"property_list": [],
		"method_list": [],
		"inheritance_chain": []
	}
	
	# Check script
	if unit.get_script():
		debug_info.script_path = unit.get_script().resource_path
	
	# Check properties (both script properties and set properties)
	var unit_properties = ["team_id", "archetype", "unit_id", "max_health", "current_health"]
	var found_properties = []
	for prop in unit_properties:
		if prop in unit:
			found_properties.append(prop + "(script)")
		elif unit.has_method("get") and unit.get(prop) != null:
			found_properties.append(prop + "(set)")
	debug_info.property_list = found_properties
	debug_info.has_unit_properties = found_properties.size() >= 3
	
	# Check methods
	var unit_methods = ["get_team_id", "get_unit_info", "move_to", "attack_target", "take_damage"]
	var found_methods = []
	for method in unit_methods:
		if unit.has_method(method):
			found_methods.append(method)
	debug_info.method_list = found_methods
	debug_info.has_unit_methods = found_methods.size() >= 3
	
	# Build inheritance chain
	var current_script = unit.get_script()
	while current_script:
		debug_info.inheritance_chain.append(current_script.resource_path)
		current_script = current_script.get_base_script()
	
	return debug_info

static func print_unit_debug(unit: Node, context: String = "") -> void:
	"""Print comprehensive debug information about a unit"""
	var debug_info = debug_unit_type(unit)
	
	var title = "\n=== UNIT DEBUG INFO"
	if not context.is_empty():
		title += " - " + context
	title += " ==="
	print(title)
	print("Node Type: %s" % debug_info.node_type)
	print("Script Path: %s" % debug_info.script_path)
	print("is Unit Check: %s" % debug_info.is_unit_check)
	print("is CharacterBody3D Check: %s" % debug_info.is_character_body_check)
	print("Has Unit Properties: %s" % debug_info.has_unit_properties)
	print("Has Unit Methods: %s" % debug_info.has_unit_methods)
	print("Found Properties: %s" % debug_info.property_list)
	print("Found Methods: %s" % debug_info.method_list)
	print("Inheritance Chain: %s" % debug_info.inheritance_chain)
	print("==============================\n")

static func is_unit_compatible(unit: Node) -> bool:
	"""Check if a node is Unit-compatible using multiple validation methods"""
	# Direct type check
	if unit is Unit:
		return true
	
	# Script-based check
	if unit.get_script():
		var script_path = str(unit.get_script().resource_path)
		if script_path.contains("unit") or script_path.contains("Unit"):
			# Check for essential Unit properties (more flexible)
			var has_team_id = "team_id" in unit or unit.get("team_id") != null
			var has_archetype = "archetype" in unit or unit.get("archetype") != null
			var has_unit_id = "unit_id" in unit or unit.get("unit_id") != null
			
			if has_team_id or has_archetype or has_unit_id:
				return true
			
			# If script is unit-related but properties missing, still compatible
			# (force initialization can handle this)
			return true
	
	# Duck typing check
	if unit.has_method("get_team_id") and unit.has_method("get_unit_info") and unit.has_method("take_damage"):
		return true
	
	# CharacterBody3D with unit script is compatible
	if unit is CharacterBody3D and unit.get_script():
		var script_path = str(unit.get_script().resource_path)
		if script_path.contains("unit") or script_path.contains("Unit"):
			return true
	
	return false

static func wait_for_unit_recognition(unit: Node, max_frames: int = 5) -> bool:
	"""Wait for Godot to recognize unit class, return true if successful"""
	for i in range(max_frames):
		if unit is Unit:
			return true
		await unit.get_tree().process_frame
	
	return false

static func validate_unit_scene(scene_path: String) -> Dictionary:
	"""Validate that a unit scene is properly configured"""
	var result = {
		"valid": false,
		"scene_loads": false,
		"has_script": false,
		"script_path": "",
		"root_node_type": "",
		"issues": []
	}
	
	# Try to load the scene
	var scene_resource = load(scene_path)
	if not scene_resource:
		result.issues.append("Scene file could not be loaded")
		return result
	
	result.scene_loads = true
	
	# Instantiate to check structure
	var instance = scene_resource.instantiate()
	if not instance:
		result.issues.append("Scene could not be instantiated")
		return result
	
	result.root_node_type = instance.get_class()
	
	# Check script
	if instance.get_script():
		result.has_script = true
		result.script_path = instance.get_script().resource_path
		
		# Check if script is unit-related
		if not result.script_path.contains("unit"):
			result.issues.append("Script path doesn't appear to be unit-related")
	else:
		result.issues.append("No script attached to root node")
	
	# Check if it extends CharacterBody3D (required for units)
	if not instance is CharacterBody3D:
		result.issues.append("Root node is not CharacterBody3D or descendant")
	
	# Clean up
	instance.queue_free()
	
	result.valid = result.scene_loads and result.has_script and result.issues.is_empty()
	return result 