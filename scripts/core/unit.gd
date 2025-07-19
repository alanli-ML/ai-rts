# Unit.gd - Base unit class
class_name Unit
extends CharacterBody3D

# Load shared components
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const UnitStatusBarScene = preload("res://scenes/units/UnitStatusBar.tscn")
const UnitHealthBarScene = preload("res://scenes/units/UnitHealthBar.tscn")
const UnitRangeVisualizationScene = preload("res://scenes/units/UnitRangeVisualization.tscn")
const ActionValidator = preload("res://scripts/ai/action_validator.gd")

const KITING_DISTANCE_BUFFER: float = 2.0

const TRIGGER_PRIORITIES = {
    "on_health_critical": 5,
    "on_under_attack": 4,
    "on_enemy_in_range": 3,
    "on_enemy_sighted": 2,
    "on_health_low": 1,
 
    "on_ally_health_low": 1
}

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
var _last_damage_time: float = 0.0
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

# Respawn system
var is_respawning: bool = false
var respawn_timer: float = 0.0
var original_spawn_position: Vector3 = Vector3.ZERO
var invulnerable: bool = false
var invulnerability_timer: float = 0.0

# New action state variables
var current_action: Dictionary = {} # For legacy actions, will be phased out
var action_complete: bool = true
var _old_action_complete: bool = true # To detect changes
var step_timer: float = 0.0  # Timer for current action step
var current_action_trigger: String = ""  # Current trigger being processed

# --- New Behavior Engine Properties ---
var behavior_matrix: Dictionary = {}
var control_point_attack_sequence: Array = []
var current_attack_sequence_index: int = 0
var current_reactive_state: String = "defend" # Default state
var behavior_start_delay: float = 0.1 # Reduced from 2.0 - quick start for UI feedback
var _behavior_timer: float = 0.0
var last_action_scores: Dictionary = {} # For debugging and UI
var last_state_variables: Dictionary = {} # For debugging and UI
const REACTIVE_BEHAVIOR_THRESHOLD: float = 0.1 # Min activation to consider a state change
const INDEPENDENT_ACTION_THRESHOLD: float = 0.6 # Min activation to fire an ability

# Movement
var navigation_agent: NavigationAgent3D

# Map boundaries (prevent units from falling off the edge)
const MAP_BOUNDS = {
    "min_x": -45.0,
    "max_x": 45.0,
    "min_z": -45.0,
    "max_z": 45.0
}

signal health_changed(new_health: float, max_health: float)
signal unit_died(unit_id: String)
signal unit_respawned(unit_id: String)

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
    
    # Set collision mask to include buildings and terrain for navigation
    set_collision_mask_value(1, false)   # Collide with other units for avoidance
    set_collision_mask_value(2, true)   # Collide with buildings for pathfinding
    set_collision_mask_value(3, true)   # Collide with terrain/static objects
    
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
    
    # Initialize with a default behavior matrix.
    # This will be overwritten when a plan is received from the AI.
    behavior_matrix = _get_default_behavior_matrix()
    
    # Also set default triggered actions for immediate UI feedback
    if behavior_matrix.is_empty():
        print("DEBUG: Unit %s - default behavior matrix is empty, calling _set_default_triggered_actions" % unit_id)
        _set_default_triggered_actions()
    else:
        print("DEBUG: Unit %s - initialized with default behavior matrix, %d actions (server: %s)" % [unit_id, behavior_matrix.size(), multiplayer.is_server()])
    
    # Start behavior processing immediately for UI feedback (server only)
    if multiplayer.is_server():
        _behavior_timer = behavior_start_delay
        print("DEBUG: Unit %s - server-side behavior engine enabled" % unit_id)
    else:
        print("DEBUG: Unit %s - client-side unit, behavior engine disabled (will display server data)" % unit_id)
    
    # Configure NavigationAgent3D after movement_speed is set
    if navigation_agent:
        navigation_agent.radius = 1.2 # Match the navigation mesh agent radius
        navigation_agent.max_speed = movement_speed
        navigation_agent.avoidance_enabled = true # Ensure avoidance is enabled
        navigation_agent.neighbor_distance = 6.0 # Reduced search radius to avoid premature slowdown
        navigation_agent.time_horizon = 2.0 # Reduced planning time for more responsive movement
        navigation_agent.path_postprocessing = NavigationPathQueryParameters3D.PATH_POSTPROCESSING_EDGECENTERED
        navigation_agent.path_metadata_flags = NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_ALL
        # CRITICAL: Use default layer (1) for navigation - keep NavigationAgent3D on layer 1
        # NavigationObstacle3D will work automatically with navigation mesh rebaking
        navigation_agent.set_navigation_layers(1)
        
        # Improve pathfinding behavior around obstacles
        navigation_agent.path_desired_distance = 1.0  # Stay closer to the path
        navigation_agent.target_desired_distance = 1.5  # Get closer to target before stopping
        
        # CRITICAL: Wait for navigation map to be ready and link to NavigationRegion3D
        call_deferred("_setup_navigation_agent")

        navigation_agent.velocity_computed.connect(Callable(self, "_on_navigation_velocity_computed"))
    
    health_changed.connect(func(new_health, _max_health): if new_health <= 0: die())

    # Simplified physics initialization - ensure proper ground positioning
    if global_position.y < 1.0:
        global_position.y = 1.0  # Ensure minimum spawn height
    
    # Store original spawn position for respawning
    original_spawn_position = global_position
    
    # CRITICAL FIX: Set initial facing direction toward enemy base
    # This ensures newly spawned units face the correct direction from the start
    call_deferred("_set_initial_facing_direction")
    
    set_physics_process(true)

