# UnitRangeVisualization.gd - Visual range indicators for units
class_name UnitRangeVisualization
extends Node3D

# Node references
var vision_range_mesh: MeshInstance3D
var attack_range_mesh: MeshInstance3D

# Materials
var vision_material: StandardMaterial3D
var attack_material: StandardMaterial3D

# Settings
@export var vision_range_color: Color = Color(0.2, 0.6, 1.0, 0.2)  # Blue, more transparent
@export var attack_range_color: Color = Color(1.0, 0.3, 0.2, 0.4)  # Red, more opaque
@export var line_width: float = 2.0
@export var fade_distance: float = 40.0
@export var min_alpha: float = 0.05
@export var max_alpha: float = 0.5

# Parent unit reference
var parent_unit: Unit

func _ready() -> void:
	# Get node references
	vision_range_mesh = $VisionRange
	attack_range_mesh = $AttackRange
	
	# Setup materials
	_setup_materials()
	
	# Find parent unit
	_find_parent_unit()
	
	# Initially hidden
	visible = false

func _setup_materials() -> void:
	"""Setup materials for range visualization"""
	# Vision range material (blue, transparent)
	vision_material = StandardMaterial3D.new()
	vision_material.flags_transparent = true
	vision_material.flags_unshaded = true
	vision_material.flags_do_not_receive_shadows = true
	vision_material.no_depth_test = true
	vision_material.albedo_color = vision_range_color
	vision_material.grow_amount = 0.01
	
	# Attack range material (red, transparent)
	attack_material = StandardMaterial3D.new()
	attack_material.flags_transparent = true
	attack_material.flags_unshaded = true
	attack_material.flags_do_not_receive_shadows = true
	attack_material.no_depth_test = true
	attack_material.albedo_color = attack_range_color
	attack_material.grow_amount = 0.01
	
	# Apply materials
	vision_range_mesh.material_override = vision_material
	attack_range_mesh.material_override = attack_material

func _find_parent_unit() -> void:
	"""Find the parent unit"""
	var current_node = get_parent()
	while current_node and not current_node is Unit:
		current_node = current_node.get_parent()
	
	if current_node is Unit:
		parent_unit = current_node
	else:
		print("UnitRangeVisualization: Warning - could not find parent Unit")

func show_ranges() -> void:
	"""Show the range visualization"""
	if not parent_unit:
		return
	
	# Update range sizes based on unit stats
	_update_range_sizes()
	
	# Show the visualization
	visible = true
	
	# Start alpha animation
	_animate_fade_in()

func hide_ranges() -> void:
	"""Hide the range visualization"""
	visible = false

func _update_range_sizes() -> void:
	"""Update range circle sizes based on unit stats"""
	if not parent_unit:
		return
	
	# Scale vision range circle
	var vision_scale = parent_unit.vision_range
	vision_range_mesh.scale = Vector3(vision_scale, 1.0, vision_scale)
	
	# Scale attack range circle  
	var attack_scale = parent_unit.attack_range
	attack_range_mesh.scale = Vector3(attack_scale, 1.0, attack_scale)

func _animate_fade_in() -> void:
	"""Animate fade in effect"""
	var vision_color = vision_range_color
	var attack_color = attack_range_color
	
	# Start with low alpha
	vision_color.a = min_alpha
	attack_color.a = min_alpha
	
	vision_material.albedo_color = vision_color
	attack_material.albedo_color = attack_color
	
	# Create fade-in tween
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Animate vision range alpha (more subtle)
	vision_color.a = max_alpha * 0.4  # Vision range much more transparent
	tween.tween_method(_set_vision_alpha, min_alpha, vision_color.a, 0.5)
	
	# Animate attack range alpha (more prominent)
	attack_color.a = max_alpha * 0.9  # Attack range more visible
	tween.tween_method(_set_attack_alpha, min_alpha, attack_color.a, 0.5)

func _set_vision_alpha(alpha: float) -> void:
	"""Set vision range alpha"""
	if vision_material:
		var color = vision_material.albedo_color
		color.a = alpha
		vision_material.albedo_color = color

func _set_attack_alpha(alpha: float) -> void:
	"""Set attack range alpha"""
	if attack_material:
		var color = attack_material.albedo_color
		color.a = alpha
		attack_material.albedo_color = color

func update_colors(vision_color: Color, attack_color: Color) -> void:
	"""Update range colors"""
	vision_range_color = vision_color
	attack_range_color = attack_color
	
	if vision_material:
		vision_material.albedo_color = vision_color
	if attack_material:
		attack_material.albedo_color = attack_color

func set_team_colors(team_id: int) -> void:
	"""Set colors based on team"""
	match team_id:
		1:  # Blue team
			vision_range_color = Color(0.2, 0.6, 1.0, 0.15)      # Light blue, very transparent
			attack_range_color = Color(0.3, 0.5, 1.0, 0.35)      # Darker blue, more visible
		2:  # Red team
			vision_range_color = Color(1.0, 0.4, 0.4, 0.15)      # Light red, very transparent
			attack_range_color = Color(1.0, 0.2, 0.2, 0.35)      # Darker red, more visible
		3:  # Green team
			vision_range_color = Color(0.4, 1.0, 0.4, 0.15)      # Light green, very transparent
			attack_range_color = Color(0.2, 1.0, 0.2, 0.35)      # Darker green, more visible
		4:  # Yellow team
			vision_range_color = Color(1.0, 1.0, 0.4, 0.15)      # Light yellow, very transparent
			attack_range_color = Color(1.0, 0.8, 0.2, 0.35)      # Orange, more visible
		_:  # Default (neutral/unknown team)
			vision_range_color = Color(0.6, 0.6, 1.0, 0.15)      # Light purple, very transparent
			attack_range_color = Color(1.0, 0.3, 0.2, 0.35)      # Red, more visible
	
	update_colors(vision_range_color, attack_range_color)

func _physics_process(_delta: float) -> void:
	"""Update visualization based on camera distance"""
	if not visible or not parent_unit:
		return
	
	# Get camera for distance calculation
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	# Calculate distance-based alpha
	var distance = global_position.distance_to(camera.global_position)
	var alpha_factor = 1.0
	
	if distance > fade_distance:
		alpha_factor = min_alpha / max_alpha
	else:
		# Smooth transition
		var fade_ratio = distance / fade_distance
		alpha_factor = lerp(1.0, min_alpha / max_alpha, fade_ratio)
	
	# Apply distance-based alpha
	var vision_color = vision_range_color
	var attack_color = attack_range_color
	
	vision_color.a = vision_range_color.a * alpha_factor
	attack_color.a = attack_range_color.a * alpha_factor
	
	if vision_material:
		vision_material.albedo_color = vision_color
	if attack_material:
		attack_material.albedo_color = attack_color

func get_vision_range() -> float:
	"""Get the current vision range"""
	return parent_unit.vision_range if parent_unit else 30.0

func get_attack_range() -> float:
	"""Get the current attack range"""
	return parent_unit.attack_range if parent_unit else 15.0

func refresh_visualization() -> void:
	"""Refresh the visualization (useful when unit stats change)"""
	if visible:
		_update_range_sizes()
		if parent_unit:
			set_team_colors(parent_unit.team_id) 