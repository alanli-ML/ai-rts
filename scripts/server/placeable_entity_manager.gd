# PlaceableEntityManager.gd
class_name PlaceableEntityManager
extends Node

const BuildingScene = preload("res://scripts/gameplay/building_entity.gd")
const MineScene = preload("res://scripts/gameplay/mine.gd")

var buildings: Dictionary = {} # building_id -> BuildingEntity
var building_counter: int = 0
var mines: Dictionary = {} # mine_id -> Mine
var mine_counter: int = 0

# Dependencies
var logger

func setup(p_logger):
    logger = p_logger
    logger.info("PlaceableEntityManager", "Setup complete.")

func spawn_building(building_type: String, position: Vector3, team_id: int) -> Node:
    building_counter += 1
    var building_id = "bld_%d" % building_counter
    
    var building = BuildingScene.new()
    building.name = building_id
    building.building_id = building_id
    building.building_type = building_type
    building.team_id = team_id
    building.global_position = position
    
    # Add to a dedicated container in the scene tree for organization
    var buildings_container = get_tree().get_root().find_child("Buildings", true, false)
    if not buildings_container:
        buildings_container = Node3D.new()
        buildings_container.name = "Buildings"
        get_tree().get_root().add_child(buildings_container)
        
    buildings_container.add_child(building)
    
    buildings[building_id] = building
    logger.info("PlaceableEntityManager", "Spawned building '%s' of type '%s' at %s" % [building_id, building_type, position])
    
    return building

func get_building(building_id: String) -> Node:
    return buildings.get(building_id)

func detonate_mine(mine_id: String, target_unit: Unit):
    if not mines.has(mine_id): return
    
    var mine = mines[mine_id]
    if not is_instance_valid(mine): return

    logger.info("PlaceableEntityManager", "Mine %s detonated on unit %s." % [mine_id, target_unit.unit_id])
    target_unit.take_damage(mine.damage)

    # Broadcast explosion effect to clients
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if root_node:
        # RPC call to all peers to spawn the effect
        root_node.rpc("spawn_impact_effect_rpc", mine.global_position)
    
    # Remove mine from server state
    mines.erase(mine_id)
    mine.queue_free()

func spawn_mine(position: Vector3, team_id: int) -> Node:
    mine_counter += 1
    var mine_id = "mine_%d" % mine_counter

    var mine = MineScene.new()
    mine.name = mine_id
    mine.mine_id = mine_id
    mine.team_id = team_id
    mine.global_position = position

    var mines_container = get_tree().get_root().find_child("Mines", true, false)
    if not mines_container:
        mines_container = Node3D.new()
        mines_container.name = "Mines"
        get_tree().get_root().add_child(mines_container)
        
    mines_container.add_child(mine)
    
    mines[mine_id] = mine
    logger.info("PlaceableEntityManager", "Spawned mine '%s' at %s" % [mine_id, position])
    
    return mine

func get_all_buildings_data() -> Array:
    var all_data = []
    for building_id in buildings:
        var building = buildings[building_id]
        if is_instance_valid(building) and building.has_method("get_building_info"):
            all_data.append(building.get_building_info())
    return all_data

func get_all_mines_data() -> Array:
    var all_data = []
    for mine_id in mines:
        var mine = mines[mine_id]
        if is_instance_valid(mine):
            all_data.append({
                "id": mine.mine_id,
                "team_id": mine.team_id,
                "position": { "x": mine.global_position.x, "y": mine.global_position.y, "z": mine.global_position.z }
            })
    return all_data