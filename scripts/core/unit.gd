# Unit.gd - Base unit class
class_name Unit
extends CharacterBody3D

# Load shared components
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const UnitStatusBarScene = preload("res://scenes/units/UnitStatusBar.tscn")
const UnitHealthBarScene = preload("res://scenes/units/UnitHealthBar.tscn")
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
var health_bar: Node3D = null
var range_visualization: Node3D = null

# New action state variables
var current_action: Dictionary = {}
var action_complete: bool = true
var _old_action_complete: bool = true # To detect changes
var triggered_actions: Array = []
var trigger_last_states: Dictionary = {}
var step_timer: float = 0.0

# Movement
var navigation_agent: NavigationAgent3D

signal health_changed(new_health: float, max_health: float)
signal unit_died(unit_id: String)

# Static counters for meaningful unit IDs
static var unit_counters: Dictionary = {}

func _ready() -> void:
    if unit_id.is_empty():
        unit_id = _generate_meaningful_unit_id()
    
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
    
    # Create health bar
    _create_health_bar()
    
    # Create range visualization
    _create_range_visualization()
    
    _load_archetype_stats()
    
    # Configure NavigationAgent3D after movement_speed is set
    if navigation_agent:
        navigation_agent.radius = 1.0 # Matches unit's collision shape radius
        navigation_agent.max_speed = movement_speed
        navigation_agent.avoidance_enabled = true # Ensure avoidance is enabled
        # Path postprocessing will use default settings
        # Units are on layer 1 for selection, use this layer for dynamic avoidance
        navigation_agent.set_navigation_layers(1) # Units avoid other units on the same layer

        navigation_agent.velocity_computed.connect(Callable(self, "_on_navigation_velocity_computed"))
    
    health_changed.connect(func(new_health, _max_health): if new_health <= 0: die())

    # Simplified physics initialization - ensure proper ground positioning
    if global_position.y < 1.0:
        global_position.y = 1.0  # Ensure minimum spawn height
    set_physics_process(true)

func _generate_meaningful_unit_id() -> String:
    """Generate a meaningful unit ID like 'tank_t1_01' instead of random numbers"""
    # Use default values if archetype or team_id aren't set yet
    var unit_archetype = archetype if not archetype.is_empty() else "unit"
    var unit_team = team_id if team_id > 0 else 1
    
    # Create key for this archetype-team combination
    var counter_key = "%s_t%d" % [unit_archetype, unit_team]
    
    # Get current counter for this type
    if not unit_counters.has(counter_key):
        unit_counters[counter_key] = 0
    
    # Increment counter
    unit_counters[counter_key] += 1
    
    # Generate meaningful ID: archetype_team_number
    return "%s_%02d" % [counter_key, unit_counters[counter_key]]

func _enable_physics():
    # This function is no longer needed with simplified approach
    set_physics_process(true)

func _load_archetype_stats() -> void:
    # Load from game constants instead of ConfigManager
    var GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
    var config = GameConstants.get_unit_config(archetype)
    if not config.is_empty():
        max_health = config.get("health", 100.0)
        current_health = max_health
        movement_speed = config.get("speed", 5.0)
        attack_damage = config.get("damage", 10.0)
        attack_range = config.get("range", 15.0)
        vision_range = config.get("vision", 30.0)
        
        # Handle medic-specific heal_range, as it uses attack_range for distance checking
        if archetype == "medic":
            attack_range = config.get("heal_range", 15.0)

        # Refresh range visualization with new stats
        call_deferred("refresh_range_visualization")

