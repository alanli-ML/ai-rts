extends Node
class_name UnitSpawner

var server_unit_scene: PackedScene
var spawned_units: Dictionary = {}
var unit_counter: int = 0

# Unit types configuration
var unit_types: Dictionary = {
    "scout": {
        "health": 80,
        "speed": 6.0,
        "damage": 20,
        "range": 2.5,
        "vision": 10.0,
        "cost": 50
    },
    "soldier": {
        "health": 120,
        "speed": 4.0,
        "damage": 35,
        "range": 3.0,
        "vision": 8.0,
        "cost": 75
    },
    "tank": {
        "health": 300,
        "speed": 2.0,
        "damage": 80,
        "range": 5.0,
        "vision": 12.0,
        "cost": 200
    },
    "medic": {
        "health": 100,
        "speed": 4.5,
        "damage": 10,
        "range": 2.0,
        "vision": 8.0,
        "cost": 100
    },
    "engineer": {
        "health": 90,
        "speed": 4.0,
        "damage": 15,
        "range": 2.0,
        "vision": 6.0,
        "cost": 80
    }
}

# Spawn positions for teams
var team_spawn_positions: Dictionary = {
    0: Vector3(-20, 0, 0),  # Team 0 spawn
    1: Vector3(20, 0, 0)    # Team 1 spawn  
}

# Signals
signal unit_spawned(unit_id: String, unit_data: Dictionary)
signal unit_destroyed(unit_id: String)

func _ready() -> void:
    # Load unit scene
    server_unit_scene = preload("res://scenes/ServerUnit.tscn")
    
    if not server_unit_scene:
        print("Error: Could not load ServerUnit scene")
        return
    
    print("UnitSpawner initialized")

func spawn_unit(unit_type: String, team_id: int, player_id: String, spawn_position: Vector3 = Vector3.ZERO) -> String:
    if not unit_types.has(unit_type):
        print("Error: Unknown unit type: %s" % unit_type)
        return ""
    
    # Generate unique unit ID
    var unit_id = "unit_%s_%d_%d" % [unit_type, team_id, unit_counter]
    unit_counter += 1
    
    # Create unit instance
    var unit_instance = server_unit_scene.instantiate()
    if not unit_instance:
        print("Error: Could not instantiate unit scene")
        return ""
    
    # Configure unit
    var unit_config = unit_types[unit_type]
    unit_instance.unit_id = unit_id
    unit_instance.unit_type = unit_type
    unit_instance.team_id = team_id
    unit_instance.owner_player_id = player_id
    unit_instance.max_health = unit_config.health
    unit_instance.current_health = unit_config.health
    unit_instance.movement_speed = unit_config.speed
    unit_instance.attack_damage = unit_config.damage
    unit_instance.attack_range = unit_config.range
    unit_instance.vision_range = unit_config.vision
    
    # Set spawn position
    if spawn_position == Vector3.ZERO:
        spawn_position = _get_spawn_position(team_id)
    
    unit_instance.global_position = spawn_position
    
    # Connect signals
    unit_instance.unit_destroyed.connect(_on_unit_destroyed)
    unit_instance.unit_health_changed.connect(_on_unit_health_changed)
    unit_instance.unit_state_changed.connect(_on_unit_state_changed)
    
    # Add to scene
    add_child(unit_instance)
    
    # Store reference
    spawned_units[unit_id] = unit_instance
    
    print("Spawned unit: %s (type: %s, team: %d, player: %s)" % [unit_id, unit_type, team_id, player_id])
    
    # Emit signal
    unit_spawned.emit(unit_id, unit_instance.get_unit_data())
    
    return unit_id

func spawn_units_for_team(team_id: int, player_id: String, unit_count: int = 5) -> Array:
    var spawned_unit_ids = []
    var base_position = team_spawn_positions.get(team_id, Vector3.ZERO)
    
    # Spawn default unit composition
    var unit_composition = [
        "scout", "scout", "soldier", "soldier", "tank"
    ]
    
    for i in range(min(unit_count, unit_composition.size())):
        var unit_type = unit_composition[i]
        var spawn_offset = Vector3(
            randf_range(-5, 5),
            0,
            randf_range(-5, 5)
        )
        var spawn_pos = base_position + spawn_offset
        
        var unit_id = spawn_unit(unit_type, team_id, player_id, spawn_pos)
        if unit_id != "":
            spawned_unit_ids.append(unit_id)
    
    print("Spawned %d units for team %d" % [spawned_unit_ids.size(), team_id])
    return spawned_unit_ids

func despawn_unit(unit_id: String) -> void:
    if unit_id in spawned_units:
        var unit = spawned_units[unit_id]
        unit.queue_free()
        spawned_units.erase(unit_id)
        print("Despawned unit: %s" % unit_id)

