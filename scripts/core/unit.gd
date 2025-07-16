# Unit.gd - Base unit class
class_name Unit
extends CharacterBody3D

# Load shared components
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const UnitStatusBarScene = preload("res://scenes/units/UnitStatusBar.tscn")
const UnitRangeVisualizationScene = preload("res://scenes/units/UnitRangeVisualization.tscn")

# Unit identification
@export var unit_id: String = ""
@export var archetype: String = "scout"
@export var team_id: int = 1
@export var system_prompt: String = "You are a generic RTS unit. Follow orders precisely."

# Unit stats
var max_health: float = 100.0
var current_health: float = 100.0
var movement_speed: float = 5.0
var attack_damage: float = 10.0
var attack_range: float = 15.0
var vision_range: float = 30.0
var attack_cooldown: float = 1.0
var last_attack_time: float = 0.0
var ammo: int = 30
var max_ammo: int = 30
var morale: float = 1.0
const FOLLOW_DISTANCE = 5.0

# State
var current_state: GameEnums.UnitState = GameEnums.UnitState.IDLE
var is_dead: bool = false
var strategic_goal: String = "Act autonomously based on my unit type."
var plan_summary: String = "Idle"  # Client-side display of current plan status
var full_plan: Array = []  # Client-side storage of complete plan data
var waiting_for_ai: bool = false  # Client-side flag for AI processing status
var target_unit: Unit = null
var follow_target: Unit = null
var target_building: Node = null
var weapon_attachment: Node = null
var can_move: bool = true
var status_bar: Node3D = null
var range_visualization: Node3D = null

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
        # The collision shape should now be part of the scene.
        # If it's not here, it's an error.
        push_error("Unit %s is missing its CollisionShape3D." % name)
    
    # Create status bar
    _create_status_bar()
    
    # Create range visualization
    _create_range_visualization()
    
    _load_archetype_stats()
    health_changed.connect(func(new_health, _max_health): if new_health <= 0: die())

    # Defer enabling physics process to prevent falling through floor on spawn
    set_physics_process(false)
    call_deferred("_enable_physics")

func _enable_physics():
    set_physics_process(true)

func _load_archetype_stats() -> void:
    var config = GameConstants.get_unit_config(archetype)
    if not config.is_empty():
        max_health = config.get("health", 100.0)
        current_health = max_health
        movement_speed = config.get("speed", 5.0)
        attack_damage = config.get("damage", 10.0)
        attack_range = config.get("range", 15.0)
        vision_range = config.get("vision", 30.0)
        
        # Refresh range visualization with new stats
        call_deferred("refresh_range_visualization")