func _physics_process(delta: float) -> void:
    if is_dead: return

    # NEW: First, check for trigger interruptions. They have the highest priority.
    if _check_triggers():
        return # A trigger fired and set a new action. The new action will be processed next frame.

    # If an action is running, increment its timer
    if not action_complete:
        step_timer += delta

    # Always apply gravity regardless of state
    if not is_on_floor():
        velocity.y += get_gravity().y * delta

    # State machine logic
    match current_state:
        GameEnums.UnitState.MOVING:
            if navigation_agent.is_navigation_finished():
                current_state = GameEnums.UnitState.IDLE
                action_complete = true
        
        GameEnums.UnitState.ATTACKING:
            if not is_instance_valid(target_unit) or target_unit.is_dead:
                print("DEBUG: Unit %s stopping attack - target invalid or dead" % unit_id)
                current_state = GameEnums.UnitState.IDLE
                action_complete = true # The attack action is complete because the target is gone.
            else:
                var distance = global_position.distance_to(target_unit.global_position)
                if distance > attack_range:
                    # Target is out of range, move closer but stay in ATTACKING state.
                    if navigation_agent:
                        navigation_agent.target_position = target_unit.global_position
                else:
                    # Target is in range. Stop moving and attack.
                    if navigation_agent:
                        navigation_agent.target_position = global_position # Stop moving

                    look_at(target_unit.global_position, Vector3.UP)
                    var current_time = Time.get_ticks_msec() / 1000.0
                    if current_time - last_attack_time >= attack_cooldown:
                        print("DEBUG: Unit %s attempting to fire at target %s" % [unit_id, target_unit.unit_id])
                        var attack_successful = false
                        
                        var shot_fired = false
                        # Try weapon attachment first
                        if weapon_attachment and weapon_attachment.has_method("fire"):
                            if weapon_attachment.can_fire():
                                print("DEBUG: Unit %s firing weapon at target %s" % [unit_id, target_unit.unit_id])
                                var fire_result = weapon_attachment.fire()
                                if not fire_result.is_empty():
                                    shot_fired = true
                                    print("DEBUG: Weapon fire result: %s" % str(fire_result))
                            else:
                                # Weapon on cooldown or out of ammo, do nothing this frame.
                                print("DEBUG: Unit %s weapon cannot fire (on cooldown or out of ammo)" % unit_id)
                        else:
                            # No weapon attachment, use fallback direct damage.
                            print("DEBUG: Unit %s using fallback direct damage (no weapon)" % unit_id)
                            target_unit.take_damage(attack_damage)
                            print("DEBUG: Unit %s dealt %f direct damage to %s" % [unit_id, attack_damage, target_unit.unit_id])
                            shot_fired = true
                        
                        if shot_fired:
                            last_attack_time = current_time
                            print("DEBUG: Unit %s attack action successful" % unit_id)
        
        GameEnums.UnitState.HEALING:
            if not is_instance_valid(target_unit) or target_unit.is_dead or target_unit.get_health_percentage() >= 1.0:
                current_state = GameEnums.UnitState.IDLE
                action_complete = true
            else:
                var distance = global_position.distance_to(target_unit.global_position)
                if distance > attack_range: # Use attack_range as heal_range for simplicity
                    navigation_agent.target_position = target_unit.global_position
                else:
                    # In range, perform healing
                    navigation_agent.target_position = global_position # Stop moving
                    look_at(target_unit.global_position, Vector3.UP)
                    if "heal_rate" in self:
                        target_unit.receive_healing(self.get("heal_rate") * delta)
        
        GameEnums.UnitState.CONSTRUCTING, GameEnums.UnitState.REPAIRING:
            if not is_instance_valid(target_building):
                current_state = GameEnums.UnitState.IDLE
                action_complete = true
            else:
                var distance = global_position.distance_to(target_building.global_position)
                if distance > attack_range: # Use attack_range as build_range
                    navigation_agent.target_position = target_building.global_position
                else:
                    navigation_agent.target_position = global_position # Stop moving
                    if target_building.has_method("add_construction_progress"):
                        var build_rate = self.build_rate if "build_rate" in self else 0.1
                        target_building.add_construction_progress(build_rate * delta)
                    if target_building.is_operational:
                        current_state = GameEnums.UnitState.IDLE
                        target_building = null
                        action_complete = true
        
        GameEnums.UnitState.LAYING_MINES:
            # Completion is handled by the EngineerUnit script, which will set action_complete = true
            velocity.x = 0
            velocity.z = 0
    
        _: # Default case for IDLE, FOLLOWING etc.
            if current_state == GameEnums.UnitState.FOLLOWING:
                if not is_instance_valid(follow_target) or follow_target.is_dead:
                    current_state = GameEnums.UnitState.IDLE
                    follow_target = null
                    action_complete = true
                else:
                    var distance_to_follow_target = global_position.distance_to(follow_target.global_position)
                    if distance_to_follow_target > FOLLOW_DISTANCE:
                        navigation_agent.target_position = follow_target.global_position
                    else:
                        navigation_agent.target_position = global_position # Stop

    # Calculate desired velocity for NavigationAgent3D for path following and local avoidance
    if can_move and navigation_agent:
        if not navigation_agent.is_navigation_finished():
            var next_global_path_point = navigation_agent.get_next_path_position()
            var desired_velocity = (next_global_path_point - global_position).normalized() * movement_speed
            navigation_agent.set_velocity(desired_velocity)
        else:
            # If navigation is finished, stop horizontal movement
            velocity.x = 0
            velocity.z = 0
            if current_state == GameEnums.UnitState.MOVING: # Only if explicitly moving to a point
                current_state = GameEnums.UnitState.IDLE # Return to idle once path is finished
                action_complete = true # Also signal completion
    else:
        # If can_move is false or no navigation agent, ensure no horizontal movement from pathfinding
        velocity.x = 0
        velocity.z = 0

    # Rotate the unit to face its movement direction.
    # This is skipped if horizontal velocity is zero (e.g., when attacking in range and stopped).
    var horizontal_velocity = velocity
    horizontal_velocity.y = 0
    if horizontal_velocity.length_squared() > 0.01:
        var new_transform = transform.looking_at(global_position + horizontal_velocity, Vector3.UP)
        transform.basis = transform.basis.slerp(new_transform.basis, delta * 10.0)

    # Always call move_and_slide to apply physics and update velocity
    move_and_slide()

    # Check if the unit just finished an action
    if not _old_action_complete and action_complete:
        # The action has just been completed on this frame.
        # Check if this unit has a sequential plan.
        var plan_executor = get_node("/root/DependencyContainer").get_node_or_null("PlanExecutor")
        if plan_executor and not plan_executor.active_plans.has(unit_id):
            # This unit just finished an action (must have been a triggered one)
            # and it does not have a sequential plan waiting. It is now truly idle.
            # We need to tell the system to consider giving it a new plan.
            plan_executor.unit_became_idle.emit(unit_id)
            
    _old_action_complete = action_complete