func _setup_navigation_agent() -> void:
    """Set up NavigationAgent3D to properly use the navigation mesh"""
    if not navigation_agent:
        return
        
    # Find the NavigationRegion3D in the scene
    var nav_region = get_tree().get_first_node_in_group("navigation_regions")
    if not nav_region:
        print("DEBUG: Unit %s - No NavigationRegion3D found, navigation may not work" % unit_id)
        return
    
    # Get the navigation map from the NavigationRegion3D
    var nav_map = nav_region.get_navigation_map()
    if nav_map.is_valid():
        # Link the NavigationAgent3D to the navigation map
        navigation_agent.set_navigation_map(nav_map)
        print("DEBUG: Unit %s - NavigationAgent3D linked to navigation map" % unit_id)
    else:
        print("DEBUG: Unit %s - Invalid navigation map, agent may not work properly" % unit_id)

func _set_initial_facing_direction() -> void:
    """Set the unit's facing direction toward the enemy base (used for both initial spawn and respawn)"""
    # Only run on server to maintain server-authoritative transforms
    if not multiplayer.is_server():
        return
        
    var home_base_manager = get_tree().get_first_node_in_group("home_base_managers")
    if home_base_manager:
        var my_base_pos = home_base_manager.get_home_base_position(team_id)
        var enemy_team_id = 2 if team_id == 1 else 1
        var enemy_base_pos = home_base_manager.get_home_base_position(enemy_team_id)
        
        if my_base_pos != Vector3.ZERO and enemy_base_pos != Vector3.ZERO:
            # Calculate direction toward enemy base
            var forward_direction = (enemy_base_pos - my_base_pos).normalized()
            
            # Set transform to face the enemy base
            # This ensures units face the correct direction when they start moving
            transform.basis = Basis.looking_at(forward_direction, Vector3.UP)
            
            print("DEBUG: Unit %s initial facing direction set toward enemy base" % unit_id)
        else:
            print("DEBUG: Unit %s could not determine home base positions for initial facing direction" % unit_id)
    else:
        print("DEBUG: Unit %s home base manager not found for initial facing direction" % unit_id)

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

func _set_default_triggered_actions() -> void:
    """Set default behavior matrix from game constants based on unit archetype"""
    var default_matrix = GameConstants.get_default_behavior_matrix(archetype)
    if not default_matrix.is_empty():
        behavior_matrix = default_matrix.duplicate()
        print("DEBUG: Unit %s (%s): Set default behavior matrix with actions: %s" % [unit_id, archetype, str(behavior_matrix.keys())])
    else:
        print("DEBUG: Unit %s (%s): No default behavior matrix found for archetype, using fallback" % [unit_id, archetype])
        # Use the internal _get_default_behavior_matrix as fallback
        behavior_matrix = _get_default_behavior_matrix()
        if not behavior_matrix.is_empty():
            print("DEBUG: Unit %s (%s): Used internal fallback matrix with %d actions" % [unit_id, archetype, behavior_matrix.size()])

func _physics_process(delta: float) -> void:
    # Handle respawn timer
    if is_dead and is_respawning:
        var old_timer = respawn_timer
        respawn_timer -= delta
        
        # Debug respawn countdown every 5 seconds (using cleaner logic)
        var old_seconds = int(old_timer)
        var new_seconds = int(respawn_timer)
        if old_seconds != new_seconds and new_seconds > 0 and new_seconds % 5 == 0:
            print("DEBUG: Unit %s respawn countdown: %d seconds remaining" % [unit_id, new_seconds])
        
        if respawn_timer <= 0.0:
            print("DEBUG: Unit %s respawn timer expired, calling _handle_respawn()" % unit_id)
            _handle_respawn()
        return
    
    # Skip processing if dead but not respawning yet
    if is_dead: 
        # Debug why respawn isn't starting
        if not is_respawning:
            print("DEBUG: Unit %s is dead but not respawning (is_respawning=false)" % unit_id)
        return
    
    # Handle invulnerability after respawn
    if invulnerable:
        invulnerability_timer -= delta
        if invulnerability_timer <= 0.0:
            invulnerable = false
            print("DEBUG: Unit %s is no longer invulnerable" % unit_id)

    # If an action is running, increment its timer
    if not action_complete:
        step_timer += delta

    # Always apply gravity regardless of state
    if not is_on_floor():
        velocity.y += get_gravity().y * delta

    # --- New Behavior Engine Loop ---
    _evaluate_reactive_behavior()
    _execute_current_state(delta)
    # --- End New Behavior Engine Loop ---

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
    else:
        # If can_move is false or no navigation agent, ensure no horizontal movement from pathfinding
        velocity.x = 0
        velocity.z = 0

    # Rotate the unit to face its movement direction or its target.
    var look_at_position: Vector3
    var should_look = false

    # Priority 1: If in an attack or retreat state with a valid target, always look at the target.
    if (current_reactive_state == "attack" or current_reactive_state == "retreat") and is_instance_valid(target_unit):
        var direction_to_target = (target_unit.global_position - global_position)
        direction_to_target.y = 0 # Don't tilt up/down
        if direction_to_target.length_squared() > 0.01:
            look_at_position = global_position + direction_to_target
            should_look = true
    # Priority 2: If navigating, look toward the next navigation waypoint
    elif can_move and navigation_agent and not navigation_agent.is_navigation_finished():
        var next_point = navigation_agent.get_next_path_position()
        var direction_to_next = (next_point - global_position)
        direction_to_next.y = 0 # Don't tilt up/down
        if direction_to_next.length_squared() > 0.25: # Only rotate if waypoint is far enough
            look_at_position = global_position + direction_to_next
            should_look = true
    # Priority 3: If not navigating but moving, look in the direction of movement.
    elif velocity.length_squared() > 0.01:
        var horizontal_velocity = velocity
        horizontal_velocity.y = 0
        if horizontal_velocity.length_squared() > 0.01:
            look_at_position = global_position + horizontal_velocity
            should_look = true
    
    if should_look:
        var new_transform = transform.looking_at(look_at_position, Vector3.UP)
        # Slower rotation for smoother navigation around obstacles
        transform.basis = transform.basis.slerp(new_transform.basis, delta * 5.0)

    # Always call move_and_slide to apply physics and update velocity
    move_and_slide()

