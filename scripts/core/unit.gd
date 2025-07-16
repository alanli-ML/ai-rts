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

# Unit stats
var max_health: float = 100.0
var current_health: float = 100.0
var movement_speed: float = 5.0
var attack_damage: float = 10.0
var attack_range: float = 15.0
var attack_cooldown: float = 1.0
var last_attack_time: float = 0.0

# State
var current_state: GameEnums.UnitState = GameEnums.UnitState.IDLE
var is_dead: bool = false
var target_unit: Unit = null

# Movement
var navigation_agent: NavigationAgent3D

signal health_changed(new_health: float, max_health: float)
signal unit_died(unit_id: String)

func _ready() -> void:
    if unit_id.is_empty():
        unit_id = "unit_" + str(randi())
    
    add_to_group("units")
    add_to_group("selectable") # For selection system
    
    navigation_agent = NavigationAgent3D.new()
    add_child(navigation_agent)
    
    # Explicitly set collision layer for selection raycasts (Layer 1 = Units)
    # This is critical for the EnhancedSelectionSystem to detect units.
    set_collision_layer_value(1, true)
    
    # Ensure a collision shape exists for physics queries
    var collision = get_node_or_null("CollisionShape3D")
    if not collision:
        collision = CollisionShape3D.new()
        collision.name = "CollisionShape3D"
        var shape = CapsuleShape3D.new()
        shape.radius = 2.5 # Much larger radius for realistic character selection
        shape.height = 4.0 # Taller to match typical character height
        collision.shape = shape
        add_child(collision)
        
        # Optional: Enable debug visualization in editor
        if Engine.is_editor_hint():
            collision.visible = true
    
    print("Unit %s: Collision shape - radius: %s, height: %s" % [unit_id, 2.5, 4.0])
    
    _load_archetype_stats()
    health_changed.connect(func(new_health, _max_health): if new_health <= 0: die())

func _load_archetype_stats() -> void:
    var config = GameConstants.get_unit_config(archetype)
    if not config.is_empty():
        max_health = config.get("health", 100.0)
        current_health = max_health
        movement_speed = config.get("speed", 5.0)
        attack_damage = config.get("damage", 10.0)
        attack_range = config.get("range", 15.0)

func _physics_process(delta: float) -> void:
    if is_dead: return

    match current_state:
        GameEnums.UnitState.ATTACKING:
            if not is_instance_valid(target_unit) or target_unit.is_dead:
                current_state = GameEnums.UnitState.IDLE
                return
            
            var distance = global_position.distance_to(target_unit.global_position)
            if distance > attack_range:
                # Move towards target
                move_to(target_unit.global_position)
            else:
                # Stop moving and attack
                velocity = Vector3.ZERO
                
                # Turn to face the target
                look_at(target_unit.global_position, Vector3.UP)
                
                var current_time = Time.get_ticks_msec() / 1000.0
                if current_time - last_attack_time >= attack_cooldown:
                    target_unit.take_damage(attack_damage)
                    last_attack_time = current_time
        _: # Default case for IDLE, MOVING, etc.
            if navigation_agent and not navigation_agent.is_navigation_finished():
                var next_pos = navigation_agent.get_next_path_position()
                var direction = global_position.direction_to(next_pos)
                velocity = direction * movement_speed
                move_and_slide()
            else:
                velocity = Vector3.ZERO

func move_to(target_position: Vector3) -> void:
    current_state = GameEnums.UnitState.MOVING
    if navigation_agent:
        navigation_agent.target_position = target_position

func attack_target(target: Unit) -> void:
    if not is_instance_valid(target): return
    target_unit = target
    current_state = GameEnums.UnitState.ATTACKING

func take_damage(damage: float) -> void:
    if is_dead: return
    current_health = max(0, current_health - damage)
    health_changed.emit(current_health, max_health)

func die() -> void:
    if is_dead: return
    is_dead = true
    current_state = GameEnums.UnitState.DEAD
    unit_died.emit(unit_id)
    # The server game state will handle queue_free() after broadcasting the death.
    # On the client, the display manager will handle freeing the visual node.
    # On server, this is acceptable for now.
    if get_tree().is_server():
        call_deferred("queue_free")

func get_health_percentage() -> float:
    return current_health / max_health if max_health > 0 else 0.0

func get_team_id() -> int:
    return team_id

func get_unit_info() -> Dictionary:
    return {
        "id": unit_id,
        "archetype": archetype,
        "health_pct": get_health_percentage() * 100,
        "position": [global_position.x, global_position.y, global_position.z],
        "team_id": team_id
    }

# Placeholder methods for plan executor
func retreat(): pass
func start_patrol(_waypoints): pass
func use_ability(_ability_name): pass
func set_formation(_formation): pass
func set_stance(_stance): pass

# Selection system methods
var is_selected: bool = false
var selection_highlight: Node3D = null

func select() -> void:
    """Called when this unit is selected"""
    if is_selected:
        return
    
    is_selected = true
    _create_selection_highlight()
    print("Unit %s (%s) selected" % [unit_id, archetype])

func deselect() -> void:
    """Called when this unit is deselected"""
    if not is_selected:
        return
    
    is_selected = false
    _remove_selection_highlight()

func _create_selection_highlight() -> void:
    """Create visual selection feedback"""
    if selection_highlight:
        return
    
    # Create a simple selection circle using MeshInstance3D with a cylinder mesh
    selection_highlight = MeshInstance3D.new()
    selection_highlight.name = "SelectionHighlight"
    
    # Create cylinder mesh
    var cylinder_mesh = CylinderMesh.new()
    cylinder_mesh.height = 0.1
    cylinder_mesh.top_radius = 1.2
    cylinder_mesh.bottom_radius = 1.2
    selection_highlight.mesh = cylinder_mesh
    
    # Position slightly above ground
    selection_highlight.position.y = 0.05
    
    # Make it green and semi-transparent
    var material = StandardMaterial3D.new()
    material.albedo_color = Color(0.2, 1.0, 0.2, 0.6)
    material.flags_transparent = true
    material.no_depth_test = true
    selection_highlight.material_override = material
    
    add_child(selection_highlight)

func _remove_selection_highlight() -> void:
    """Remove visual selection feedback"""
    if selection_highlight:
        selection_highlight.queue_free()
        selection_highlight = null

# Debug functions for collision visualization
func show_collision_debug(show_debug: bool = true) -> void:
    """Toggle collision shape visibility for debugging"""
    var collision = get_node_or_null("CollisionShape3D")
    if collision:
        collision.visible = show_debug
        if show_debug:
            print("Unit %s: Showing collision debug (radius: 2.5, height: 4.0)" % unit_id)

func get_collision_info() -> Dictionary:
    """Get collision shape information for debugging"""
    var collision = get_node_or_null("CollisionShape3D")
    if collision and collision.shape is CapsuleShape3D:
        var shape = collision.shape as CapsuleShape3D
        return {
            "type": "CapsuleShape3D",
            "radius": shape.radius,
            "height": shape.height,
            "position": collision.position
        }
    return {"type": "none"}