# New function to receive velocity computed by NavigationAgent3D (including RVO avoidance)
func _on_navigation_velocity_computed(safe_velocity: Vector3) -> void:
    # This is the velocity adjusted by NavigationAgent3D for local avoidance.
    # Apply it to the unit's horizontal velocity component.
    velocity.x = safe_velocity.x
    velocity.z = safe_velocity.z

func move_to(target_position: Vector3) -> void:
    current_state = GameEnums.UnitState.MOVING
    if navigation_agent:
        navigation_agent.target_position = target_position
        # Provide an initial desired velocity to the agent when setting a new target
        var desired_initial_velocity = (target_position - global_position).normalized() * movement_speed
        navigation_agent.set_velocity(desired_initial_velocity)

func attack_target(target: Unit) -> void:
    if not is_instance_valid(target): 
        print("DEBUG: Unit %s received invalid attack target" % unit_id)
        return
    print("DEBUG: Unit %s setting attack target to %s" % [unit_id, target.unit_id])
    target_unit = target
    follow_target = null
    current_state = GameEnums.UnitState.ATTACKING
    # When attacking, clear NavigationAgent's target unless the attack requires movement
    if navigation_agent:
        navigation_agent.target_position = global_position # Stop pathfinding if currently moving to a general point

func follow(target: Unit) -> void:
    if not is_instance_valid(target) or target == self:
        return
    current_state = GameEnums.UnitState.FOLLOWING
    follow_target = target
    target_unit = null # Clear attack target
    # NavigationAgent's target will be updated continuously in _physics_process
    # if it's following (currently, it updates target_position in _physics_process for FOLLOWING state).

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
    
    # Trigger death animation sequence if this is an animated unit
    if has_method("trigger_death_sequence"):
        call("trigger_death_sequence")
    
    # The unit now persists after death. Its 'is_dead' state is broadcast
    # to clients, and it will be ignored by most game logic.

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
func retreat():
    # Implement unit retreat logic here
    if navigation_agent:
        # For a simple retreat, move to a safe, pre-defined position or away from enemies
        var safe_pos = global_position + (global_position - target_unit.global_position).normalized() * 30.0 if is_instance_valid(target_unit) else global_position + Vector3(randf_range(-1,1),0,randf_range(-1,1)) * 30.0
        move_to(safe_pos)
    current_state = GameEnums.UnitState.IDLE # Or GameEnums.UnitState.RETREATING if defined
    print("%s is retreating." % unit_id)