# New function to receive velocity computed by NavigationAgent3D (including RVO avoidance)
func _on_navigation_velocity_computed(safe_velocity: Vector3) -> void:
    # This is the velocity adjusted by NavigationAgent3D for local avoidance.
    # Apply it to the unit's horizontal velocity component.
    velocity.x = safe_velocity.x
    velocity.z = safe_velocity.z

func move_to(target_position: Vector3) -> void:
    current_state = GameEnums.UnitState.MOVING
    if navigation_agent:
        # Wait for navigation map to be ready before setting target
        await get_tree().physics_frame
        
        # Clamp target position to map boundaries
        var clamped_position = _clamp_to_map_bounds(target_position)
        navigation_agent.target_position = clamped_position
        
        print("DEBUG: Unit %s moving from %s to %s" % [unit_id, global_position, clamped_position])
        
        # Provide an initial desired velocity to the agent when setting a new target
        var desired_initial_velocity = (clamped_position - global_position).normalized() * movement_speed
        navigation_agent.set_velocity(desired_initial_velocity)
        
        # Debug: Check if a path was found
        call_deferred("_debug_navigation_path")

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
    
    # Check for invulnerability after respawn
    if invulnerable:
        print("DEBUG: Unit %s is invulnerable, no damage taken" % unit_id)
        return

    _last_damage_time = Time.get_ticks_msec() / 1000.0
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
    
    print("DEBUG: Unit %s die() called - is_dead set to true" % unit_id)
    
    # Trigger death animation sequence if this is an animated unit
    if has_method("trigger_death_sequence"):
        print("DEBUG: Unit %s calling trigger_death_sequence()" % unit_id)
        call("trigger_death_sequence")
    else:
        print("DEBUG: Unit %s does not have trigger_death_sequence() method" % unit_id)
    
    # Start respawn timer (only on server)
    if multiplayer.is_server():
        _start_respawn_timer()
    
    # The unit now persists after death. Its 'is_dead' state is broadcast
    # to clients, and it will be ignored by most game logic.

func get_health_percentage() -> float:
    return current_health / max_health if max_health > 0 else 0.0

func get_team_id() -> int:
    return team_id

func get_current_active_triggers() -> Array:
    # OBSOLETE: This is now handled by the behavior matrix activations.
    return []

func get_all_trigger_info() -> Dictionary:
    # OBSOLETE: This is now handled by the behavior matrix activations.
    return {}

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

# --- New Behavior Engine Implementation ---

func set_behavior_plan(matrix: Dictionary, sequence: Array):
    """Called by the PlanExecutor to set the unit's personality and goals."""
    self.behavior_matrix = matrix
    self.control_point_attack_sequence = sequence
    self.current_attack_sequence_index = 0
    print("Unit %s received new behavior plan." % unit_id)

func _evaluate_reactive_behavior() -> void:
    """The main 'brain' function for the unit, called every physics frame."""
    # CRITICAL: Only run behavior calculations on the server
    # Client units should display server-calculated activation data only
    if not multiplayer.is_server():
        return
    
    if behavior_matrix.is_empty():
        #print("DEBUG: Unit %s - behavior matrix is empty, cannot evaluate" % unit_id)
        return
    
    if _behavior_timer < behavior_start_delay:
        return

    var state_vars = _gather_state_variables()
    if state_vars.is_empty():
        #print("DEBUG: Unit %s - state variables empty, using fallback basic state" % unit_id)
        # Fallback to basic state variables for UI display
        state_vars = _get_fallback_state_variables()
        
    var activation_levels = _calculate_activation_levels(state_vars)
    
    # For debugging and UI - always store these for display
    last_state_variables = state_vars
    last_action_scores = activation_levels
    
    # Only execute actions if we have valid state
    if not state_vars.is_empty():
        _decide_and_execute_actions(activation_levels)
    
    # Debug output every few seconds
    if int(Time.get_ticks_msec() / 1000.0) % 5 == 0 and activation_levels.size() > 0:
        var top_action = ""
        var max_score = -999.0
        for action in activation_levels:
            if activation_levels[action] > max_score:
                max_score = activation_levels[action]
                top_action = action
        #if not top_action.is_empty():
        #    print("DEBUG: SERVER Unit %s top activation: %s (%.2f) - will sync to clients" % [unit_id, top_action, max_score])