func _physics_process(delta: float) -> void:
    if is_dead: return

    # Always apply gravity regardless of state
    if not is_on_floor():
        velocity.y += get_gravity().y * delta

    # State machine logic
    match current_state:
        GameEnums.UnitState.ATTACKING:
            if not is_instance_valid(target_unit) or target_unit.is_dead:
                print("DEBUG: Unit %s stopping attack - target invalid or dead" % unit_id)
                current_state = GameEnums.UnitState.IDLE
            else:
                var distance = global_position.distance_to(target_unit.global_position)
                if distance > attack_range:
                    print("DEBUG: Unit %s moving closer to target %s (distance: %.1f > range: %.1f)" % [unit_id, target_unit.unit_id, distance, attack_range])
                    move_to(target_unit.global_position)
                else:
                    # Stop moving and attack
                    velocity.x = 0
                    velocity.z = 0
                    look_at(target_unit.global_position, Vector3.UP)
                    var current_time = Time.get_ticks_msec() / 1000.0
                    if current_time - last_attack_time >= attack_cooldown:
                        print("DEBUG: Unit %s attempting to fire at target %s" % [unit_id, target_unit.unit_id])
                        var attack_successful = false
                        
                        # Try weapon attachment first
                        if weapon_attachment and weapon_attachment.has_method("fire"):
                            print("DEBUG: Unit %s has weapon attachment, checking if can fire" % unit_id)
                            if weapon_attachment.can_fire():
                                print("DEBUG: Unit %s firing weapon at target %s" % [unit_id, target_unit.unit_id])
                                var fire_result = weapon_attachment.fire()
                                print("DEBUG: Weapon fire result: %s" % str(fire_result))
                                if not fire_result.is_empty():
                                    attack_successful = true
                            else:
                                print("DEBUG: Unit %s weapon cannot fire (ammo: %d, equipped: %s)" % [unit_id, weapon_attachment.current_ammo if weapon_attachment else 0, weapon_attachment.is_equipped if weapon_attachment else false])
                        
                        # Fallback to direct damage if weapon failed
                        if not attack_successful:
                            print("DEBUG: Unit %s using fallback direct damage (weapon failed or missing)" % unit_id)
                            target_unit.take_damage(attack_damage)
                            print("DEBUG: Unit %s dealt %f direct damage to %s" % [unit_id, attack_damage, target_unit.unit_id])
                            attack_successful = true
                        
                        if attack_successful:
                            last_attack_time = current_time
                            print("DEBUG: Unit %s attack completed successfully" % unit_id)
                        else:
                            print("DEBUG: Unit %s attack failed completely" % unit_id)
                    else:
                        var cooldown_remaining = attack_cooldown - (current_time - last_attack_time)
                        print("DEBUG: Unit %s attack on cooldown (%.1fs remaining)" % [unit_id, cooldown_remaining])
        
        GameEnums.UnitState.HEALING:
            if not is_instance_valid(target_unit) or target_unit.is_dead or target_unit.get_health_percentage() >= 1.0:
                current_state = GameEnums.UnitState.IDLE
            else:
                var distance = global_position.distance_to(target_unit.global_position)
                if distance > attack_range: # Use attack_range as heal_range for simplicity
                    move_to(target_unit.global_position)
        
        GameEnums.UnitState.CONSTRUCTING, GameEnums.UnitState.REPAIRING:
            if not is_instance_valid(target_building):
                current_state = GameEnums.UnitState.IDLE
            else:
                var distance = global_position.distance_to(target_building.global_position)
                if distance > attack_range: # Use attack_range as build_range
                    move_to(target_building.global_position)
                else:
                    velocity.x = 0
                    velocity.z = 0
                    if target_building.has_method("add_construction_progress"):
                        var build_rate = self.build_rate if "build_rate" in self else 0.1
                        target_building.add_construction_progress(build_rate * delta)
                    if target_building.is_operational:
                        current_state = GameEnums.UnitState.IDLE
                        target_building = null
        
        GameEnums.UnitState.LAYING_MINES:
            velocity.x = 0
            velocity.z = 0
    
        _: # Default case for IDLE, MOVING, FOLLOWING etc.
            if current_state == GameEnums.UnitState.FOLLOWING:
                if not is_instance_valid(follow_target) or follow_target.is_dead:
                    current_state = GameEnums.UnitState.IDLE
                    follow_target = null
                else:
                    var distance_to_follow_target = global_position.distance_to(follow_target.global_position)
                    if distance_to_follow_target > FOLLOW_DISTANCE:
                        navigation_agent.target_position = follow_target.global_position
                    else:
                        navigation_agent.target_position = global_position # Stop

    # Calculate horizontal velocity from navigation agent if the unit can move
    if can_move:
        if navigation_agent and not navigation_agent.is_navigation_finished():
            var next_pos = navigation_agent.get_next_path_position()
            var direction = global_position.direction_to(next_pos)
            var horizontal_direction = Vector3(direction.x, 0, direction.z).normalized()
            velocity.x = horizontal_direction.x * movement_speed
            velocity.z = horizontal_direction.z * movement_speed
        else:
            velocity.x = 0
            velocity.z = 0
    else:
        velocity.x = 0
        velocity.z = 0

    # Always call move_and_slide to apply physics and update velocity
    move_and_slide()

func move_to(target_position: Vector3) -> void:
    current_state = GameEnums.UnitState.MOVING
    if navigation_agent:
        navigation_agent.target_position = target_position