func start_patrol(_waypoints):
    # Implement unit patrol logic here
    current_state = GameEnums.UnitState.IDLE # Or GameEnums.UnitState.PATROLING
    print("%s is starting patrol." % unit_id)

func set_formation(_formation):
    # Implement formation logic here
    print("%s is setting formation." % unit_id)

func set_stance(_stance):
    # Implement stance logic here
    print("%s is setting stance." % unit_id)

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

func _create_health_bar() -> void:
    """Create and attach the health bar to this unit"""
    if health_bar:
        return  # Already has a health bar
    
    health_bar = UnitHealthBarScene.instantiate()
    add_child(health_bar)

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

func set_health_bar_visibility(visible: bool) -> void:
    """Set the visibility of the health bar"""
    if health_bar and health_bar.has_method("set_visibility"):
        health_bar.set_visibility(visible)

func set_health_bar_hide_when_full(hide: bool) -> void:
    """Set whether health bar should hide when unit is at full health"""
    if health_bar and health_bar.has_method("set_hide_when_full"):
        health_bar.set_hide_when_full(hide)

func refresh_health_display() -> void:
    """Force refresh the health bar display"""
    if health_bar:
        health_changed.emit(current_health, max_health)

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

# --- New Action & Trigger System ---

func set_current_action(action: Dictionary):
    current_action = action
    action_complete = false
    step_timer = 0.0
    _execute_action(action)

func set_triggered_actions(actions: Array):
    triggered_actions = actions
    trigger_last_states.clear()

func _execute_action(step: Dictionary):
    var action = step.get("action")
    var params = step.get("params", {})
    if params == null: params = {}
    params = params.duplicate()

    if params.has("trigger_context"):
        var trigger_context = params.get("trigger_context", {})
        for key in trigger_context:
            if not params.has(key):
                params[key] = trigger_context[key]
    
    match action:
        "move_to":
            if params.has("position") and params.position != null:
                var pos_arr = params.position
                var relative_pos = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
                var team_transform = _get_team_transform()
                var world_pos = team_transform * relative_pos
                move_to(world_pos)
        "attack":
            if params.has("target_id") and params.target_id != null:
                var game_state = get_node("/root/DependencyContainer").get_game_state()
                var target = game_state.units.get(params.target_id)
                attack_target(target)
        "retreat":
            retreat()
        "patrol":
            current_state = GameEnums.UnitState.MOVING # Patrol is essentially moving
            action_complete = true # Patrol is conceptual, for AI; for execution it's just a move. The AI can issue another patrol if it wants. Or we can implement it as a sequence of moves. For now, it's a single action.
        "follow":
            if params.has("target_id") and params.target_id != null:
                var target = get_node("/root/DependencyContainer").get_game_state().units.get(params.target_id)
                follow(target)
        "activate_stealth":
            if has_method("activate_stealth"): activate_stealth(params)
        "activate_shield":
            if has_method("activate_shield"): activate_shield(params)
        "taunt_enemies":
            if has_method("taunt_enemies"): taunt_enemies(params)
        "charge_shot":
            if has_method("charge_shot"): charge_shot(params)
        "find_cover":
            if has_method("find_cover"): find_cover(params)
        "heal_target":
            if has_method("heal_target"): heal_target(params)
        "construct":
            if has_method("construct"): construct(params)
        "repair":
            if has_method("repair"): repair(params)
        "lay_mines":
            if has_method("lay_mines"): lay_mines(params)
        "idle":
            current_state = GameEnums.UnitState.IDLE
            action_complete = true
        _:
            action_complete = true # Unknown action, complete immediately

