extends CharacterBody3D
class_name ServerUnit

@export var unit_id: String = ""
@export var unit_type: String = "scout"
@export var team_id: int = 0
@export var owner_player_id: String = ""

# Unit stats
@export var max_health: int = 100
@export var current_health: int = 100
@export var movement_speed: float = 5.0
@export var attack_damage: int = 25
@export var attack_range: float = 3.0
@export var vision_range: float = 8.0

# Movement and navigation
var target_position: Vector3
var movement_target: Vector3
var is_moving: bool = false
var nav_agent: NavigationAgent3D

# Combat
var attack_target: ServerUnit
var last_attack_time: float = 0.0
var attack_cooldown: float = 1.0

# Unit state
enum UnitState {
    IDLE,
    MOVING,
    ATTACKING,
    DEAD
}

var current_state: UnitState = UnitState.IDLE

# Multiplayer synchronization
var last_sync_time: float = 0.0
var sync_interval: float = 0.1  # 10Hz sync rate

# Signals
signal unit_destroyed(unit_id: String)
signal unit_health_changed(unit_id: String, health: int)
signal unit_state_changed(unit_id: String, state: UnitState)

func _ready() -> void:
    # Setup navigation agent
    nav_agent = NavigationAgent3D.new()
    add_child(nav_agent)
    nav_agent.path_desired_distance = 0.5
    nav_agent.target_desired_distance = 0.5
    nav_agent.navigation_finished.connect(_on_navigation_finished)
    
    # Setup collision
    var collision_shape = CollisionShape3D.new()
    var box_shape = BoxShape3D.new()
    box_shape.size = Vector3(1, 2, 1)
    collision_shape.shape = box_shape
    add_child(collision_shape)
    
    # Setup visual representation
    var mesh_instance = MeshInstance3D.new()
    var box_mesh = BoxMesh.new()
    box_mesh.size = Vector3(1, 2, 1)
    mesh_instance.mesh = box_mesh
    add_child(mesh_instance)
    
    # Set up multiplayer synchronization
    set_multiplayer_authority(1)  # Server authority
    
    # Initialize unit
    if unit_id == "":
        unit_id = "unit_" + str(randi())
    
    current_health = max_health
    target_position = global_position
    movement_target = global_position
    
    print("ServerUnit initialized: %s (team: %d)" % [unit_id, team_id])

func _physics_process(delta: float) -> void:
    if not is_multiplayer_authority():
        return
    
    # Update unit logic
    _update_unit_logic(delta)
    
    # Handle movement
    if is_moving:
        _handle_movement(delta)
    
    # Handle combat
    if attack_target:
        _handle_combat(delta)
    
    # Sync to clients periodically
    if Time.get_ticks_msec() - last_sync_time > sync_interval * 1000:
        _sync_to_clients()
        last_sync_time = Time.get_ticks_msec()

func _update_unit_logic(delta: float) -> void:
    # Update state based on conditions
    match current_state:
        UnitState.IDLE:
            _update_idle_state()
        UnitState.MOVING:
            _update_moving_state()
        UnitState.ATTACKING:
            _update_attacking_state()
        UnitState.DEAD:
            return

func _update_idle_state() -> void:
    # Look for enemies in range
    var enemies = _find_enemies_in_range(vision_range)
    if enemies.size() > 0:
        set_attack_target(enemies[0])

func _update_moving_state() -> void:
    # Check if we've reached our destination
    if global_position.distance_to(movement_target) < 0.5:
        stop_movement()
    
    # Check for enemies while moving
    var enemies = _find_enemies_in_range(vision_range)
    if enemies.size() > 0:
        set_attack_target(enemies[0])

func _update_attacking_state() -> void:
    # Check if target is still valid
    if not attack_target or attack_target.current_state == UnitState.DEAD:
        clear_attack_target()
        return
    
    # Check if target is in range
    var distance_to_target = global_position.distance_to(attack_target.global_position)
    if distance_to_target > attack_range:
        # Move closer to target
        move_to_position(attack_target.global_position)

func _handle_movement(delta: float) -> void:
    if nav_agent.is_navigation_finished():
        stop_movement()
        return
    
    var next_position = nav_agent.get_next_path_position()
    var direction = (next_position - global_position).normalized()
    
    velocity = direction * movement_speed
    move_and_slide()

func _handle_combat(delta: float) -> void:
    if not attack_target or attack_target.current_state == UnitState.DEAD:
        clear_attack_target()
        return
    
    var distance_to_target = global_position.distance_to(attack_target.global_position)
    
    if distance_to_target <= attack_range:
        # Stop moving and attack
        stop_movement()
        
        # Check attack cooldown
        if Time.get_ticks_msec() - last_attack_time > attack_cooldown * 1000:
            _perform_attack()
            last_attack_time = Time.get_ticks_msec()
    else:
        # Move closer to target
        move_to_position(attack_target.global_position)

