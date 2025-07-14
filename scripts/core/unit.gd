# Unit.gd
class_name Unit
extends CharacterBody3D

# Unit states
enum UnitState {
	IDLE,
	MOVING,
	ATTACKING,
	USING_ABILITY,
	DEAD
}

# Unit identification
@export var unit_id: String
@export var archetype: String = "scout"
@export var team_id: int = 1
@export var system_prompt: String = ""

# Unit stats (loaded from ConfigManager)
var max_health: float = 100.0
var current_health: float = 100.0
var speed: float = 10.0
var vision_range: float = 30.0
var vision_angle: float = 120.0
var attack_range: float = 15.0
var attack_damage: float = 20.0

# State variables
var current_state: UnitState = UnitState.IDLE
var previous_state: UnitState = UnitState.IDLE
var state_timer: float = 0.0
var attack_cooldown: float = 0.0
var ability_cooldown: float = 0.0
var target_unit: Unit = null

var morale: float = 1.0
var energy: float = 100.0
var is_selected: bool = false
var is_moving: bool = false
var is_attacking: bool = false
var is_dead: bool = false

# Movement and navigation
var move_speed: float = 10.0
var destination: Vector3

# AI/Vision system
var visible_enemies: Array[Unit] = []
var visible_allies: Array[Unit] = []
var can_attack: bool = true

# Node references (created programmatically)
var navigation_agent: NavigationAgent3D
var health_bar: ProgressBar
var selection_indicator: MeshInstance3D
var vision_area: Area3D
var combat_area: Area3D

# Signals
signal unit_selected(unit: Unit)
signal unit_deselected(unit: Unit)
signal unit_died(unit: Unit)
signal health_changed(new_health: float, max_health: float)
signal enemy_sighted(enemy: Unit)
signal command_received(command: Dictionary)

func _ready() -> void:
	# Generate unique ID
	unit_id = "unit_" + str(randi())
	
	# Create child nodes
	_create_child_nodes()
	
	# Load archetype stats
	_load_archetype_stats()
	
	# Setup navigation
	_setup_navigation()
	
	# Setup UI
	_setup_ui()
	
	# Setup vision system
	_setup_vision()
	
	# Add to units group for easy access
	add_to_group("units")
	
	# Register with game systems
	_register_unit()
	
	Logger.info("Unit", "Unit %s (%s) initialized for team %d" % [unit_id, archetype, team_id])

func _create_child_nodes() -> void:
	# Create NavigationAgent3D
	navigation_agent = NavigationAgent3D.new()
	navigation_agent.name = "NavigationAgent3D"
	add_child(navigation_agent)
	
	# Create basic visual representation
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "UnitMesh"
	mesh_instance.mesh = BoxMesh.new()
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.BLUE if team_id == 1 else Color.RED
	mesh_instance.material_override = material
	add_child(mesh_instance)
	
	# Create collision shape
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var shape = BoxShape3D.new()
	shape.size = Vector3(1, 1, 1)
	collision_shape.shape = shape
	add_child(collision_shape)
	
	# Create selection indicator
	selection_indicator = MeshInstance3D.new()
	selection_indicator.name = "SelectionIndicator"
	selection_indicator.mesh = SphereMesh.new()
	selection_indicator.mesh.radius = 1.2
	selection_indicator.mesh.height = 0.1
	selection_indicator.position.y = -0.6
	selection_indicator.visible = false
	var selection_material = StandardMaterial3D.new()
	selection_material.albedo_color = Color.GREEN
	selection_material.flags_transparent = true
	selection_material.albedo_color.a = 0.5
	selection_indicator.material_override = selection_material
	add_child(selection_indicator)
	
	# Create vision area
	vision_area = Area3D.new()
	vision_area.name = "VisionArea"
	var vision_collision = CollisionShape3D.new()
	vision_collision.name = "VisionCollision"
	var vision_shape = SphereShape3D.new()
	vision_shape.radius = vision_range
	vision_collision.shape = vision_shape
	vision_area.add_child(vision_collision)
	add_child(vision_area)
	
	# Create combat area (for close combat detection)
	combat_area = Area3D.new()
	combat_area.name = "CombatArea"
	var combat_collision = CollisionShape3D.new()
	combat_collision.name = "CombatCollision"
	var combat_shape = SphereShape3D.new()
	combat_shape.radius = attack_range
	combat_collision.shape = combat_shape
	combat_area.add_child(combat_collision)
	add_child(combat_area)

func _load_archetype_stats() -> void:
	var stats = ConfigManager.get_unit_stats(archetype)
	if stats.is_empty():
		Logger.warning("Unit", "No stats found for archetype: %s" % archetype)
		return
		
	max_health = stats.get("health", 100.0)
	current_health = max_health
	speed = stats.get("speed", 10.0)
	vision_range = stats.get("vision_range", 25.0)
	vision_angle = stats.get("vision_angle", 120.0)
	attack_range = stats.get("attack_range", 15.0)
	attack_damage = stats.get("attack_damage", 20.0)
	
	# Set navigation speed
	move_speed = speed

