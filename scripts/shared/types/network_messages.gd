# NetworkMessages.gd - Shared network message structures (not an autoload)

# Base message class
class NetworkMessage:
    var timestamp: float
    var sender_id: int
    var message_type: String
    
    func _init(type: String, sender: int = -1):
        message_type = type
        sender_id = sender
        timestamp = Time.get_ticks_msec()
    
    func to_dict() -> Dictionary:
        return {
            "timestamp": timestamp,
            "sender_id": sender_id,
            "message_type": message_type
        }

# Map generation messages
class MapGenerationMessage extends NetworkMessage:
    var map_seed: int
    var map_size: Vector2i
    var tile_size: float
    var districts: Array
    var roads: Array
    var buildings: Array
    var control_points: Array
    var spawn_points: Dictionary
    var metadata: Dictionary
    
    func _init(seed: int, size: Vector2i, tile_sz: float):
        super._init("map_generation")
        map_seed = seed
        map_size = size
        tile_size = tile_sz
        districts = []
        roads = []
        buildings = []
        control_points = []
        spawn_points = {}
        metadata = {}
    
    func to_dict() -> Dictionary:
        var dict = super.to_dict()
        dict["map_seed"] = map_seed
        dict["map_size"] = [map_size.x, map_size.y]
        dict["tile_size"] = tile_size
        dict["districts"] = districts
        dict["roads"] = roads
        dict["buildings"] = buildings
        dict["control_points"] = control_points
        dict["spawn_points"] = spawn_points
        dict["metadata"] = metadata
        return dict

# Individual placement data structures
class DistrictData:
    var district_id: String
    var center_position: Vector2i
    var district_type: int  # 0=Commercial, 1=Industrial, 2=Mixed, etc.
    var bounds: Dictionary  # {x, y, width, height}
    var strategic_value: int
    var team_color_override: int  # -1 for none, 0+ for team colors
    
    func _init(id: String, center: Vector2i, type: int):
        district_id = id
        center_position = center
        district_type = type
        bounds = {}
        strategic_value = 1
        team_color_override = -1
    
    func to_dict() -> Dictionary:
        return {
            "district_id": district_id,
            "center_position": [center_position.x, center_position.y],
            "district_type": district_type,
            "bounds": bounds,
            "strategic_value": strategic_value,
            "team_color_override": team_color_override
        }

class RoadPlacement:
    var position: Vector2i
    var asset_name: String
    var rotation_degrees: float
    var road_type: String  # "main_road", "street", "intersection"
    var connections: Array  # Array of connected road positions
    var lod_level: int  # 0=High, 1=Medium, 2=Low
    
    func _init(pos: Vector2i, asset: String, rotation: float = 0.0):
        position = pos
        asset_name = asset
        rotation_degrees = rotation
        road_type = "street"
        connections = []
        lod_level = 0
    
    func to_dict() -> Dictionary:
        return {
            "position": [position.x, position.y],
            "asset_name": asset_name,
            "rotation_degrees": rotation_degrees,
            "road_type": road_type,
            "connections": connections,
            "lod_level": lod_level
        }

class BuildingPlacement:
    var position: Vector2i
    var asset_name: String
    var rotation_degrees: float
    var building_type: String
    var scale: Vector3
    var district_id: String
    var lod_level: int
    var team_affiliation: int  # -1 for neutral, 0+ for team-specific
    
    func _init(pos: Vector2i, asset: String, type: String):
        position = pos
        asset_name = asset
        building_type = type
        rotation_degrees = 0.0
        scale = Vector3.ONE
        district_id = ""
        lod_level = 0
        team_affiliation = -1
    
    func to_dict() -> Dictionary:
        return {
            "position": [position.x, position.y],
            "asset_name": asset_name,
            "rotation_degrees": rotation_degrees,
            "building_type": building_type,
            "scale": [scale.x, scale.y, scale.z],
            "district_id": district_id,
            "lod_level": lod_level,
            "team_affiliation": team_affiliation
        }