func _perform_attack() -> void:
    if not attack_target:
        return
    
    print("Unit %s attacking %s" % [unit_id, attack_target.unit_id])
    
    # Deal damage
    attack_target.take_damage(attack_damage)
    
    # Broadcast attack to clients
    _broadcast_attack_event()

func take_damage(amount: int) -> void:
    if current_state == UnitState.DEAD:
        return
    
    current_health -= amount
    unit_health_changed.emit(unit_id, current_health)
    
    print("Unit %s took %d damage (health: %d/%d)" % [unit_id, amount, current_health, max_health])
    
    if current_health <= 0:
        _die()

func _die() -> void:
    current_state = UnitState.DEAD
    current_health = 0
    
    print("Unit %s destroyed" % unit_id)
    
    unit_destroyed.emit(unit_id)
    unit_state_changed.emit(unit_id, current_state)
    
    # Broadcast death to clients
    _broadcast_death_event()
    
    # Remove from scene after delay
    await get_tree().create_timer(2.0).timeout
    queue_free()

# Command handling
func move_to_position(target_pos: Vector3) -> void:
    movement_target = target_pos
    nav_agent.target_position = target_pos
    is_moving = true
    
    if current_state != UnitState.ATTACKING:
        _set_state(UnitState.MOVING)
    
    print("Unit %s moving to %s" % [unit_id, target_pos])

func stop_movement() -> void:
    is_moving = false
    velocity = Vector3.ZERO
    
    if current_state == UnitState.MOVING:
        _set_state(UnitState.IDLE)

func set_attack_target(target: ServerUnit) -> void:
    attack_target = target
    _set_state(UnitState.ATTACKING)
    
    print("Unit %s attacking %s" % [unit_id, target.unit_id])

func clear_attack_target() -> void:
    attack_target = null
    
    if current_state == UnitState.ATTACKING:
        _set_state(UnitState.IDLE)

func _set_state(new_state: UnitState) -> void:
    if current_state != new_state:
        current_state = new_state
        unit_state_changed.emit(unit_id, current_state)
        print("Unit %s state: %s" % [unit_id, UnitState.keys()[current_state]])

# Utility functions
func _find_enemies_in_range(range: float) -> Array:
    var enemies = []
    var units = get_tree().get_nodes_in_group("server_units")
    
    for unit in units:
        if unit == self or unit.team_id == team_id:
            continue
        
        if unit.current_state == UnitState.DEAD:
            continue
        
        var distance = global_position.distance_to(unit.global_position)
        if distance <= range:
            enemies.append(unit)
    
    return enemies

func _on_navigation_finished() -> void:
    stop_movement()

# Multiplayer synchronization
func _sync_to_clients() -> void:
    var sync_data = {
        "unit_id": unit_id,
        "position": global_position,
        "rotation": global_rotation,
        "velocity": velocity,
        "health": current_health,
        "state": current_state,
        "is_moving": is_moving,
        "movement_target": movement_target
    }
    
    rpc("_on_unit_sync", sync_data)

@rpc("authority", "call_local", "unreliable")
func _on_unit_sync(sync_data: Dictionary) -> void:
    # This will be received by clients for interpolation
    pass

func _broadcast_attack_event() -> void:
    var attack_data = {
        "attacker_id": unit_id,
        "target_id": attack_target.unit_id if attack_target else "",
        "damage": attack_damage,
        "timestamp": Time.get_ticks_msec()
    }
    
    rpc("_on_attack_event", attack_data)

@rpc("authority", "call_local", "reliable")
func _on_attack_event(attack_data: Dictionary) -> void:
    # This will be received by clients for visual effects
    pass

func _broadcast_death_event() -> void:
    var death_data = {
        "unit_id": unit_id,
        "timestamp": Time.get_ticks_msec()
    }
    
    rpc("_on_death_event", death_data)

@rpc("authority", "call_local", "reliable")
func _on_death_event(death_data: Dictionary) -> void:
    # This will be received by clients for death effects
    pass

# Public interface for session management
func get_unit_data() -> Dictionary:
    return {
        "unit_id": unit_id,
        "unit_type": unit_type,
        "team_id": team_id,
        "owner_player_id": owner_player_id,
        "position": global_position,
        "health": current_health,
        "max_health": max_health,
        "state": current_state
    }

func execute_command(command: Dictionary) -> void:
    var command_type = command.get("type", "")
    
    match command_type:
        "MOVE":
            var target_pos = command.get("target_position", Vector3.ZERO)
            move_to_position(target_pos)
        "ATTACK":
            var target_unit_id = command.get("target_unit_id", "")
            var target_unit = _find_unit_by_id(target_unit_id)
            if target_unit:
                set_attack_target(target_unit)
        "STOP":
            stop_movement()
            clear_attack_target()
        _:
            print("Unknown command: %s" % command_type)

func _find_unit_by_id(search_id: String) -> ServerUnit:
    var units = get_tree().get_nodes_in_group("server_units")
    for unit in units:
        if unit.unit_id == search_id:
            return unit
    return null 