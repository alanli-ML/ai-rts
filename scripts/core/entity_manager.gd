# EntityManager.gd - Manages deployable entities (mines, spires) - Turrets are handled as units
class_name EntityManager
extends Node

# Load shared components
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")

# Entity collections (turrets removed - they are units now)
var active_mines: Dictionary = {}      # mine_id -> Node
var active_spires: Dictionary = {}     # spire_id -> Node

# Tile-based placement tracking
var tile_occupation: Dictionary = {}   # tile_pos -> entity_id
var placement_restrictions: Dictionary = {}  # tile_pos -> restriction_type

# Entity limits per team (turrets removed - handled by GameState unit limits)
var team_limits: Dictionary = {
    "mines": 10,
    "spires": 3
}

# Entity counts per team (turrets removed)
var team_counts: Dictionary = {
    1: {"mines": 0, "spires": 0},
    2: {"mines": 0, "spires": 0}
}

# Dependencies
var logger
var asset_loader: Node
var map_generator: Node
var resource_manager: Node
var tile_system: Node

# Performance settings
var max_entities_per_frame: int = 5
var cleanup_interval: float = 10.0
var last_cleanup_time: float = 0.0

# Entity containers in 3D scene (turrets container removed)
var entities_container: Node3D
var mines_container: Node3D
var spires_container: Node3D

# Signals
signal entity_created(entity_type: String, entity_id: String, position: Vector3)
signal entity_destroyed(entity_type: String, entity_id: String, reason: String)
signal entity_limit_reached(entity_type: String, team_id: int, limit: int)
signal tile_occupied(tile_pos: Vector2i, entity_id: String)
signal tile_freed(tile_pos: Vector2i, entity_id: String)
signal placement_validation_failed(tile_pos: Vector2i, reason: String)

func _ready() -> void:
    # Add to group
    add_to_group("entity_managers")
    
    # Initialize cleanup timer
    last_cleanup_time = Time.get_ticks_msec() / 1000.0

func setup(logger_ref, asset_loader_ref, map_generator_ref, resource_manager_ref) -> void:
    """Setup entity manager with dependencies"""
    logger = logger_ref
    asset_loader = asset_loader_ref
    map_generator = map_generator_ref
    resource_manager = resource_manager_ref
    
    # Get tile system reference
    if map_generator and map_generator.has_method("get_tile_system"):
        tile_system = map_generator.get_tile_system()
    
    # Create entity containers
    _create_entity_containers()
    
    if logger:
        logger.info("EntityManager", "Entity manager initialized with tile system")

func _create_entity_containers() -> void:
    """Create containers for organizing entities in 3D scene"""
    
    # Find or create main entities container
    var scene_root = get_tree().current_scene
    entities_container = scene_root.get_node("Entities")
    if not entities_container:
        entities_container = Node3D.new()
        entities_container.name = "Entities"
        scene_root.add_child(entities_container)
    
    # Create type-specific containers
    mines_container = Node3D.new()
    mines_container.name = "Mines"
    entities_container.add_child(mines_container)
    
    spires_container = Node3D.new()
    spires_container.name = "Spires"
    entities_container.add_child(spires_container)

func _process(delta: float) -> void:
    """Process entity management"""
    
    # Periodic cleanup
    var current_time = Time.get_ticks_msec() / 1000.0
    if current_time - last_cleanup_time >= cleanup_interval:
        _cleanup_destroyed_entities()
        last_cleanup_time = current_time