func _setup_navigation() -> void:
	if navigation_agent:
		navigation_agent.path_desired_distance = 0.5
		navigation_agent.target_desired_distance = 0.5
		navigation_agent.path_max_distance = 3.0

func _setup_ui() -> void:
	# Health bar will be implemented later with proper UI
	pass

func _setup_vision() -> void:
	# Setup vision area
	if vision_area:
		vision_area.body_entered.connect(_on_unit_entered_vision)
		vision_area.body_exited.connect(_on_unit_exited_vision)

func _register_unit() -> void:
	# Register with EventBus
	EventBus.unit_spawned.emit(self)
	
	# Register with GameManager
	GameManager.register_unit(self)

func _physics_process(delta: float) -> void:
	if current_state == UnitState.DEAD:
		return
	
	# Update timers
	state_timer += delta
	if attack_cooldown > 0:
		attack_cooldown -= delta
	if ability_cooldown > 0:
		ability_cooldown -= delta
	
	# Handle movement
	_handle_movement(delta)
	
	# Update vision system
	_update_vision()

func _handle_movement(delta: float) -> void:
	if current_state == UnitState.DEAD:
		return
	
	# Handle movement
	if navigation_agent and navigation_agent.is_navigation_finished():
		is_moving = false
		velocity = Vector3.ZERO
	elif navigation_agent:
		is_moving = true
		var next_position = navigation_agent.get_next_path_position()
		var direction = (next_position - global_position).normalized()
		velocity = direction * move_speed
		
		# Face movement direction
		if direction.length() > 0.1:
			look_at(global_position + direction, Vector3.UP)
	
	move_and_slide()

func move_to(target_position: Vector3) -> void:
	if current_state == UnitState.DEAD:
		return
	
	destination = target_position
	if navigation_agent:
		navigation_agent.target_position = target_position
	is_moving = true
	Logger.debug("Unit", "Unit %s moving to %s" % [unit_id, target_position])

func _update_vision() -> void:
	# Clear old lists
	visible_enemies.clear()
	visible_allies.clear()
	
	# Check all units in vision area
	if vision_area:
		for body in vision_area.get_overlapping_bodies():
			if body != self and body.has_method("get_team_id"):
				var other_unit = body as Unit
				if other_unit and not other_unit.is_dead:
					# Check if unit is in vision cone
					var direction_to_unit = (other_unit.global_position - global_position).normalized()
					var forward = -global_transform.basis.z
					var angle = acos(forward.dot(direction_to_unit))
					
					if angle <= deg_to_rad(vision_angle / 2.0):
						if other_unit.team_id != team_id:
							visible_enemies.append(other_unit)
							enemy_sighted.emit(other_unit)
						else:
							visible_allies.append(other_unit)

func get_team_id() -> int:
	return team_id

func take_damage(damage: float) -> void:
	if current_state == UnitState.DEAD:
		return
	
	current_health -= damage
	current_health = max(0, current_health)
	
	health_changed.emit(current_health, max_health)
	
	if current_health <= 0:
		die()

func heal(amount: float) -> void:
	if current_state == UnitState.DEAD:
		return
	
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

func die() -> void:
	change_state(UnitState.DEAD)
	is_dead = true
	is_selected = false
	Logger.info("Unit", "Unit %s died" % unit_id)
	unit_died.emit(self)
	
	# Play death animation/effects here
	queue_free()

func change_state(new_state: UnitState) -> void:
	if new_state == current_state:
		return
	
	previous_state = current_state
	current_state = new_state
	state_timer = 0.0
	
	Logger.debug("Unit", "Unit %s changed state from %s to %s" % [unit_id, UnitState.keys()[previous_state], UnitState.keys()[current_state]])

func select() -> void:
	if is_dead:
		return
	
	is_selected = true
	if selection_indicator:
		selection_indicator.visible = true
	unit_selected.emit(self)

func deselect() -> void:
	is_selected = false
	if selection_indicator:
		selection_indicator.visible = false
	unit_deselected.emit(self)

func get_health_percentage() -> float:
	return current_health / max_health if max_health > 0 else 0.0

func _on_unit_entered_vision(body: Node3D) -> void:
	if body != self and body.has_method("get_team_id"):
		var other_unit = body as Unit
		if other_unit and not other_unit.is_dead:
			Logger.debug("Unit", "Unit %s detected %s in vision range" % [unit_id, other_unit.unit_id])

func _on_unit_exited_vision(body: Node3D) -> void:
	if body != self and body.has_method("get_team_id"):
		var other_unit = body as Unit
		if other_unit:
			Logger.debug("Unit", "Unit %s lost sight of %s" % [unit_id, other_unit.unit_id])

func _on_command_received(command: Dictionary) -> void:
	if command.get("unit_id") == unit_id:
		Logger.debug("Unit", "Unit %s received command: %s" % [unit_id, command])
		# Process command here

func _on_health_changed(new_health: float, max_health: float) -> void:
	# Health bar updates will be implemented later
	pass