func _gather_state_variables() -> Dictionary:
    """Collects real-time data about the unit's environment and normalizes it."""
    var state = {}
    
    # Try to get dependencies from DependencyContainer
    var dependency_container = get_node_or_null("/root/DependencyContainer")
    if not dependency_container:
        return {}
    
    var game_state = dependency_container.get_game_state()
    var node_system = dependency_container.get_node_capture_system()
    
    if not game_state:
        return {}
        
    if not node_system:
        return {}

    # Get nearby units
    var enemies = game_state.get_units_in_radius(global_position, attack_range, team_id)
    var allies = game_state.get_units_in_radius(global_position, vision_range, -1, team_id)
    
    state["enemies_in_range"] = clamp(float(enemies.size()) / 5.0, 0.0, 1.0) # Normalize by typical squad size
    state["current_health"] = get_health_percentage()
    state["under_attack"] = 1.0 if (Time.get_ticks_msec() / 1000.0 - _last_damage_time < 1.5) else 0.0
    state["allies_in_range"] = clamp(float(allies.size()) / 5.0, 0.0, 1.0)
    
    var max_ally_missing_health = 0.0
    for ally in allies:
        if is_instance_valid(ally) and not ally.is_dead:
            var missing_health = 1.0 - ally.get_health_percentage()
            max_ally_missing_health = max(max_ally_missing_health, missing_health)
    state["ally_low_health"] = max_ally_missing_health
    
    var node_counts = node_system.get_team_control_counts()
    var total_nodes = float(node_system.control_points.size())
    if total_nodes > 0:
        state["ally_nodes_controlled"] = node_counts.get(team_id, 0) / total_nodes
        var enemy_team_id = 2 if team_id == 1 else 1
        state["enemy_nodes_controlled"] = node_counts.get(enemy_team_id, 0) / total_nodes
    else:
        state["ally_nodes_controlled"] = 0.0
        state["enemy_nodes_controlled"] = 0.0
        
    state["bias"] = 1.0 # Constant bias term
    
    return state

func _calculate_activation_levels(state_vars: Dictionary) -> Dictionary:
    """Calculates the activation level for each possible action using the behavior matrix."""
    var activations = {}
    if behavior_matrix.is_empty(): return activations

    for action_name in behavior_matrix:
        var weights = behavior_matrix[action_name]
        var score = 0.0
        for var_name in state_vars:
            score += state_vars[var_name] * weights.get(var_name, 0.0)
        activations[action_name] = score # Raw score, can be > 1 or < -1
    return activations

func _decide_and_execute_actions(activations: Dictionary) -> void:
    """Decides which actions to take based on activation levels."""
    if activations.is_empty(): return
        
    # --- 1. Process Independent Ability Actions ---
    var validator = ActionValidator.new()
    var valid_actions = validator.get_valid_actions_for_archetype(archetype)
    
    var independent_actions = validator.INDEPENDENT_REACTIVE_ACTIONS
    for action_name in independent_actions:
        # Only consider actions valid for this archetype
        if action_name not in valid_actions:
            continue
            
        if activations.get(action_name, 0.0) > INDEPENDENT_ACTION_THRESHOLD:
            # Check if we can execute this ability (e.g., not on cooldown)
            if has_method(action_name):
                # Abilities are context-sensitive, so we need to find a target if required
                var params = _get_context_for_action(action_name)
                call(action_name, params)

    # --- 2. Process Mutually Exclusive State Actions ---
    var exclusive_actions = validator.MUTUALLY_EXCLUSIVE_REACTIVE_ACTIONS
    var best_action = ""
    var max_score = -INF

    for action_name in exclusive_actions:
        # Only consider actions valid for this archetype
        if action_name not in valid_actions:
            continue
            
        var score = activations.get(action_name, 0.0)
        if score > max_score:
            max_score = score
            best_action = action_name
    
    # Only switch state if the best action is above threshold and is different from the current one
    if max_score > REACTIVE_BEHAVIOR_THRESHOLD and best_action != current_reactive_state:
        current_reactive_state = best_action
        
        # If we switch to attack, reset the sequence index
        if best_action == "attack":
            current_attack_sequence_index = 0

func _execute_attack_state():
    var game_state = get_node("/root/DependencyContainer").get_game_state()
    if not game_state: return

    # 1. Target Acquisition (in vision range)
    var enemies_in_vision = game_state.get_units_in_radius(global_position, vision_range, team_id)
    var current_target = _get_closest_valid_enemy(enemies_in_vision)
    target_unit = current_target # Update the unit's main target

    if not is_instance_valid(current_target):
        # 2. No enemies in vision: Move to objective
        _move_to_next_objective()
        return

    # 3. Enemies found: Engage
    var distance_to_target = global_position.distance_to(current_target.global_position)
    var my_range = self.attack_range
    var target_range = current_target.attack_range

    # 4. Movement Decision
    if my_range > target_range:
        # Kiting Logic: try to maintain an optimal distance.
        var safe_distance = target_range + KITING_DISTANCE_BUFFER
        # The "sweet spot" is halfway between the edge of the enemy's range and our max range.
        var sweet_spot_distance = (safe_distance + my_range) / 2.0
        var tolerance = 1.0 # A 1-meter tolerance band to prevent jittering.

        # Only adjust position if we are outside the tolerance band around the sweet spot.
        if abs(distance_to_target - sweet_spot_distance) > tolerance:
            # Calculate the ideal position at the sweet spot distance from the enemy.
            var direction_from_enemy = (global_position - current_target.global_position).normalized()
            # If direction is zero (somehow on top of target), create a fallback direction
            if direction_from_enemy.length_squared() < 0.01:
                direction_from_enemy = Vector3.FORWARD
            navigation_agent.target_position = current_target.global_position + direction_from_enemy * sweet_spot_distance
        else:
            # We are in the sweet spot, stop moving to fire.
            navigation_agent.target_position = global_position
    else:
        # Standard Engagement
        if distance_to_target > my_range:
            # Out of range, move closer
            navigation_agent.target_position = current_target.global_position
        else:
            # In range, stop moving
            navigation_agent.target_position = global_position
    
    # 5. Execute Attack
    _attempt_attack_target(current_target)