func _check_triggers() -> bool:
    if triggered_actions.is_empty():
        return false

    var context = get_node("/root/DependencyContainer").get_game_state().get_context_for_ai(self)
    
    for triggered_action in triggered_actions:
        var source = triggered_action.get("trigger_source")
        var comparison = triggered_action.get("trigger_comparison")
        var value = triggered_action.get("trigger_value")
        var trigger_description = "%s %s %s" % [source, comparison, str(value)]

        var trigger_result = _evaluate_structured_trigger(source, comparison, value, context)
        var current_trigger_state = trigger_result.result
        var last_trigger_state = trigger_last_states.get(trigger_description, false)
        
        trigger_last_states[trigger_description] = current_trigger_state
            
        # Fire on rising edge
        if current_trigger_state and not last_trigger_state:
            push_warning("Unit %s: Trigger '%s' fired. Interrupting current action." % [unit_id, trigger_description])

            # Interrupt current plan execution by notifying the executor
            var plan_executor = get_node("/root/DependencyContainer").get_node_or_null("PlanExecutor")
            if plan_executor:
                plan_executor.interrupt_plan(unit_id, "Trigger fired: %s" % trigger_description, true)

            # Execute the triggered action immediately
            var action_to_execute = triggered_action.duplicate()
            action_to_execute.params["trigger_context"] = trigger_result.context
            
            call_deferred("set_current_action", action_to_execute)
            
            # Let the UI know
            if plan_executor:
                plan_executor.trigger_evaluated.emit(unit_id, trigger_description, true)
            
            return true
            
    return false

func _evaluate_structured_trigger(source: String, comparison: String, value: Variant, unit_context: Dictionary) -> Dictionary:
    var metric_result = _get_metric_value(source, unit_context)
    var metric_context = {}
    var current_value
    
    if metric_result is Dictionary:
        if metric_result.has("result"):
            current_value = metric_result.result
            metric_context = metric_result.get("context", {})
        elif metric_result.has("value"):
            current_value = metric_result.value
            metric_context = metric_result.get("context", {})
        else:
            current_value = metric_result
    else:
        current_value = metric_result
    
    var comparison_value = value
    if value is String:
        if value == "true": comparison_value = true
        elif value == "false": comparison_value = false
        elif value.is_valid_float(): comparison_value = float(value)
        elif value.is_valid_int(): comparison_value = int(value)
    
    var comparison_result = false
    
    if comparison in ["<", "<=", ">", ">="]:
        if not (current_value is float or current_value is int) or not (comparison_value is float or comparison_value is int):
            return {"result": false, "context": {}}
    
    match comparison:
        "=", "==": comparison_result = current_value == comparison_value
        "!=": comparison_result = current_value != comparison_value
        "<": comparison_result = current_value < comparison_value
        "<=": comparison_result = current_value <= comparison_value
        ">": comparison_result = current_value > comparison_value
        ">=": comparison_result = current_value >= comparison_value
        _:
            return {"result": false, "context": {}}
            
    if comparison_result:
        return {"result": true, "context": metric_context}
    else:
        return {"result": false, "context": {}}

