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
        _:
            var msg = NetworkMessage.new(msg_type)
            msg.timestamp = data.get("timestamp", 0.0)
            msg.sender_id = data.get("sender_id", -1)
            return msg 