func _move_to_next_objective():
    var node_system = get_node("/root/DependencyContainer").get_node_capture_system()
    if not node_system: return
    
    var target_node = null
    
    # Try to get next node from sequence
    if not control_point_attack_sequence.is_empty() and current_attack_sequence_index < control_point_attack_sequence.size():
        var target_node_id = control_point_attack_sequence[current_attack_sequence_index]
        target_node = node_system.get_control_point_by_id(target_node_id)
        
        # Check if this node is already controlled by our team
        if is_instance_valid(target_node) and target_node.has_method("get_controlling_team"):
            if target_node.get_controlling_team() == team_id:
                # Node already controlled, advance to next
                current_attack_sequence_index += 1
                target_node = null # Invalidate to find a new one
    
    # If no valid target from sequence, find nearest uncontrolled node
    if not is_instance_valid(target_node):
        target_node = _find_nearest_uncontrolled_node(node_system)
    
    if is_instance_valid(target_node):
        navigation_agent.target_position = _clamp_to_map_bounds(target_node.global_position)
        # Check if we're close enough to the target
        if global_position.distance_to(target_node.global_position) < 5.0:
            # If this was from the sequence, advance to next
            if not control_point_attack_sequence.is_empty() and current_attack_sequence_index < control_point_attack_sequence.size():
                current_attack_sequence_index += 1
    else:
        # No uncontrolled nodes found, act like defend
        _execute_defend_state()

func _execute_retreat_state():
    var game_state = get_node("/root/DependencyContainer").get_game_state()
    if not game_state: return

    # 1. Maintain Retreat Movement
    var enemies_in_vision = game_state.get_units_in_radius(global_position, vision_range, team_id)
    if not enemies_in_vision.is_empty():
        # Move away from the average position of enemies
        var avg_enemy_pos = Vector3.ZERO
        for enemy in enemies_in_vision:
            avg_enemy_pos += enemy.global_position
        avg_enemy_pos /= enemies_in_vision.size()
        
        var retreat_direction = (global_position - avg_enemy_pos).normalized()
        var retreat_position = global_position + retreat_direction * 20.0
        navigation_agent.target_position = _clamp_to_map_bounds(retreat_position)
    else:
        # No enemies nearby, move towards home base
        var home_base_manager = get_tree().get_first_node_in_group("home_base_managers")
        if home_base_manager:
            var home_position = home_base_manager.get_home_base_position(team_id)
            navigation_agent.target_position = _clamp_to_map_bounds(home_position)
            
    # 2. Fire While Retreating
    var enemies_in_attack_range = game_state.get_units_in_radius(global_position, attack_range, team_id)
    if not enemies_in_attack_range.is_empty():
        var closest_enemy = _get_closest_valid_enemy(enemies_in_attack_range)
        if closest_enemy:
            target_unit = closest_enemy # Update target for aiming
            _attempt_attack_target(closest_enemy)

func _execute_current_state(delta: float):
    """The new state machine, driven by the `current_reactive_state` string."""
    # CRITICAL: Only execute behavior states on the server
    # Client units should only display server-calculated data, not execute logic
    if not multiplayer.is_server():
        return
    
    # Wait for behavior delay before processing
    if _behavior_timer < behavior_start_delay:
        _behavior_timer += delta
        return
        
    # Debug output every few seconds to see which state units are in
    if int(Time.get_ticks_msec() / 1000.0) % 10 == 0:
        print("DEBUG: Unit %s in state '%s' - executing actions" % [unit_id, current_reactive_state])
    
    match current_reactive_state:
        "attack":
            _execute_attack_state()

        "retreat":
            _execute_retreat_state()

        "defend":
            _execute_defend_state()
            
            # Also check for enemies while defending and attack if found
            var game_state = get_node("/root/DependencyContainer").get_game_state()
            if game_state:
                var enemies_in_range = game_state.get_units_in_radius(global_position, attack_range, team_id)
                if not enemies_in_range.is_empty():
                    var closest_enemy = _get_closest_valid_enemy(enemies_in_range)
                    if closest_enemy:
                        target_unit = closest_enemy
                        current_state = GameEnums.UnitState.ATTACKING
                        _attempt_attack_target(closest_enemy)
        
        "follow":
            _execute_follow_state()

func _execute_defend_state():
    """Logic for the defend state: capture uncontrolled nodes, then patrol around friendly nodes."""
    var node_system = get_node("/root/DependencyContainer").get_node_capture_system()
    
    print("DEBUG: Unit %s _execute_defend_state() called, node_system: %s" % [unit_id, str(node_system)])
    
    # First priority: Capture uncontrolled nodes if available
    var uncontrolled_node = _find_nearest_uncontrolled_node(node_system)
    if is_instance_valid(uncontrolled_node):
        # Move to the nearest uncontrolled node to capture it
        var target_pos = _clamp_to_map_bounds(uncontrolled_node.global_position)
        navigation_agent.target_position = target_pos
        print("DEBUG: Unit %s moving to capture uncontrolled node at %s" % [unit_id, target_pos])
        return
    
    # Second priority: Patrol around the nearest friendly node
    var closest_friendly_node = node_system.get_closest_friendly_node(global_position, team_id) if node_system else null
    if is_instance_valid(closest_friendly_node):
        # Patrol in a radius around the friendly node
        if navigation_agent.is_navigation_finished() or navigation_agent.target_position.distance_to(global_position) < 2.0:
            var patrol_radius = 15.0
            var random_angle = randf() * TAU
            var offset = Vector3(cos(random_angle), 0, sin(random_angle)) * patrol_radius
            var patrol_position = closest_friendly_node.global_position + offset
            var target_pos = _clamp_to_map_bounds(patrol_position)
            navigation_agent.target_position = target_pos
            print("DEBUG: Unit %s patrolling around friendly node, target: %s" % [unit_id, target_pos])
    else:
        # Third priority: No friendly nodes, patrol around home base
        var home_base_manager = get_tree().get_first_node_in_group("home_base_managers")
        if home_base_manager:
             if navigation_agent.is_navigation_finished() or navigation_agent.target_position.distance_to(global_position) < 2.0:
                var patrol_radius = 20.0
                var random_angle = randf() * TAU
                var offset = Vector3(cos(random_angle), 0, sin(random_angle)) * patrol_radius
                var home_patrol_position = home_base_manager.get_home_base_position(team_id) + offset
                var target_pos = _clamp_to_map_bounds(home_patrol_position)
                navigation_agent.target_position = target_pos
                print("DEBUG: Unit %s patrolling around home base, target: %s" % [unit_id, target_pos])
        else:
            print("DEBUG: Unit %s - no movement targets found (no nodes, no home base)" % unit_id)

