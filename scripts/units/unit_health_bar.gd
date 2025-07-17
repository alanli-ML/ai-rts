# UnitHealthBar.gd - Billboard health bar for units
class_name UnitHealthBar
extends Node3D

# References
var health_quad: MeshInstance3D
var health_viewport: SubViewport
var health_background: ColorRect
var health_bar: ColorRect
var health_text: Label
var health_panel: Panel
var camera: Camera3D
var parent_unit: Unit

# Health bar settings
@export var offset_height: float = 1.8
@export var always_visible: bool = false
@export var fade_distance: float = 50.0
@export var min_alpha: float = 0.3
@export var max_alpha: float = 1.0
@export var hide_when_full: bool = true

# Material for the quad
var health_material: StandardMaterial3D

# Team colors for borders
var team_colors: Dictionary = {
	1: Color(0.2, 0.4, 1.0),    # Blue team
	2: Color(1.0, 0.3, 0.2),    # Red team
	3: Color(0.2, 1.0, 0.4),    # Green team
	4: Color(1.0, 0.8, 0.2)     # Yellow team
}

func _ready() -> void:
	# Get node references
	health_quad = $HealthQuad
	health_viewport = $HealthQuad/SubViewport
	health_panel = $HealthQuad/SubViewport/HealthPanel
	health_background = $HealthQuad/SubViewport/HealthPanel/HealthContainer/HealthBackground
	health_bar = $HealthQuad/SubViewport/HealthPanel/HealthContainer/HealthBar
	health_text = $HealthQuad/SubViewport/HealthPanel/HealthContainer/HealthText
	
	# Set up the material for the quad
	_setup_material()
	
	# Find the parent unit
	parent_unit = get_parent() as Unit
	
	# Set up team-colored border
	_setup_team_border()
	
	# Find the camera
	_find_camera()
	
	# Position the health bar
	position.y = offset_height
	
	# Connect to parent unit's health changed signal
	if parent_unit:
		parent_unit.health_changed.connect(_on_health_changed)
		# Initial health update
		call_deferred("_update_health", parent_unit.current_health, parent_unit.max_health)

func _setup_material() -> void:
	"""Setup the material for the health quad"""
	health_material = StandardMaterial3D.new()
	health_material.flags_transparent = true
	health_material.flags_unshaded = true
	health_material.flags_do_not_receive_shadows = true
	health_material.albedo_texture = health_viewport.get_texture()
	health_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	health_material.no_depth_test = true
	
	health_quad.material_override = health_material

func _setup_team_border() -> void:
	"""Setup team-colored border around the health panel"""
	if not health_panel or not parent_unit:
		return
	
	# Get team color
	var team_id = parent_unit.team_id if parent_unit.team_id > 0 else 1
	var border_color = team_colors.get(team_id, Color.WHITE)
	
	# Create a StyleBoxFlat for the panel
	var style_box = StyleBoxFlat.new()
	
	# Set background color (transparent so we can see the ColorRects)
	style_box.bg_color = Color(0, 0, 0, 0)
	
	# Set border properties
	style_box.border_width_left = 2
	style_box.border_width_right = 2  
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	style_box.border_color = border_color
	
	# Set corner rounding
	style_box.corner_radius_top_left = 3
	style_box.corner_radius_top_right = 3
	style_box.corner_radius_bottom_left = 3
	style_box.corner_radius_bottom_right = 3
	
	# Apply the style to the panel
	health_panel.add_theme_stylebox_override("panel", style_box)

func _find_camera() -> void:
	"""Find the active camera in the scene"""
	# Look for cameras in groups first
	var camera_nodes = get_tree().get_nodes_in_group("cameras")
	if camera_nodes.size() > 0:
		camera = camera_nodes[0] as Camera3D
		return
	
	# Fallback: search for any Camera3D node
	var all_cameras = get_tree().get_nodes_in_group("rts_cameras")
	if all_cameras.size() > 0:
		camera = all_cameras[0] as Camera3D
		return
	
	# Last resort: search the whole tree
	camera = get_viewport().get_camera_3d()

func _physics_process(_delta: float) -> void:
	# Update camera reference if needed
	if not is_instance_valid(camera):
		_find_camera()
	
	# Update visibility based on distance
	if camera and not always_visible:
		_update_visibility()

func _update_visibility() -> void:
	"""Update visibility based on distance to camera and health status"""
	if not camera or not parent_unit:
		return
	
	# Hide when full health if enabled
	if hide_when_full and parent_unit.current_health >= parent_unit.max_health:
		visible = false
		return
	
	visible = true
	
	var distance = global_position.distance_to(camera.global_position)
	var alpha = 1.0
	
	if distance > fade_distance:
		alpha = min_alpha
	else:
		# Interpolate alpha based on distance
		var fade_factor = clamp(distance / fade_distance, 0.0, 1.0)
		alpha = lerp(max_alpha, min_alpha, fade_factor)
	
	# Apply alpha to the material
	if health_material:
		var current_color = health_material.albedo_color
		current_color.a = alpha
		health_material.albedo_color = current_color

func _on_health_changed(new_health: float, max_health: float) -> void:
	"""Handle health changed signal from parent unit"""
	_update_health(new_health, max_health)

func _update_health(current_health: float, max_health: float) -> void:
	"""Update the health bar display"""
	if not health_bar or not health_text or not health_background:
		return
	
	# Calculate health percentage
	var health_pct = clamp(current_health / max_health, 0.0, 1.0) if max_health > 0 else 0.0
	
	# Update health bar width
	health_bar.anchor_right = health_pct
	
	# Update health bar color based on percentage
	var health_color = _get_health_color(health_pct)
	health_bar.color = health_color
	
	# Update health text
	health_text.text = "%d/%d" % [int(current_health), int(max_health)]
	
	# Make text white for better visibility
	health_text.modulate = Color.WHITE
	
	# Add outline to text for better readability
	health_text.add_theme_color_override("font_shadow_color", Color.BLACK)
	health_text.add_theme_constant_override("shadow_offset_x", 1)
	health_text.add_theme_constant_override("shadow_offset_y", 1)

func _get_health_color(health_pct: float) -> Color:
	"""Get color based on health percentage"""
	if health_pct > 0.66:
		return Color(0, 0.8, 0, 1)  # Green
	elif health_pct > 0.33:
		return Color(1, 0.8, 0, 1)  # Yellow
	else:
		return Color(1, 0.2, 0, 1)  # Red

func set_visibility(visible: bool) -> void:
	"""Set the visibility of the health bar"""
	self.visible = visible

func update_team_border(team_id: int) -> void:
	"""Update the border color for a different team (if needed)"""
	if not health_panel:
		return
	
	var border_color = team_colors.get(team_id, Color.WHITE)
	var current_style = health_panel.get_theme_stylebox("panel")
	
	if current_style is StyleBoxFlat:
		current_style.border_color = border_color

func set_hide_when_full(hide: bool) -> void:
	"""Set whether to hide the health bar when unit is at full health"""
	hide_when_full = hide 