# Mine deployment methods
func deploy_mine(tile_pos: Vector2i, mine_type: String, team_id: int, owner_unit_id: String) -> String:
    """Deploy a mine at the specified tile position"""
    
    # Validate placement
    var validation_result = _validate_placement(tile_pos, "mine", team_id)
    if not validation_result.valid:
        placement_validation_failed.emit(tile_pos, validation_result.reason)
        return ""
    
    # Check team limits
    if team_counts[team_id]["mines"] >= team_limits["mines"]:
        entity_limit_reached.emit("mine", team_id, team_limits["mines"])
        return ""
    
    # Create simple mine node (fallback implementation)
    var mine = Node3D.new()
    var mine_id = "mine_" + str(Time.get_ticks_msec()) + "_" + str(randi())
    mine.name = mine_id
    mine.set("mine_id", mine_id)
    mine.set("team_id", team_id)
    mine.set("mine_type", mine_type)
    mine.set("tile_position", tile_pos)
    
    # Position the mine in world space
    mine.global_position = Vector3(tile_pos.x, 0, tile_pos.y)
    
    # Add to scene
    mines_container.add_child(mine)
    
    # Register mine
    active_mines[mine_id] = mine
    team_counts[team_id]["mines"] += 1
    _occupy_tile(tile_pos, mine_id)
    
    entity_created.emit("mine", mine_id, mine.global_position)
    
    if logger:
        logger.info("EntityManager", "Mine %s deployed at tile %s by unit %s" % [mine_id, tile_pos, owner_unit_id])
    
    return mine_id

func get_mine(mine_id: String) -> Node:
    """Get mine by ID"""
    return active_mines.get(mine_id, null)

func get_mines_in_area(center: Vector3, radius: float) -> Array[Node]:
    """Get all mines within a radius of center point"""
    var mines_in_area = []
    
    for mine_id in active_mines:
        var mine = active_mines[mine_id]
        if mine and mine.global_position.distance_to(center) <= radius:
            mines_in_area.append(mine)
    
    return mines_in_area

func trigger_remote_mine(mine_id: String) -> bool:
    """Trigger a remote mine"""
    var mine = get_mine(mine_id)
    if mine and mine.get("mine_type") == "remote":
        # Assuming a method like remote_trigger() exists on the mine node
        # This part needs to be adapted based on the actual MineEntity class
        # For now, we'll just emit a signal or call a method if it exists
        if mine.has_method("remote_trigger"):
            mine.remote_trigger()
            return true
    return false

# Spire management methods
func create_spire(tile_pos: Vector2i, spire_type: String, team_id: int) -> String:
    """Create a spire at the specified tile position"""
    
    # Validate placement
    var validation_result = _validate_placement(tile_pos, "spire", team_id)
    if not validation_result.valid:
        placement_validation_failed.emit(tile_pos, validation_result.reason)
        return ""
    
    # Check team limits
    if team_counts[team_id]["spires"] >= team_limits["spires"]:
        entity_limit_reached.emit("spire", team_id, team_limits["spires"])
        return ""
    
    # Create simple spire node (fallback implementation)
    var spire = Node3D.new()
    var spire_id = "spire_" + str(Time.get_ticks_msec()) + "_" + str(randi())
    spire.name = spire_id
    spire.set("spire_id", spire_id)
    spire.set("team_id", team_id)
    spire.set("spire_type", spire_type)
    spire.set("tile_position", tile_pos)
    
    # Position the spire in world space  
    spire.global_position = Vector3(tile_pos.x, 0, tile_pos.y)
    
    # Add to scene
    spires_container.add_child(spire)
    
    # Register spire
    active_spires[spire_id] = spire
    team_counts[team_id]["spires"] += 1
    _occupy_tile(tile_pos, spire_id)
    
    entity_created.emit("spire", spire_id, spire.global_position)
    
    if logger:
        logger.info("EntityManager", "Spire %s created at tile %s for team %d" % [spire_id, tile_pos, team_id])
    
    return spire_id

func get_spire(spire_id: String) -> Node:
    """Get spire by ID"""
    return active_spires.get(spire_id, null)

func get_spires_for_team(team_id: int) -> Array[Node]:
    """Get all spires controlled by a team"""
    var team_spires = []
    
    for spire_id in active_spires:
        var spire = active_spires[spire_id]
        if spire and spire.get("team_id") == team_id:
            team_spires.append(spire)
    
    return team_spires

func get_hijackable_spires(team_id: int) -> Array[Node]:
    """Get all spires that can be hijacked by a team"""
    var hijackable_spires = []
    
    for spire_id in active_spires:
        var spire = active_spires[spire_id]
        if spire and spire.get("team_id") != team_id and not spire.get("is_being_hijacked", false):
            hijackable_spires.append(spire)
    
    return hijackable_spires