func _execute_follow_state():
    """Logic for the follow state: follow nearest ally in range, with mutual following resolution."""
    var game_state = get_node("/root/DependencyContainer").get_game_state()
    if not game_state:
        return
    
    # Get allies in range  
    var allies = game_state.get_units_in_radius(global_position, vision_range, -1, team_id)
    if allies.is_empty():
        # No allies in range, fall back to next highest activation state
        _fallback_to_next_best_state()
        return
    
    # Find the nearest ally
    var nearest_ally = _get_nearest_ally(allies)
    if not is_instance_valid(nearest_ally):
        _fallback_to_next_best_state()
        return
    
    # Check for mutual following and resolve it
    var resolved_follow_target = _resolve_mutual_following(nearest_ally)
    if not is_instance_valid(resolved_follow_target):
        # This unit should not follow, fall back to next state
        _fallback_to_next_best_state()
        return
    
    # Set the follow target and update state
    follow_target = resolved_follow_target
    target_unit = null  # Clear attack target
    current_state = GameEnums.UnitState.FOLLOWING
    
    # Move to follow position (maintain distance)
    var follow_distance = FOLLOW_DISTANCE
    var direction_to_ally = (global_position - follow_target.global_position).normalized()
    var follow_position = follow_target.global_position + direction_to_ally * follow_distance
    navigation_agent.target_position = _clamp_to_map_bounds(follow_position)
    
    print("Unit %s (follow): Following ally %s" % [unit_id, follow_target.unit_id])

func _fallback_to_next_best_state():
    """Fall back to the next highest activation state when follow is not viable."""
    # Get current activation levels
    if last_action_scores.is_empty():
        current_reactive_state = "defend"  # Safe fallback
        return
    
    # Find the next best state (excluding follow)
    var validator = ActionValidator.new()
    var exclusive_actions = validator.MUTUALLY_EXCLUSIVE_REACTIVE_ACTIONS
    var best_action = "defend"  # Default fallback
    var max_score = -INF
    
    for action_name in exclusive_actions:
        if action_name == "follow":
            continue  # Skip follow state
        
        var score = last_action_scores.get(action_name, 0.0)
        if score > max_score:
            max_score = score
            best_action = action_name
    
    current_reactive_state = best_action
    print("Unit %s: Follow fallback to %s (score: %.2f)" % [unit_id, best_action, max_score])

func _get_nearest_ally(allies: Array) -> Unit:
    """Get the nearest ally from a list of allies."""
    var nearest_ally = null
    var nearest_distance = INF
    
    for ally in allies:
        if not is_instance_valid(ally) or ally == self or ally.is_dead:
            continue
        
        var distance = global_position.distance_to(ally.global_position)
        if distance < nearest_distance:
            nearest_distance = distance
            nearest_ally = ally
    
    return nearest_ally

func _resolve_mutual_following(target_ally: Unit) -> Unit:
    """Resolve mutual following between two units. Returns the unit this should follow, or null if this unit should not follow."""
    # Check if the target ally is also trying to follow this unit
    if not is_instance_valid(target_ally):
        return target_ally
    
    # Check if target ally is in follow state and targeting this unit
    var ally_following_this = false
    if "current_reactive_state" in target_ally and target_ally.current_reactive_state == "follow":
        if "follow_target" in target_ally and target_ally.follow_target == self:
            ally_following_this = true
    
    if not ally_following_this:
        # No mutual following, safe to follow
        return target_ally
    
    # Mutual following detected - resolve by comparing follow activation levels
    var my_follow_score = last_action_scores.get("follow", 0.0)
    var ally_follow_score = 0.0
    
    if "last_action_scores" in target_ally and target_ally.last_action_scores.has("follow"):
        ally_follow_score = target_ally.last_action_scores.follow
    
    if my_follow_score > ally_follow_score:
        # This unit has higher follow activation, it gets to follow
        print("Unit %s: Mutual follow resolved - this unit follows %s (%.2f > %.2f)" % [unit_id, target_ally.unit_id, my_follow_score, ally_follow_score])
        return target_ally
    else:
        # Target ally has higher (or equal) follow activation, this unit should not follow
        print("Unit %s: Mutual follow resolved - %s gets priority (%.2f >= %.2f)" % [unit_id, target_ally.unit_id, ally_follow_score, my_follow_score])
        return null

func _get_closest_valid_enemy(enemies: Array) -> Unit:
    """Get the closest valid enemy from a list of enemies"""
    var closest_enemy = null
    var closest_distance = INF
    for enemy in enemies:
        if is_instance_valid(enemy) and not enemy.is_dead:
            var distance = global_position.distance_to(enemy.global_position)
            if distance < closest_distance:
                closest_distance = distance
                closest_enemy = enemy
    return closest_enemy

func _clamp_to_map_bounds(position: Vector3) -> Vector3:
    """Clamp a position to stay within map boundaries"""
    return Vector3(
        clamp(position.x, MAP_BOUNDS.min_x, MAP_BOUNDS.max_x),
        position.y,  # Don't clamp Y axis
        clamp(position.z, MAP_BOUNDS.min_z, MAP_BOUNDS.max_z)
    )

