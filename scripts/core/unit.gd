# Unit.gd - Base unit class
class_name Unit
extends CharacterBody3D

# Load shared components
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# Unit identification
@export var unit_id: String = ""
@export var archetype: String = "scout"
@export var team_id: int = 1
@export var system_prompt: String = ""
@export var unit_type: String = ""
@export var owner_player_id: String = ""

# Unit stats (loaded from GameConstants)
var max_health: float = 100.0
var current_health: float = 100.0
var movement_speed: float = 5.0
var attack_damage: float = 25.0
var attack_range: float = 3.0
var vision_range: float = 8.0
var vision_angle: float = 120.0
var speed: float = 10.0

# State variables
var current_state: GameEnums.UnitState = GameEnums.UnitState.IDLE
var previous_state: GameEnums.UnitState = GameEnums.UnitState.IDLE
var state_timer: float = 0.0
var attack_cooldown: float = 1.0
var ability_cooldown: float = 0.0
var last_attack_time: float = 0.0

# Combat and targeting
var target_unit: Unit = null
var target_position: Vector3 = Vector3.ZERO
var can_attack: bool = true

# Unit status
var morale: float = 1.0
var energy: float = 100.0
var is_selected: bool = false
var is_moving: bool = false
var is_attacking: bool = false
var is_dead: bool = false

# Movement and navigation
var movement_target: Vector3 = Vector3.ZERO
var destination: Vector3 = Vector3.ZERO

# AI/Vision system
var visible_enemies: Array[Unit] = []
var visible_allies: Array[Unit] = []

# Node references (created programmatically)
var navigation_agent: NavigationAgent3D
var health_bar: ProgressBar
var selection_indicator: MeshInstance3D
var vision_area: Area3D
var combat_area: Area3D

# Signals
signal unit_selected(unit: Unit)
signal unit_deselected(unit: Unit)
signal unit_destroyed(unit_id: String)
signal unit_died(unit: Unit)
signal unit_health_changed(unit_id: String, health: float)
signal unit_state_changed(unit_id: String, state: GameEnums.UnitState)
signal health_changed(new_health: float, max_health: float)
signal enemy_sighted(enemy: Unit)
signal command_received(command: Dictionary)

func _ready() -> void:
    # Generate unique ID if not set
    if unit_id.is_empty():
        unit_id = "unit_" + str(randi())
    
    # Set unit_type from archetype if not set
    if unit_type.is_empty():
        unit_type = archetype
    
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
    
    print("Unit %s (%s) initialized for team %d" % [unit_id, archetype, team_id])

func _create_child_nodes() -> void:
    # Create NavigationAgent3D
    navigation_agent = NavigationAgent3D.new()
    navigation_agent.name = "NavigationAgent3D"
    add_child(navigation_agent)
    
    # Create basic visual representation
    var mesh_instance = MeshInstance3D.new()
    mesh_instance.name = "UnitMesh"
    mesh_instance.mesh = CapsuleMesh.new()
    var material = StandardMaterial3D.new()
    material.albedo_color = Color.BLUE if team_id == 1 else Color.RED
    mesh_instance.material_override = material
    add_child(mesh_instance)
    
    # Create collision shape
    var collision_shape = CollisionShape3D.new()
    collision_shape.name = "CollisionShape3D"
    var shape = CapsuleShape3D.new()
    shape.height = 2.0
    shape.radius = 0.5
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
    # Use GameConstants for unit configuration
    var unit_config = GameConstants.get_unit_config(archetype)
    if unit_config.is_empty():
        print("No stats found for archetype: %s, using defaults" % archetype)
        unit_config = GameConstants.get_unit_config("scout")  # Fallback to scout
    
    if not unit_config.is_empty():
        max_health = unit_config.get("health", 100.0)
        current_health = max_health
        movement_speed = unit_config.get("speed", 5.0)
        attack_damage = unit_config.get("damage", 25.0)
        attack_range = unit_config.get("range", 3.0)
        vision_range = unit_config.get("vision", 8.0)
        speed = movement_speed
    
    # Update vision area radius
    if vision_area:
        var vision_collision = vision_area.get_node("VisionCollision")
        if vision_collision and vision_collision.shape:
            vision_collision.shape.radius = vision_range
    
    # Update combat area radius
    if combat_area:
        var combat_collision = combat_area.get_node("CombatCollision")
        if combat_collision and combat_collision.shape:
            combat_collision.shape.radius = attack_range

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
    # Register with EventBus if available
    if has_node("/root/EventBus"):
        var event_bus = get_node("/root/EventBus")
        if event_bus.has_signal("unit_spawned"):
            event_bus.unit_spawned.emit(self)