func _get_metric_value(metric: String, unit_context: Dictionary) -> Variant:
    match metric:
        "elapsed_ms":
            return step_timer * 1000.0
        "health_pct":
            return get_health_percentage() * 100.0
        "ammo_pct":
            return (float(ammo) / max_ammo) * 100.0 if max_ammo > 0 else 0.0
        "morale":
            return morale
        "incoming_fire_count":
            var attackers = unit_context.get("unit_state", {}).get("attackers", [])
            return attackers.size() if attackers is Array else 0
        "target_health_pct":
            if is_instance_valid(target_unit):
                return target_unit.get_health_percentage() * 100.0
            return 0.0
        "enemies_in_range":
            var enemies = unit_context.get("sensor_data", {}).get("visible_enemies", [])
            var count = 0
            var closest_enemy_id = ""
            for enemy in enemies:
                if enemy.get("dist", 9999.0) <= attack_range:
                    count += 1
                    if closest_enemy_id.is_empty():
                        closest_enemy_id = enemy.get("id", "")
            if count > 0:
                return {"value": count, "context": {"target_id": closest_enemy_id}}
            else:
                return {"value": 0, "context": {}}
        "enemy_dist":
            var enemies = unit_context.get("sensor_data", {}).get("visible_enemies", [])
            if enemies.is_empty():
                return {"value": 9999.0, "context": {}}
            var closest_enemy = enemies[0]
            var dist_value = closest_enemy.get("dist", 9999.0)
            return {"value": float(dist_value), "context": {"target_id": closest_enemy.get("id", "")}}
        "ally_health_pct":
            var allies = unit_context.get("sensor_data", {}).get("visible_allies", [])
            var lowest_health_ally = null
            var lowest_health_pct = 100.0
            for ally in allies:
                if ally.health_pct < lowest_health_pct:
                    lowest_health_ally = ally
                    lowest_health_pct = ally.health_pct
            if lowest_health_ally:
                return {"value": lowest_health_pct, "context": {"target_id": lowest_health_ally.id}}
            return {"value": 100.0, "context": {}}
        "nearby_enemies":
            var enemies = unit_context.get("sensor_data", {}).get("visible_enemies", [])
            return enemies.size() if enemies is Array else 0
        "move_speed":
            return velocity.length()
        _:
            return null

func _get_team_transform() -> Transform3D:
    var home_base_manager = get_tree().get_first_node_in_group("home_base_managers")
    if not home_base_manager:
        push_error("HomeBaseManager not found!")
        return Transform3D.IDENTITY

    var my_base_pos = home_base_manager.get_home_base_position(team_id)
    var enemy_team_id = 2 if team_id == 1 else 1
    var enemy_base_pos = home_base_manager.get_home_base_position(enemy_team_id)

    if my_base_pos == Vector3.ZERO or enemy_base_pos == Vector3.ZERO:
        push_error("Home base positions not set up correctly.")
        return Transform3D.IDENTITY
        
    var forward_vec = (enemy_base_pos - my_base_pos).normalized()
    var right_vec = forward_vec.cross(Vector3.UP).normalized()
    var up_vec = right_vec.cross(forward_vec).normalized()

    return Transform3D(right_vec, up_vec, forward_vec, my_base_pos)

# Stub methods for archetype-specific abilities (overridden in subclasses)
func activate_stealth(_params: Dictionary): pass
func activate_shield(_params: Dictionary): pass  
func taunt_enemies(_params: Dictionary): pass
func charge_shot(_params: Dictionary): pass
func find_cover(_params: Dictionary): pass
func heal_target(_params: Dictionary): pass
func construct(_params: Dictionary): pass
func repair(_params: Dictionary): pass
func lay_mines(_params: Dictionary): pass