# Placement validation
func _validate_placement(tile_pos: Vector2i, entity_type: String, team_id: int) -> Dictionary:
    """Validate entity placement at tile position"""
    
    var result = {"valid": true, "reason": ""}
    
    # Check if tile system is available
    if not tile_system:
        result.valid = false
        result.reason = "tile_system_unavailable"
        return result
    
    # Check if tile is within bounds
    if not tile_system.is_tile_valid(tile_pos):
        result.valid = false
        result.reason = "tile_out_of_bounds"
        return result
    
    # Check if tile is already occupied
    if tile_pos in tile_occupation:
        result.valid = false
        result.reason = "tile_occupied"
        return result
    
    # Check placement restrictions
    if tile_pos in placement_restrictions:
        var restriction = placement_restrictions[tile_pos]
        if restriction != entity_type:
            result.valid = false
            result.reason = "placement_restricted"
            return result
    
    # Entity-specific validation
    match entity_type:
        "mine":
            # Mines can't be placed too close to each other
            if _has_nearby_entity("mine", tile_pos, 2):
                result.valid = false
                result.reason = "too_close_to_mine"
        
        "spire":
            # Spires need significant separation
            if _has_nearby_entity("spire", tile_pos, 5):
                result.valid = false
                result.reason = "too_close_to_spire"
    
    return result

func _has_nearby_entity(entity_type: String, tile_pos: Vector2i, radius: int) -> bool:
    """Check if there's an entity of the same type within radius"""
    
    var entities_dict = {}
    match entity_type:
        "mine":
            entities_dict = active_mines
        "spire":
            entities_dict = active_spires
    
    for entity_id in entities_dict:
        var entity = entities_dict[entity_id]
        if entity and entity.get("tile_position").distance_to(tile_pos) <= radius:
            return true
    
    return false

func _occupy_tile(tile_pos: Vector2i, entity_id: String) -> void:
    """Mark tile as occupied by entity"""
    
    tile_occupation[tile_pos] = entity_id
    tile_occupied.emit(tile_pos, entity_id)

func _free_tile(tile_pos: Vector2i, entity_id: String) -> void:
    """Mark tile as free"""
    
    if tile_pos in tile_occupation and tile_occupation[tile_pos] == entity_id:
        tile_occupation.erase(tile_pos)
        tile_freed.emit(tile_pos, entity_id)

# Entity cleanup
func _cleanup_destroyed_entities() -> void:
    """Remove destroyed entities from collections"""
    
    # Clean up mines
    var mines_to_remove = []
    for mine_id in active_mines:
        var mine = active_mines[mine_id]
        if not mine or not is_instance_valid(mine):
            mines_to_remove.append(mine_id)
    
    for mine_id in mines_to_remove:
        active_mines.erase(mine_id)
    
    # Clean up spires
    var spires_to_remove = []
    for spire_id in active_spires:
        var spire = active_spires[spire_id]
        if not spire or not is_instance_valid(spire):
            spires_to_remove.append(spire_id)
    
    for spire_id in spires_to_remove:
        active_spires.erase(spire_id)

# Signal handlers
func _on_mine_destroyed(mine_id: String, reason: String) -> void:
    """Handle mine destruction"""
    
    var mine = active_mines.get(mine_id, null)
    if mine:
        # Update team count
        team_counts[mine.get("team_id")]["mines"] -= 1
        
        # Free tile
        _free_tile(mine.get("tile_position"), mine_id)
        
        # Remove from collection
        active_mines.erase(mine_id)
        
        entity_destroyed.emit("mine", mine_id, reason)

func _on_mine_exploded(mine_id: String, position: Vector3, damage: float) -> void:
    """Handle mine explosion"""
    
    if logger:
        logger.info("EntityManager", "Mine %s exploded at %s with %.1f damage" % [mine_id, position, damage])

func _on_spire_destroyed(spire_id: String, reason: String) -> void:
    """Handle spire destruction"""
    
    var spire = active_spires.get(spire_id, null)
    if spire:
        # Update team count
        team_counts[spire.get("team_id")]["spires"] -= 1
        
        # Free tile
        _free_tile(spire.get("tile_position"), spire_id)
        
        # Remove from collection
        active_spires.erase(spire_id)
        
        entity_destroyed.emit("spire", spire_id, reason)

