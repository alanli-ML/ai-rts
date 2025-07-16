# FallbackUnitBehavior.gd - Minimal unit behavior when script system fails
extends CharacterBody3D

# Essential unit properties - set via set() calls from spawner
var team_id: int = 1
var archetype: String = "scout"
var unit_id: String = ""
var max_health: float = 100.0
var current_health: float = 100.0
var movement_speed: float = 5.0
var attack_damage: float = 10.0
var attack_range: float = 15.0
var is_dead: bool = false

# Navigation
var navigation_agent: NavigationAgent3D

# Selection state
var is_selected: bool = false
var selection_highlight: Node3D = null

# Signals
signal unit_died(unit_id: String)

func _ready() -> void:
	if unit_id.is_empty():
		unit_id = "fallback_unit_" + str(randi())
	
	# Add navigation agent
	navigation_agent = NavigationAgent3D.new()
	add_child(navigation_agent)
	
	# Ensure groups are set
	add_to_group("units")
	add_to_group("selectable")
	
	print("FallbackUnit: Initialized fallback unit %s (%s) for team %d" % [unit_id, archetype, team_id])

func get_team_id() -> int:
	return team_id

func get_unit_info() -> Dictionary:
	return {
		"id": unit_id,
		"archetype": archetype,
		"health_pct": (current_health / max_health) * 100.0 if max_health > 0 else 0.0,
		"position": [global_position.x, global_position.y, global_position.z],
		"team_id": team_id
	}

func take_damage(damage: float) -> void:
	if is_dead:
		return
	
	current_health = max(0, current_health - damage)
	print("FallbackUnit %s took %f damage, health: %f/%f" % [unit_id, damage, current_health, max_health])
	
	if current_health <= 0:
		die()

func die() -> void:
	if is_dead:
		return
	
	is_dead = true
	print("FallbackUnit %s died" % unit_id)
	
	# Emit death signal if it exists
	if has_signal("unit_died"):
		emit_signal("unit_died", unit_id)
	
	# Simple death handling - just remove from game
	queue_free()

func connect_death_signal(callback: Callable) -> void:
	"""Connect death signal for units that don't have the standard signal"""
	if has_signal("unit_died"):
		unit_died.connect(callback)
	else:
		# Create the signal if it doesn't exist
		add_user_signal("unit_died", [{"name": "unit_id", "type": TYPE_STRING}])
		unit_died.connect(callback)

func move_to(target_position: Vector3) -> void:
	if navigation_agent and not is_dead:
		navigation_agent.target_position = target_position
		print("FallbackUnit %s moving to %s" % [unit_id, target_position])

func get_health_percentage() -> float:
	return current_health / max_health if max_health > 0 else 0.0

# Selection methods for compatibility
func select() -> void:
	if is_selected or is_dead:
		return
	
	is_selected = true
	_create_selection_highlight()
	print("FallbackUnit %s (%s) selected" % [unit_id, archetype])

func deselect() -> void:
	if not is_selected:
		return
	
	is_selected = false
	_remove_selection_highlight()

func _create_selection_highlight() -> void:
	if selection_highlight:
		return
	
	selection_highlight = MeshInstance3D.new()
	selection_highlight.name = "SelectionHighlight"
	
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 3.0
	cylinder_mesh.bottom_radius = 3.0
	cylinder_mesh.height = 0.1
	selection_highlight.mesh = cylinder_mesh
	
	var highlight_material = StandardMaterial3D.new()
	highlight_material.albedo_color = Color(0, 1, 0, 0.5)
	highlight_material.flags_transparent = true
	highlight_material.flags_unshaded = true
	selection_highlight.material_override = highlight_material
	
	add_child(selection_highlight)
	selection_highlight.position = Vector3(0, -2, 0)

func _remove_selection_highlight() -> void:
	if selection_highlight and is_instance_valid(selection_highlight):
		selection_highlight.queue_free()
		selection_highlight = null

# Basic physics for movement
func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	if navigation_agent and not navigation_agent.is_navigation_finished():
		var next_pos = navigation_agent.get_next_path_position()
		var direction = global_position.direction_to(next_pos)
		velocity = direction * movement_speed
		move_and_slide()
	else:
		velocity = Vector3.ZERO 