func _physics_process(delta: float) -> void:
    if current_state == GameEnums.UnitState.DEAD:
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
    if current_state == GameEnums.UnitState.DEAD:
        return
    
    # Handle movement with NavigationAgent3D
    if navigation_agent and navigation_agent.is_navigation_finished():
        is_moving = false
        velocity = Vector3.ZERO
        if current_state == GameEnums.UnitState.MOVING:
            change_state(GameEnums.UnitState.IDLE)
    elif navigation_agent and not navigation_agent.is_navigation_finished():
        is_moving = true
        var next_position = navigation_agent.get_next_path_position()
        var direction = (next_position - global_position).normalized()
        velocity = direction * movement_speed
        
        # Face movement direction
        if direction.length() > 0.1:
            look_at(global_position + direction, Vector3.UP)
        
        # Check if we've reached the target
        if global_position.distance_to(movement_target) < 0.5:
            _stop_movement()
    
    move_and_slide()

func move_to(target_pos: Vector3) -> void:
    """Move the unit to the target position"""
    if current_state == GameEnums.UnitState.DEAD:
        return
    
    movement_target = target_pos
    destination = target_pos
    is_moving = true
    change_state(GameEnums.UnitState.MOVING)
    
    if navigation_agent:
        navigation_agent.target_position = target_pos
    
    print("Unit %s moving to %s" % [unit_id, target_pos])

func attack_target(target: Unit) -> void:
    """Attack the target unit"""
    if not target or current_health <= 0 or target.current_health <= 0:
        return
    
    var distance = global_position.distance_to(target.global_position)
    if distance > attack_range:
        # Move closer to target
        move_to(target.global_position)
        target_unit = target
        return
    
    # Check attack cooldown
    var current_time = Time.get_ticks_msec() / 1000.0
    if current_time - last_attack_time < attack_cooldown:
        return
    
    # Perform attack
    target.take_damage(attack_damage)
    last_attack_time = current_time
    change_state(GameEnums.UnitState.ATTACKING)
    is_attacking = true

func take_damage(damage: float) -> void:
    """Take damage and handle death"""
    if current_state == GameEnums.UnitState.DEAD:
        return
    
    current_health -= damage
    current_health = max(0, current_health)
    
    health_changed.emit(current_health, max_health)
    unit_health_changed.emit(unit_id, current_health)
    
    if current_health <= 0:
        die()

func heal(amount: float) -> void:
    """Heal the unit"""
    if current_state == GameEnums.UnitState.DEAD:
        return
    
    current_health = min(max_health, current_health + amount)
    health_changed.emit(current_health, max_health)
    unit_health_changed.emit(unit_id, current_health)

func die() -> void:
    """Handle unit death"""
    change_state(GameEnums.UnitState.DEAD)
    is_dead = true
    is_selected = false
    is_attacking = false
    is_moving = false
    
    print("Unit %s died" % unit_id)
    unit_died.emit(self)
    unit_destroyed.emit(unit_id)
    
    # Remove from scene
    queue_free()

func stop() -> void:
    """Stop current action"""
    _stop_movement()
    target_unit = null
    is_attacking = false
    change_state(GameEnums.UnitState.IDLE)

func _stop_movement() -> void:
    """Stop movement"""
    is_moving = false
    velocity = Vector3.ZERO
    if current_state == GameEnums.UnitState.MOVING:
        change_state(GameEnums.UnitState.IDLE)

func change_state(new_state: GameEnums.UnitState) -> void:
    """Change unit state"""
    if new_state == current_state:
        return
    
    previous_state = current_state
    current_state = new_state
    state_timer = 0.0
    
    unit_state_changed.emit(unit_id, current_state)
    print("Unit %s changed state from %s to %s" % [unit_id, GameEnums.get_unit_state_string(previous_state), GameEnums.get_unit_state_string(current_state)])

func select() -> void:
    """Handle unit selection"""
    if is_dead:
        return
    
    is_selected = true
    if selection_indicator:
        selection_indicator.visible = true
    unit_selected.emit(self)

func deselect() -> void:
    """Handle unit deselection"""
    is_selected = false
    if selection_indicator:
        selection_indicator.visible = false
    unit_deselected.emit(self)

func _update_vision() -> void:
    """Update vision system"""
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

func server_update(delta: float) -> void:
    """Server-side update (called by game state)"""
    # Update AI behavior, combat, etc.
    _update_ai_behavior(delta)
    _update_combat(delta)

func _update_ai_behavior(_delta: float) -> void:
    """Update AI behavior"""
    # Basic AI: attack nearby enemies
    if target_unit and target_unit.current_health > 0:
        attack_target(target_unit)
    else:
        # Look for enemies in vision
        for enemy in visible_enemies:
            if enemy.current_health > 0:
                attack_target(enemy)
                break