func _on_spire_hijacked(spire_id: String, new_team: int, hijacker: Unit) -> void:
    """Handle spire hijacking"""
    
    var spire = active_spires.get(spire_id, null)
    if spire:
        # Update team counts
        team_counts[spire.get("original_team")]["spires"] -= 1
        team_counts[new_team]["spires"] += 1
        
        if logger:
            logger.info("EntityManager", "Spire %s hijacked by team %d (unit %s)" % [spire_id, new_team, hijacker.unit_id])

# Public query methods
func get_entity_counts_for_team(team_id: int) -> Dictionary:
    """Get entity counts for a team"""
    return team_counts.get(team_id, {"mines": 0, "spires": 0})

func get_tile_occupant(tile_pos: Vector2i) -> String:
    """Get entity occupying a tile"""
    return tile_occupation.get(tile_pos, "")

func is_tile_occupied(tile_pos: Vector2i) -> bool:
    """Check if tile is occupied"""
    return tile_pos in tile_occupation

func get_all_entities() -> Dictionary:
    """Get all active entities"""
    return {
        "mines": active_mines,
        "spires": active_spires
    }

func get_entities_for_team(team_id: int) -> Dictionary:
    """Get all entities for a specific team"""
    var team_entities = {
        "mines": {},
        "spires": {}
    }
    
    for mine_id in active_mines:
        var mine = active_mines[mine_id]
        if mine and mine.get("team_id") == team_id:
            team_entities.mines[mine_id] = mine
    
    for spire_id in active_spires:
        var spire = active_spires[spire_id]
        if spire and spire.get("team_id") == team_id:
            team_entities.spires[spire_id] = spire
    
    return team_entities

func get_entity_statistics() -> Dictionary:
    """Get entity statistics"""
    return {
        "total_entities": active_mines.size() + active_spires.size(),
        "active_mines": active_mines.size(),
        "active_spires": active_spires.size(),
        "team_counts": team_counts,
        "tile_occupation": tile_occupation.size(),
        "placement_restrictions": placement_restrictions.size()
    }

# Administrative methods
func set_team_limit(entity_type: String, limit: int) -> void:
    """Set team limit for entity type"""
    
    if entity_type in team_limits:
        team_limits[entity_type] = limit

func add_placement_restriction(tile_pos: Vector2i, restriction_type: String) -> void:
    """Add placement restriction to tile"""
    
    placement_restrictions[tile_pos] = restriction_type

func remove_placement_restriction(tile_pos: Vector2i) -> void:
    """Remove placement restriction from tile"""
    
    if tile_pos in placement_restrictions:
        placement_restrictions.erase(tile_pos)

func clear_all_entities() -> void:
    """Clear all entities (for testing/reset)"""
    
    # Clear mines
    for mine_id in active_mines:
        var mine = active_mines[mine_id]
        if mine:
            mine.queue_free()
    active_mines.clear()
    
    # Clear spires
    for spire_id in active_spires:
        var spire = active_spires[spire_id]
        if spire:
            spire.queue_free()
    active_spires.clear()
    
    # Reset counts and occupation
    for team_id in team_counts:
        team_counts[team_id] = {"mines": 0, "spires": 0}
    tile_occupation.clear()
    
    if logger:
        logger.info("EntityManager", "All entities cleared")

# Helper methods for checking entity limits
func get_team_mine_count(team_id: int) -> int:
    """Get the current number of mines for a team"""
    if team_id in team_counts:
        return team_counts[team_id].get("mines", 0)
    return 0

func get_mine_limit() -> int:
    """Get the maximum number of mines allowed per team"""
    return team_limits.get("mines", 10)

func get_team_spire_count(team_id: int) -> int:
    """Get the current number of spires for a team"""
    if team_id in team_counts:
        return team_counts[team_id].get("spires", 0)
    return 0

func get_spire_limit() -> int:
    """Get the maximum number of spires allowed per team"""
    return team_limits.get("spires", 3) 