func _find_nearest_uncontrolled_node(node_system) -> Node:
    """Find the nearest control point that is not controlled by our team"""
    if not node_system or not node_system.has_method("get_control_points"):
        return null
    
    var control_points = node_system.get_control_points()
    var nearest_node = null
    var nearest_distance = INF
    
    for control_point in control_points:
        if not is_instance_valid(control_point):
            continue
        
        # Check if this node is controlled by our team
        var controller_team = -1
        if control_point.has_method("get_controlling_team"):
            controller_team = control_point.get_controlling_team()
        
        # Skip if already controlled by our team
        if controller_team == team_id:
            continue
        
        # Calculate distance to this node
        var distance = global_position.distance_to(control_point.global_position)
        if distance < nearest_distance:
            nearest_distance = distance
            nearest_node = control_point
    
    return nearest_node

func _attempt_attack_target(target: Unit) -> void:
    """Attempt to attack a target using weapons or fallback damage"""
    if not is_instance_valid(target) or target.is_dead:
        return
    
    # Check attack cooldown
    var current_time = Time.get_ticks_msec() / 1000.0
    if current_time - last_attack_time < attack_cooldown:
        return
    
    # Check if target is in range
    var distance = global_position.distance_to(target.global_position)
    if distance > attack_range:
        return
    
    print("DEBUG: Unit %s attempting to attack target %s" % [unit_id, target.unit_id])
    
    # Try to fire weapon
    var weapon_fired = false
    if weapon_attachment and weapon_attachment.has_method("can_fire") and weapon_attachment.has_method("fire"):
        if weapon_attachment.can_fire():
            print("DEBUG: Unit %s firing weapon at target %s" % [unit_id, target.unit_id])
            var fire_result = weapon_attachment.fire()
            if not fire_result.is_empty():
                weapon_fired = true
                last_attack_time = current_time
                
                # Play attack animation if available
                if has_method("play_animation"):
                    call("play_animation", "Attack")
        else:
            print("DEBUG: Unit %s weapon cannot fire (cooldown or ammo)" % unit_id)
    
    # Fallback to direct damage if weapon failed
    if not weapon_fired:
        print("DEBUG: Unit %s using fallback direct damage against %s" % [unit_id, target.unit_id])
        target.take_damage(attack_damage)
        last_attack_time = current_time
        
        # Create damage indicator
        target._create_damage_indicator(attack_damage)
        
        # Play attack animation if available
        if has_method("play_animation"):
            call("play_animation", "Attack")

func _get_context_for_action(action_name: String) -> Dictionary:
    """Gets context-sensitive parameters for an action, e.g., a target for 'heal_ally'."""
    var params = {}
    var game_state = get_node("/root/DependencyContainer").get_game_state()
    if not game_state: return params

    match action_name:
        "heal_ally":
            var lowest_ally = _get_lowest_health_ally_in_vision()
            if is_instance_valid(lowest_ally):
                params["target_id"] = lowest_ally.unit_id
        "charge_shot", "attack":
            var closest_enemy = _get_closest_enemy_in_vision()
            if is_instance_valid(closest_enemy):
                params["target_id"] = closest_enemy.unit_id
    
    return params

func _get_visible_entities(group_name: String) -> Array:
    var visible_entities = []
    var game_state = get_node("/root/DependencyContainer").get_game_state()
    if not game_state: return []
    
    var entities_to_check = []
    if group_name == "units":
        entities_to_check = game_state.units.values()

    for entity in entities_to_check:
        if is_instance_valid(entity) and entity != self:
            if global_position.distance_to(entity.global_position) < vision_range:
                visible_entities.append(entity)
    return visible_entities

func _get_lowest_health_ally_in_vision() -> Unit:
    var allies = _get_visible_entities("units").filter(func(u): return u.team_id == self.team_id)
    var lowest_health_ally: Unit = null
    var lowest_health_pct = 1.1
    for ally in allies:
        var ally_health_pct = ally.get_health_percentage()
        if ally_health_pct < lowest_health_pct:
            lowest_health_pct = ally_health_pct
            lowest_health_ally = ally
    return lowest_health_ally

func _get_closest_enemy_in_vision() -> Unit:
    var enemies = _get_visible_entities("units").filter(func(u): return u.team_id != self.team_id)
    var closest_enemy: Unit = null
    var closest_dist = 9999.0
    for enemy in enemies:
        var dist = global_position.distance_to(enemy.global_position)
        if dist < closest_dist:
            closest_dist = dist
            closest_enemy = enemy
    return closest_enemy

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
func heal_ally(_params: Dictionary): pass
func construct(_params: Dictionary): pass
func repair(_params: Dictionary): pass
func lay_mines(_params: Dictionary): pass

# Respawn system methods
func _start_respawn_timer() -> void:
    """Start the respawn countdown timer"""
    is_respawning = true
    respawn_timer = GameConstants.UNIT_RESPAWN_TIME
    
    # CRITICAL: Re-enable physics processing for respawn countdown
    # The death sequence disables physics, but we need it for the respawn timer
    set_physics_process(true)
    
    print("DEBUG: Unit %s will respawn in %.1f seconds (physics_process re-enabled)" % [unit_id, respawn_timer])