func _update_combat(_delta: float) -> void:
    """Update combat logic"""
    # Handle combat cooldowns, state transitions, etc.
    if is_attacking and attack_cooldown <= 0:
        is_attacking = false
        if current_state == GameEnums.UnitState.ATTACKING:
            change_state(GameEnums.UnitState.IDLE)

# Utility functions
func get_team_id() -> int:
    return team_id

func get_health_percentage() -> float:
    return current_health / max_health if max_health > 0 else 0.0

func get_state_name() -> String:
    return GameEnums.get_unit_state_string(current_state)

func get_unit_id() -> String:
    return unit_id

func get_archetype() -> String:
    return archetype

func get_unit_info() -> Dictionary:
    """Get unit information for AI system"""
    return {
        "id": unit_id,
        "archetype": archetype,
        "health": current_health,
        "max_health": max_health,
        "position": [global_position.x, global_position.y, global_position.z],
        "state": get_state_name().to_lower(),
        "team_id": team_id,
        "speed": movement_speed,
        "vision_range": vision_range,
        "attack_range": attack_range,
        "abilities": _get_available_abilities(),
        "is_selected": is_selected,
        "is_moving": is_moving,
        "is_attacking": is_attacking,
        "morale": morale,
        "energy": energy
    }

func get_unit_data() -> Dictionary:
    """Get unit data for networking"""
    return {
        "id": unit_id,
        "unit_type": unit_type,
        "team_id": team_id,
        "position": [global_position.x, global_position.y, global_position.z],
        "rotation": rotation.y,
        "health": current_health,
        "max_health": max_health,
        "state": current_state
    }

func _get_available_abilities() -> Array[String]:
    """Get list of available abilities for this unit"""
    var abilities = []
    
    # Add unit-specific abilities based on archetype
    match archetype:
        "scout":
            abilities.append("stealth")
            abilities.append("mark_target")
        "sniper":
            abilities.append("snipe")
            abilities.append("overwatch")
        "medic":
            abilities.append("heal")
            abilities.append("revive")
        "engineer":
            abilities.append("repair")
            abilities.append("build_turret")
        "tank":
            abilities.append("charge")
            abilities.append("shield")
    
    return abilities

# Signal handlers
func _on_unit_entered_vision(body: Node3D) -> void:
    if body != self and body.has_method("get_team_id"):
        var other_unit = body as Unit
        if other_unit and not other_unit.is_dead:
            print("Unit %s detected %s in vision range" % [unit_id, other_unit.unit_id])

func _on_unit_exited_vision(body: Node3D) -> void:
    if body != self and body.has_method("get_team_id"):
        var other_unit = body as Unit
        if other_unit:
            print("Unit %s lost sight of %s" % [unit_id, other_unit.unit_id])

func _on_command_received(command: Dictionary) -> void:
    if command.get("unit_id") == unit_id:
        print("Unit %s received command: %s" % [unit_id, command])
        command_received.emit(command)
        # Process command here

func _on_health_changed(_new_health: float, _max_health: float) -> void:
    # Health bar updates will be implemented later
    pass

func show_speech_bubble(text: String, duration: float = 3.0) -> void:
    """Show a speech bubble above this unit"""
    
    # Try to find SpeechBubbleManager
    var speech_bubble_manager = _get_speech_bubble_manager()
    if speech_bubble_manager:
        speech_bubble_manager.show_speech_bubble(unit_id, text, team_id)
    else:
        # Fallback: use EventBus if available
        if has_node("/root/EventBus"):
            var event_bus = get_node("/root/EventBus")
            if event_bus.has_signal("unit_command_issued"):
                event_bus.unit_command_issued.emit(unit_id, "speech:%s" % text)
        else:
            print("Unit %s says: %s" % [unit_id, text])

func _get_speech_bubble_manager() -> Node:
    """Get the SpeechBubbleManager instance"""
    
    # Try to find in scene tree
    var managers = get_tree().get_nodes_in_group("speech_bubble_managers")
    if managers.size() > 0:
        return managers[0]
    
    # Try to find by name
    var scene_root = get_tree().current_scene
    if scene_root:
        var manager = scene_root.find_child("SpeechBubbleManager", true, false)
        if manager:
            return manager
    
    # Try to find as autoload
    if has_node("/root/SpeechBubbleManager"):
        return get_node("/root/SpeechBubbleManager")
    
    return null

func say(text: String) -> void:
    """Convenience method for showing speech bubbles"""
    show_speech_bubble(text) 