class ControlPointData:
    var control_point_id: String
    var world_position: Vector3
    var district_id: String
    var strategic_value: int
    var capture_radius: float
    var initial_state: int  # 0=Neutral, 1=Team1, 2=Team2
    var visual_overrides: Dictionary  # Custom visual properties
    
    func _init(id: String, pos: Vector3, district: String):
        control_point_id = id
        world_position = pos
        district_id = district
        strategic_value = 1
        capture_radius = 5.0
        initial_state = 0
        visual_overrides = {}
    
    func to_dict() -> Dictionary:
        return {
            "control_point_id": control_point_id,
            "world_position": [world_position.x, world_position.y, world_position.z],
            "district_id": district_id,
            "strategic_value": strategic_value,
            "capture_radius": capture_radius,
            "initial_state": initial_state,
            "visual_overrides": visual_overrides
        }

class SpawnPointData:
    var team_id: int
    var positions: Array  # Array of Vector3 positions
    var spawn_type: String  # "building", "district", "fixed"
    var associated_building: String  # Building ID if spawn_type is "building"
    
    func _init(team: int, spawn_positions: Array):
        team_id = team
        positions = spawn_positions
        spawn_type = "fixed"
        associated_building = ""
    
    func to_dict() -> Dictionary:
        var pos_arrays = []
        for pos in positions:
            pos_arrays.append([pos.x, pos.y, pos.z])
        
        return {
            "team_id": team_id,
            "positions": pos_arrays,
            "spawn_type": spawn_type,
            "associated_building": associated_building
        }

# Player connection messages
class PlayerJoinMessage extends NetworkMessage:
    var player_name: String
    var team_id: int
    
    func _init(name: String, team: int = 0):
        super._init("player_join")
        player_name = name
        team_id = team
    
    func to_dict() -> Dictionary:
        var dict = super.to_dict()
        dict["player_name"] = player_name
        dict["team_id"] = team_id
        return dict

class PlayerLeaveMessage extends NetworkMessage:
    var player_id: int
    var reason: String
    
    func _init(id: int, leave_reason: String = ""):
        super._init("player_leave")
        player_id = id
        reason = leave_reason
    
    func to_dict() -> Dictionary:
        var dict = super.to_dict()
        dict["player_id"] = player_id
        dict["reason"] = reason
        return dict

# Game state messages
class GameStateMessage extends NetworkMessage:
    var units: Array
    var buildings: Array
    var resources: Dictionary
    var match_state: String
    var game_time: float
    
    func _init():
        super._init("game_state")
        units = []
        buildings = []
        resources = {}
        match_state = "active"
        game_time = 0.0
    
    func to_dict() -> Dictionary:
        var dict = super.to_dict()
        dict["units"] = units
        dict["buildings"] = buildings
        dict["resources"] = resources
        dict["match_state"] = match_state
        dict["game_time"] = game_time
        return dict

# Unit command messages
class UnitCommandMessage extends NetworkMessage:
    var command_type: String
    var unit_ids: Array
    var target_position: Vector3
    var target_id: String
    var parameters: Dictionary
    
    func _init(cmd_type: String, units: Array = []):
        super._init("unit_command")
        command_type = cmd_type
        unit_ids = units
        target_position = Vector3.ZERO
        target_id = ""
        parameters = {}
    
    func to_dict() -> Dictionary:
        var dict = super.to_dict()
        dict["command_type"] = command_type
        dict["unit_ids"] = unit_ids
        dict["target_position"] = [target_position.x, target_position.y, target_position.z]
        dict["target_id"] = target_id
        dict["parameters"] = parameters
        return dict

# AI command messages
class AICommandMessage extends NetworkMessage:
    var command_text: String
    var selected_units: Array
    var game_context: Dictionary
    
    func _init(text: String, units: Array = []):
        super._init("ai_command")
        command_text = text
        selected_units = units
        game_context = {}
    
    func to_dict() -> Dictionary:
        var dict = super.to_dict()
        dict["command_text"] = command_text
        dict["selected_units"] = selected_units
        dict["game_context"] = game_context
        return dict