func attack_target(target: Unit) -> void:
    if not is_instance_valid(target): 
        print("DEBUG: Unit %s received invalid attack target" % unit_id)
        return
    print("DEBUG: Unit %s setting attack target to %s" % [unit_id, target.unit_id])
    target_unit = target
    follow_target = null
    current_state = GameEnums.UnitState.ATTACKING

func follow(target: Unit) -> void:
    if not is_instance_valid(target) or target == self:
        return
    current_state = GameEnums.UnitState.FOLLOWING
    follow_target = target
    target_unit = null # Clear attack target

func take_damage(damage: float) -> void:
    if is_dead: return

    var old_health = current_health
    current_health = max(0, current_health - damage)
    
    # On server, broadcast RPC for damage indicator
    if multiplayer.is_server():
        var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
        if root_node:
            root_node.rpc("display_damage_indicator_rpc", unit_id, damage)

    health_changed.emit(current_health, max_health)
    
    if current_health <= 0 and not is_dead:
        die()

func receive_healing(amount: float):
    if is_dead: return
    current_health = min(current_health + amount, max_health)
    health_changed.emit(current_health, max_health)

func die() -> void:
    if is_dead: return
    is_dead = true
    current_state = GameEnums.UnitState.DEAD
    unit_died.emit(unit_id)
    # The server game state will handle queue_free() after broadcasting the death.
    # On the client, the display manager will handle freeing the visual node.
    # On server, this is acceptable for now.
    if multiplayer.is_server():
        call_deferred("queue_free")

func get_health_percentage() -> float:
    return current_health / max_health if max_health > 0 else 0.0

func get_team_id() -> int:
    return team_id

func get_unit_info() -> Dictionary:
    # This provides the detailed "unit_state" portion of the AI context.
    var info = {
        "id": unit_id,
        "archetype": archetype,
        "health_pct": get_health_percentage() * 100,
        "ammo_pct": (float(ammo) / max_ammo) * 100 if max_ammo > 0 else 0.0,
        "morale": morale,
        "position": [global_position.x, global_position.y, global_position.z],
        "current_state": GameEnums.get_unit_state_string(current_state),
        "is_under_fire": false, # This would be managed by a combat state tracker
        "strategic_goal": strategic_goal,
        "current_plan_summary": "", # This would be set by the plan executor
        "team_id": team_id,
        "is_dead": is_dead,
        "is_stealthed": false, # Default values
        "shield_active": false
    }
    if is_instance_valid(target_unit):
        info["target_id"] = target_unit.unit_id

    # Add archetype-specific info safely
    if "is_stealthed" in self:
        info["is_stealthed"] = self.is_stealthed
    if "shield_active" in self:
        info["shield_active"] = self.shield_active
    
    return info

# Placeholder methods for plan executor
func retreat(): pass
func start_patrol(_waypoints): pass

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
    
    # Show range visualization
    if range_visualization and range_visualization.has_method("show_ranges"):
        range_visualization.show_ranges()
    
    var audio_manager = get_node_or_null("/root/DependencyContainer/AudioManager")
    if audio_manager:
        audio_manager.play_sound_2d("res://assets/audio/ui/click_01.wav")
    
    print("Unit %s (%s) selected" % [unit_id, archetype])

func deselect() -> void:
    """Called when this unit is deselected"""
    if not is_selected:
        return
    
    is_selected = false
    _remove_selection_highlight()
    
    # Hide range visualization
    if range_visualization and range_visualization.has_method("hide_ranges"):
        range_visualization.hide_ranges()

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

func _create_status_bar() -> void:
    """Create and attach the status bar to this unit"""
    if status_bar:
        return  # Already has a status bar
    
    status_bar = UnitStatusBarScene.instantiate()
    add_child(status_bar)
    
    # Initialize with current plan summary
    if status_bar.has_method("update_status"):
        status_bar.update_status(plan_summary)

func _create_range_visualization() -> void:
    """Create and attach the range visualization to this unit"""
    if range_visualization:
        return  # Already has range visualization
    
    range_visualization = UnitRangeVisualizationScene.instantiate()
    add_child(range_visualization)
    
    # Set team colors after the node is ready
    call_deferred("_setup_range_visualization")