func _handle_respawn() -> void:
    """Handle unit respawn after timer expires"""
    if not multiplayer.is_server():
        return
    
    # Get spawn position from home base manager
    var spawn_position = _get_respawn_position()
    
    # Reset unit state
    is_dead = false
    is_respawning = false
    current_health = max_health
    current_state = GameEnums.UnitState.IDLE
    
    # Apply invulnerability period
    invulnerable = true
    invulnerability_timer = GameConstants.RESPAWN_INVULNERABILITY_TIME
    
    # Clear any ongoing actions and triggers
    action_complete = true
    current_action.clear()
    current_action_trigger = ""
    target_unit = null
    follow_target = null
    
    # Move to spawn position
    global_position = spawn_position
    
    # CRITICAL FIX: Reset facing direction to face toward enemy base
    # This prevents units from walking in the wrong direction after respawn
    _set_initial_facing_direction()
    
    # Re-enable physics and collision
    set_physics_process(true)
    set_collision_layer_value(1, true)  # Re-enable selection
    
    # CRITICAL: Properly restore collision mask for navigation
    set_collision_mask_value(1, false)   # Don't collide with other units for avoidance
    set_collision_mask_value(2, true)    # Collide with buildings for pathfinding
    set_collision_mask_value(3, true)    # Collide with terrain/static objects
    
    # Re-enable the CollisionShape3D if it was disabled
    var collision_shape = get_node_or_null("CollisionShape3D")
    if collision_shape and collision_shape.disabled:
        collision_shape.disabled = false
        print("DEBUG: Re-enabled CollisionShape3D for unit %s" % unit_id)
    
    # Ensure unit is visible
    visible = true
    
    # Trigger respawn effects if this is an animated unit
    if has_method("trigger_respawn_sequence"):
        call("trigger_respawn_sequence")
    
    # Emit respawn signal
    unit_respawned.emit(unit_id)
    
    print("DEBUG: Unit %s respawned at %s with %d health (invulnerable for %.1f seconds)" % [
        unit_id, spawn_position, current_health, invulnerability_timer
    ])
    print("DEBUG: Unit %s respawn state - is_dead: %s, is_respawning: %s, physics_processing: %s" % [
        unit_id, is_dead, is_respawning, is_physics_processing()
    ])

func _get_respawn_position() -> Vector3:
    """Get the respawn position for this unit with bounds checking"""
    var home_base_manager = get_tree().get_first_node_in_group("home_base_managers")
    if home_base_manager:
        # Use the home base manager's safe spawn positioning
        return home_base_manager.get_spawn_position_with_offset(team_id)
    
    # Fallback to original spawn position with bounds checking
    var fallback_offset = Vector3(randf() * 2.0 - 1.0, 0, randf() * 2.0 - 1.0)
    var fallback_position = original_spawn_position + fallback_offset
    
    # Clamp to map bounds
    return _clamp_to_map_bounds(fallback_position)

func get_respawn_time_remaining() -> float:
    """Get remaining respawn time (for UI display)"""
    return respawn_timer if is_respawning else 0.0

func _get_default_behavior_matrix() -> Dictionary:
    var validator = ActionValidator.new()
    var valid_actions = validator.get_valid_actions_for_archetype(archetype)
    var matrix = {}

    # Default weights for a balanced, generic unit
    var default_weights = {
        # --- Mutually Exclusive States ---
        "attack": {
            "enemies_in_range": 0.8, "current_health": 0.2, "under_attack": 0.1,
            "allies_in_range": 0.3, "ally_low_health": 0.1, "enemy_nodes_controlled": 0.4,
            "ally_nodes_controlled": -0.2, "bias": -0.2
        },
        "retreat": {
            "enemies_in_range": 0.4, "current_health": -0.9, "under_attack": 0.8,
            "allies_in_range": -0.3, "ally_low_health": -0.5, "enemy_nodes_controlled": 0.1,
            "ally_nodes_controlled": 0.0, "bias": -0.8
        },
        "defend": {
            "enemies_in_range": -0.5, "current_health": 0.5, "under_attack": -0.6,
            "allies_in_range": 0.2, "ally_low_health": 0.2, "enemy_nodes_controlled": -0.3,
            "ally_nodes_controlled": 0.5, "bias": -0.6
        },
        "follow": {
            "enemies_in_range": -0.3, "current_health": 0.0, "under_attack": -0.4,
            "allies_in_range": 0.7, "ally_low_health": 0.3, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": -0.6
        },
        # --- Independent Abilities (generally off by default or context-sensitive) ---
        "activate_stealth": {"bias": -1.0},
        "activate_shield": {
            "enemies_in_range": 0.5, "current_health": -0.6, "under_attack": 0.9, "bias": -0.7
        },
        "taunt_enemies": {
            "enemies_in_range": 0.8, "current_health": 0.8, "allies_in_range": 0.5, "bias": -1.0
        },
        "charge_shot": {"bias": -1.0},
        "heal_ally": {
            "allies_in_range": 0.8, "ally_low_health": 0.9, "bias": -0.3
        },
        "lay_mines": {"bias": -1.0}, "construct": {"bias": -1.0}, "repair": {"bias": -1.0},
        "find_cover": {
            "under_attack": 0.7, "current_health": -0.5, "bias": -0.6
        }
    }

    # Populate the matrix, ensuring only valid actions for this archetype are included
    for action in valid_actions:
        matrix[action] = {}
        var template = default_weights.get(action, {})
        for state_var in validator.DEFINED_STATE_VARIABLES:
            matrix[action][state_var] = template.get(state_var, 0.0)
    
    return matrix

func _get_fallback_state_variables() -> Dictionary:
    """Provide basic fallback state variables when dependencies aren't available"""
    return {
        "enemies_in_range": 0.0,  # No enemies detected
        "current_health": get_health_percentage(),
        "under_attack": 0.0,  # Not under attack
        "allies_in_range": 0.0,  # No allies detected  
        "ally_low_health": 0.0,  # No low health allies
        "ally_nodes_controlled": 0.5,  # Neutral assumption
        "enemy_nodes_controlled": 0.5,  # Neutral assumption
        "bias": 1.0
    }