func get_unit(unit_id: String) -> ServerUnit:
    return spawned_units.get(unit_id, null)

func get_units_for_team(team_id: int) -> Array:
    var team_units = []
    for unit in spawned_units.values():
        if unit.team_id == team_id:
            team_units.append(unit)
    return team_units

func get_units_for_player(player_id: String) -> Array:
    var player_units = []
    for unit in spawned_units.values():
        if unit.owner_player_id == player_id:
            player_units.append(unit)
    return player_units

func get_all_units() -> Array:
    return spawned_units.values()

func get_unit_count() -> int:
    return spawned_units.size()

func get_unit_count_for_team(team_id: int) -> int:
    var count = 0
    for unit in spawned_units.values():
        if unit.team_id == team_id:
            count += 1
    return count

func _get_spawn_position(team_id: int) -> Vector3:
    var base_position = team_spawn_positions.get(team_id, Vector3.ZERO)
    
    # Add random offset to prevent stacking
    var offset = Vector3(
        randf_range(-3, 3),
        0,
        randf_range(-3, 3)
    )
    
    return base_position + offset

func _on_unit_destroyed(unit_id: String) -> void:
    if unit_id in spawned_units:
        spawned_units.erase(unit_id)
        print("Unit destroyed: %s" % unit_id)
        unit_destroyed.emit(unit_id)

func _on_unit_health_changed(unit_id: String, health: int) -> void:
    # Forward health change events
    pass

func _on_unit_state_changed(unit_id: String, state: int) -> void:
    # Forward state change events  
    pass

# Command execution
func execute_command_on_units(unit_ids: Array, command: Dictionary) -> void:
    for unit_id in unit_ids:
        var unit = get_unit(unit_id)
        if unit:
            unit.execute_command(command)

func execute_ai_command(command: Dictionary, selected_unit_ids: Array) -> void:
    var command_type = command.get("type", "")
    var target_unit_ids = command.get("unit_ids", selected_unit_ids)
    
    print("Executing AI command: %s on units: %s" % [command_type, target_unit_ids])
    
    execute_command_on_units(target_unit_ids, command)

# Utility functions
func get_units_in_area(center: Vector3, radius: float) -> Array:
    var units_in_area = []
    
    for unit in spawned_units.values():
        var distance = center.distance_to(unit.global_position)
        if distance <= radius:
            units_in_area.append(unit)
    
    return units_in_area

func get_nearest_enemy_unit(position: Vector3, team_id: int) -> ServerUnit:
    var nearest_enemy: ServerUnit = null
    var nearest_distance = INF
    
    for unit in spawned_units.values():
        if unit.team_id == team_id or unit.current_state == ServerUnit.UnitState.DEAD:
            continue
        
        var distance = position.distance_to(unit.global_position)
        if distance < nearest_distance:
            nearest_distance = distance
            nearest_enemy = unit
    
    return nearest_enemy

func get_units_data() -> Array:
    var units_data = []
    for unit in spawned_units.values():
        units_data.append(unit.get_unit_data())
    return units_data

func clear_all_units() -> void:
    for unit in spawned_units.values():
        unit.queue_free()
    spawned_units.clear()
    print("Cleared all units")

# Formation helpers
func arrange_units_in_formation(unit_ids: Array, formation_type: String, center_position: Vector3) -> void:
    var units = []
    for unit_id in unit_ids:
        var unit = get_unit(unit_id)
        if unit:
            units.append(unit)
    
    if units.size() == 0:
        return
    
    var positions = _calculate_formation_positions(units.size(), formation_type, center_position)
    
    for i in range(units.size()):
        if i < positions.size():
            units[i].move_to_position(positions[i])

func _calculate_formation_positions(unit_count: int, formation_type: String, center: Vector3) -> Array:
    var positions = []
    
    match formation_type:
        "line":
            for i in range(unit_count):
                var offset = Vector3((i - unit_count / 2) * 2, 0, 0)
                positions.append(center + offset)
        "circle":
            var radius = max(2.0, unit_count * 0.5)
            for i in range(unit_count):
                var angle = (i / float(unit_count)) * TAU
                var offset = Vector3(cos(angle) * radius, 0, sin(angle) * radius)
                positions.append(center + offset)
        "wedge":
            var rows = int(ceil(sqrt(unit_count)))
            var current_unit = 0
            for row in range(rows):
                var units_in_row = min(row + 1, unit_count - current_unit)
                for col in range(units_in_row):
                    var x_offset = (col - units_in_row / 2) * 2
                    var z_offset = row * 2
                    positions.append(center + Vector3(x_offset, 0, z_offset))
                    current_unit += 1
                    if current_unit >= unit_count:
                        break
                if current_unit >= unit_count:
                    break
        _:
            # Default to line formation
            return _calculate_formation_positions(unit_count, "line", center)
    
    return positions 