func _setup_range_visualization() -> void:
    """Setup range visualization after it's been added to the scene"""
    if range_visualization and range_visualization.has_method("set_team_colors"):
        range_visualization.set_team_colors(team_id)

func update_plan_summary(new_summary: String) -> void:
    """Update the plan summary and refresh the status bar"""
    plan_summary = new_summary
    
    # Update status bar if it exists
    if status_bar and status_bar.has_method("update_status"):
        status_bar.update_status(plan_summary)

func update_full_plan(full_plan_data: Array) -> void:
    """Update the full plan data and refresh the status bar"""
    # Update status bar with full plan if it exists
    if status_bar and status_bar.has_method("update_full_plan"):
        status_bar.update_full_plan(full_plan_data)
    elif status_bar and status_bar.has_method("update_status"):
        # Fallback to summary if full plan method doesn't exist
        status_bar.update_status(plan_summary)

func refresh_status_bar() -> void:
    """Refresh the status bar display (useful when goal or other info changes)"""
    if not status_bar:
        return
    
    # Refresh with current plan summary if no full plan available
    if full_plan.is_empty():
        if status_bar.has_method("update_status"):
            status_bar.update_status(plan_summary)
    else:
        if status_bar.has_method("update_full_plan"):
            status_bar.update_full_plan(full_plan)

func set_status_bar_visibility(visible: bool) -> void:
    """Set the visibility of the status bar"""
    if status_bar and status_bar.has_method("set_visibility"):
        status_bar.set_visibility(visible)

func refresh_range_visualization() -> void:
    """Refresh the range visualization (useful when unit stats change)"""
    if range_visualization and range_visualization.has_method("refresh_visualization"):
        range_visualization.refresh_visualization()

func set_range_visualization_visibility(visible: bool) -> void:
    """Set the visibility of the range visualization"""
    if not range_visualization:
        return
    
    if visible and is_selected:
        if range_visualization.has_method("show_ranges"):
            range_visualization.show_ranges()
    elif range_visualization.has_method("hide_ranges"):
        range_visualization.hide_ranges()

func set_ai_processing_status(processing: bool) -> void:
    """Set the AI processing status and update visual indicators"""
    waiting_for_ai = processing
    
    # Update status bar to show processing state
    if status_bar and status_bar.has_method("set_ai_processing"):
        status_bar.set_ai_processing(processing)

func _create_damage_indicator(damage_amount: float) -> void:
    """Create a visual indicator showing damage taken"""
    print("DEBUG: Unit %s creating damage indicator for %.1f damage" % [unit_id, damage_amount])
    
    # Create a simple 3D text label for damage feedback
    var label = Label3D.new()
    label.text = "-%.0f" % damage_amount
    label.modulate = Color.RED
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.font_size = 32
    label.position = Vector3(0, 2, 0)  # Above the unit
    add_child(label)
    
    # Animate the damage indicator
    var tween = create_tween()
    tween.parallel().tween_property(label, "position", Vector3(0, 4, 0), 1.0)
    tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
    tween.tween_callback(func(): if is_instance_valid(label): label.queue_free())

func get_attack_capability_debug() -> String:
    """Get debug information about unit's attack capability"""
    var info = []
    info.append("Unit: %s" % unit_id)
    info.append("State: %s" % GameEnums.get_unit_state_string(current_state))
    info.append("Has weapon: %s" % ("yes" if weapon_attachment else "no"))
    if weapon_attachment:
        info.append("Weapon equipped: %s" % ("yes" if weapon_attachment.is_equipped else "no"))
        info.append("Weapon ammo: %d/%d" % [weapon_attachment.current_ammo, weapon_attachment.max_ammo])
        info.append("Can fire: %s" % ("yes" if weapon_attachment.can_fire() else "no"))
    info.append("Attack damage: %.1f" % attack_damage)
    info.append("Attack range: %.1f" % attack_range)
    info.append("Last attack: %.1fs ago" % ((Time.get_ticks_msec() / 1000.0) - last_attack_time))
    return "\n".join(info)