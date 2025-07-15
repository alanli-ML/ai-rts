# TileSystem.gd - Grid-based tile management system for procedural generation
class_name TileSystem
extends Node

# Grid configuration
var grid_size: Vector2i = Vector2i(20, 20)
var tile_size: float = 3.0
var tile_grid: Array = []

# Dependencies
var logger

func _ready() -> void:
    pass

func setup(logger_ref, size: Vector2i, tile_size_ref: float) -> void:
    """Setup the tile system with dependencies"""
    logger = logger_ref
    grid_size = size
    tile_size = tile_size_ref
    
    if logger:
        logger.info("TileSystem", "Tile system initialized with grid size: %s, tile size: %.1f" % [grid_size, tile_size])

func initialize_grid() -> void:
    """Initialize the tile grid"""
    tile_grid = []
    for x in range(grid_size.x):
        var row = []
        for y in range(grid_size.y):
            row.append({
                "position": Vector2i(x, y),
                "world_position": tile_to_world(Vector2i(x, y)),
                "type": "empty",
                "asset_data": {}
            })
        tile_grid.append(row)
    
    if logger:
        logger.info("TileSystem", "Grid initialized with %d tiles" % (grid_size.x * grid_size.y))

func world_to_tile(world_pos: Vector3) -> Vector2i:
    """Convert world position to tile coordinates (centered grid)"""
    var center_offset = Vector2i(grid_size.x / 2, grid_size.y / 2)
    return Vector2i(
        int(world_pos.x / tile_size) + center_offset.x,
        int(world_pos.z / tile_size) + center_offset.y
    )

func tile_to_world(tile_pos: Vector2i) -> Vector3:
    """Convert tile coordinates to world position (centered grid)"""
    var center_offset = Vector2i(grid_size.x / 2, grid_size.y / 2)
    return Vector3(
        (tile_pos.x - center_offset.x) * tile_size,
        0,
        (tile_pos.y - center_offset.y) * tile_size
    )

func set_tile(tile_pos: Vector2i, tile_type: String, asset_data: Dictionary = {}) -> bool:
    """Set tile type and associated data"""
    if tile_pos.x >= 0 and tile_pos.x < grid_size.x and tile_pos.y >= 0 and tile_pos.y < grid_size.y:
        tile_grid[tile_pos.x][tile_pos.y]["type"] = tile_type
        tile_grid[tile_pos.x][tile_pos.y]["asset_data"] = asset_data
        return true
    return false

func get_tile(tile_pos: Vector2i) -> Dictionary:
    """Get tile data at position"""
    if tile_pos.x >= 0 and tile_pos.x < grid_size.x and tile_pos.y >= 0 and tile_pos.y < grid_size.y:
        return tile_grid[tile_pos.x][tile_pos.y]
    return {}

func is_tile_empty(tile_pos: Vector2i) -> bool:
    """Check if tile is empty"""
    var tile_data = get_tile(tile_pos)
    return tile_data.get("type", "") == "empty"

func get_neighbors(tile_pos: Vector2i) -> Array:
    """Get neighboring tiles"""
    var neighbors = []
    var directions = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
    
    for direction in directions:
        var neighbor_pos = tile_pos + direction
        if neighbor_pos.x >= 0 and neighbor_pos.x < grid_size.x and neighbor_pos.y >= 0 and neighbor_pos.y < grid_size.y:
            neighbors.append(get_tile(neighbor_pos))
    
    return neighbors 