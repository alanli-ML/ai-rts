# GameEnums.gd - Shared enums (not an autoload)

# Unit states
enum UnitState {
    IDLE,
    MOVING,
    ATTACKING,
    DEAD
}

# Unit types
enum UnitType {
    SCOUT,
    SOLDIER,
    TANK,
    MEDIC,
    ENGINEER
}

# Building types
enum BuildingType {
    POWER_SPIRE,
    DEFENSE_TOWER,
    RELAY_PAD
}

# Game phases
enum GamePhase {
    LOBBY,
    LOADING,
    ACTIVE,
    PAUSED,
    ENDED
}

# Command types
enum CommandType {
    MOVE,
    ATTACK,
    STOP,
    GUARD,
    PATROL,
    FOLLOW,
    HEAL,
    BUILD,
    SPECIAL
}

# Team IDs
enum TeamID {
    NEUTRAL = 0,
    TEAM_1 = 1,
    TEAM_2 = 2
}

# Network states
enum NetworkState {
    OFFLINE,
    CONNECTING,
    CONNECTED,
    IN_GAME,
    DISCONNECTED
}

# Match results
enum MatchResult {
    IN_PROGRESS,
    TEAM_1_WIN,
    TEAM_2_WIN,
    DRAW,
    ABANDONED
}

# Control point states
enum ControlPointState {
    NEUTRAL,
    CONTESTED,
    CONTROLLED
}

# AI plan types
enum PlanType {
    SIMPLE_COMMAND,
    MULTI_STEP_PLAN,
    CONDITIONAL_PLAN
}

# Static utility functions for string conversion
static func get_unit_state_string(state: UnitState) -> String:
    match state:
        UnitState.IDLE: return "IDLE"
        UnitState.MOVING: return "MOVING"
        UnitState.ATTACKING: return "ATTACKING"
        UnitState.DEAD: return "DEAD"
        _: return "UNKNOWN"

static func get_unit_type_string(type: UnitType) -> String:
    match type:
        UnitType.SCOUT: return "SCOUT"
        UnitType.SOLDIER: return "SOLDIER"
        UnitType.TANK: return "TANK"
        UnitType.MEDIC: return "MEDIC"
        UnitType.ENGINEER: return "ENGINEER"
        _: return "UNKNOWN"

static func get_building_type_string(type: BuildingType) -> String:
    match type:
        BuildingType.POWER_SPIRE: return "power_spire"
        BuildingType.DEFENSE_TOWER: return "defense_tower"
        BuildingType.RELAY_PAD: return "relay_pad"
        _: return "unknown"

static func get_command_type_string(type: CommandType) -> String:
    match type:
        CommandType.MOVE: return "MOVE"
        CommandType.ATTACK: return "ATTACK"
        CommandType.STOP: return "STOP"
        CommandType.GUARD: return "GUARD"
        CommandType.PATROL: return "PATROL"
        CommandType.FOLLOW: return "FOLLOW"
        CommandType.HEAL: return "HEAL"
        CommandType.BUILD: return "BUILD"
        CommandType.SPECIAL: return "SPECIAL"
        _: return "UNKNOWN" 