# Unit spawn messages
class UnitSpawnMessage extends NetworkMessage:
    var unit_type: String
    var team_id: int
    var position: Vector3
    var unit_id: String
    
    func _init(type: String, team: int, pos: Vector3, id: String):
        super._init("unit_spawn")
        unit_type = type
        team_id = team
        position = pos
        unit_id = id
    
    func to_dict() -> Dictionary:
        var dict = super.to_dict()
        dict["unit_type"] = unit_type
        dict["team_id"] = team_id
        dict["position"] = [position.x, position.y, position.z]
        dict["unit_id"] = unit_id
        return dict

# Match result messages
class MatchResultMessage extends NetworkMessage:
    var winner_team: int
    var match_duration: float
    var final_scores: Dictionary
    
    func _init(winner: int, duration: float):
        super._init("match_result")
        winner_team = winner
        match_duration = duration
        final_scores = {}
    
    func to_dict() -> Dictionary:
        var dict = super.to_dict()
        dict["winner_team"] = winner_team
        dict["match_duration"] = match_duration
        dict["final_scores"] = final_scores
        return dict

# Chat messages
class ChatMessage extends NetworkMessage:
    var message: String
    var channel: String
    var recipient_id: int
    
    func _init(msg: String, chat_channel: String = "all", recipient: int = -1):
        super._init("chat")
        message = msg
        channel = chat_channel
        recipient_id = recipient
    
    func to_dict() -> Dictionary:
        var dict = super.to_dict()
        dict["message"] = message
        dict["channel"] = channel
        dict["recipient_id"] = recipient_id
        return dict

# Static utility functions for message handling
static func create_player_join_message(name: String, team: int = 0) -> PlayerJoinMessage:
    return PlayerJoinMessage.new(name, team)

static func create_unit_command_message(cmd_type: String, units: Array = []) -> UnitCommandMessage:
    return UnitCommandMessage.new(cmd_type, units)

static func create_ai_command_message(text: String, units: Array = []) -> AICommandMessage:
    return AICommandMessage.new(text, units)

static func create_game_state_message() -> GameStateMessage:
    return GameStateMessage.new()

static func create_match_result_message(winner: int, duration: float) -> MatchResultMessage:
    return MatchResultMessage.new(winner, duration)

static func create_map_generation_message(seed: int, size: Vector2i, tile_size: float) -> MapGenerationMessage:
    return MapGenerationMessage.new(seed, size, tile_size)

static func parse_message_from_dict(data: Dictionary) -> NetworkMessage:
    var msg_type = data.get("message_type", "")
    
    match msg_type:
        "player_join":
            var msg = PlayerJoinMessage.new(data.get("player_name", ""), data.get("team_id", 0))
            msg.timestamp = data.get("timestamp", 0.0)
            msg.sender_id = data.get("sender_id", -1)
            return msg
        "unit_command":
            var msg = UnitCommandMessage.new(data.get("command_type", ""), data.get("unit_ids", []))
            msg.timestamp = data.get("timestamp", 0.0)
            msg.sender_id = data.get("sender_id", -1)
            var pos_array = data.get("target_position", [0, 0, 0])
            msg.target_position = Vector3(pos_array[0], pos_array[1], pos_array[2])
            msg.target_id = data.get("target_id", "")
            msg.parameters = data.get("parameters", {})
            return msg
        "ai_command":
            var msg = AICommandMessage.new(data.get("command_text", ""), data.get("selected_units", []))
            msg.timestamp = data.get("timestamp", 0.0)
            msg.sender_id = data.get("sender_id", -1)
            msg.game_context = data.get("game_context", {})
            return msg
        "map_generation":
            var size_array = data.get("map_size", [20, 20])
            var msg = MapGenerationMessage.new(data.get("map_seed", 0), Vector2i(size_array[0], size_array[1]), data.get("tile_size", 3.0))
            msg.timestamp = data.get("timestamp", 0.0)
            msg.sender_id = data.get("sender_id", -1)
            msg.districts = data.get("districts", [])
            msg.roads = data.get("roads", [])
            msg.buildings = data.get("buildings", [])
            msg.control_points = data.get("control_points", [])
            msg.spawn_points = data.get("spawn_points", {})
            msg.metadata = data.get("metadata", {})
            return msg
        _:
            var msg = NetworkMessage.new(msg_type)
            msg.timestamp = data.get("timestamp", 0.0)
            msg.sender_id = data.get("sender_id", -1)
            return msg 