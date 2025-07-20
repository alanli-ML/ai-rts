# GameConstants.gd - Shared constants (not an autoload)

# Debug configuration
const DEBUG_ENABLED: bool = false
const DEBUG_UNITS: bool = false
const DEBUG_ANIMATIONS: bool = false
const DEBUG_SELECTION: bool = false
const DEBUG_WEAPONS: bool = false
const DEBUG_NAVIGATION: bool = false
const DEBUG_AI: bool = false
const DEBUG_NETWORK: bool = false

# Debug utility function
static func debug_print(message: String, category: String = "GENERAL") -> void:
    if not DEBUG_ENABLED:
        return
        
    match category.to_upper():
        "UNITS":
            if DEBUG_UNITS:
                print("DEBUG: %s" % message)
        "ANIMATIONS":
            if DEBUG_ANIMATIONS:
                print("DEBUG: %s" % message)
        "SELECTION":
            if DEBUG_SELECTION:
                print("DEBUG: %s" % message)
        "WEAPONS":
            if DEBUG_WEAPONS:
                print("DEBUG: %s" % message)
        "NAVIGATION":
            if DEBUG_NAVIGATION:
                print("DEBUG: %s" % message)
        "AI":
            if DEBUG_AI:
                print("DEBUG: %s" % message)
        "NETWORK":
            if DEBUG_NETWORK:
                print("DEBUG: %s" % message)
        _:
            print("DEBUG: %s" % message)

# Game balance constants
const TICK_RATE: int = 60
const NETWORK_TICK_RATE: int = 30
const MAX_PLAYERS: int = 4
const MAX_UNITS_PER_PLAYER: int = 50

# Unit selection
const UNIT_SELECTION_RADIUS: float = 1.0
const MULTI_SELECT_RADIUS: float = 0.5

# Combat constants
const DAMAGE_VARIANCE: float = 0.1
const CRITICAL_HIT_CHANCE: float = 0.05
const CRITICAL_HIT_MULTIPLIER: float = 2.0

# Movement constants
const MOVEMENT_TOLERANCE: float = 0.1
const PATHFINDING_MARGIN: float = 0.5

# AI constants
const AI_THINK_INTERVAL: float = 0.5
const AI_RESPONSE_TIMEOUT: float = 10.0
const MAX_AI_COMMAND_LENGTH: int = 500

# Network constants
const NETWORK_TIMEOUT: float = 5.0
const RECONNECT_ATTEMPTS: int = 3
const PING_INTERVAL: float = 1.0

# Building constants
const MAX_BUILDINGS_PER_PLAYER: int = 20
const BUILDING_PLACEMENT_RADIUS: float = 2.0
const BUILDING_CONSTRUCTION_RANGE: float = 5.0

# Respawn constants
const UNIT_RESPAWN_TIME: float = 30.0
const RESPAWN_INVULNERABILITY_TIME: float = 3.0
const RESPAWN_OFFSET_RADIUS: float = 5.0

# Unit configurations
const UNIT_CONFIGS: Dictionary = {
    "scout": {
        "health": 80,
        "speed": 6.0,
        "damage": 20,
        "range": 10.0,
        "vision": 20.0,
        "cost": 50,
        "build_time": 5.0
    },
    "sniper": {
        "health": 80,
        "speed": 4.0,
        "damage": 35,
        "range": 20.0,
        "vision": 32.0,
        "cost": 75,
        "build_time": 8.0
    },
    "tank": {
        "health": 300,
        "speed": 3.0,
        "damage": 20,
        "range": 6.0,
        "vision": 24.0,
        "cost": 200,
        "build_time": 20.0
    },
    "medic": {
        "health": 100,
        "speed": 4.5,
        "damage": 10,
        "range": 6.0,
        "vision": 24.0,
        "cost": 100,
        "build_time": 12.0,
        "heal_rate": 10.0
    },
    "engineer": {
        "health": 90,
        "speed": 4.0,
        "damage": 15,
        "range": 6.0,
        "vision": 12.0,
        "cost": 80,
        "build_time": 10.0
    },
    "turret": {
        "health": 150,
        "speed": 0.0,
        "damage": 15,
        "range": 15.0,
        "vision": 15.0,
        "cost": 100,
        "build_time": 5.0
    }
}


# Default behavior matrices by unit archetype (NEW SYSTEM)
# Uses correct variable names from ActionValidator.DEFINED_STATE_VARIABLES
const DEFAULT_BEHAVIOR_MATRICES: Dictionary = {
    "scout": {
        "attack": {
            "enemies_in_range": 0.8, "current_health": 0.3, "under_attack": -0.2,
            "allies_in_range": 0.2, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.4,
            "ally_nodes_controlled": -0.2, "bias": 0.0
        },
        "retreat": {
            "enemies_in_range": 0.4, "current_health": -0.7, "under_attack": 0.9,
            "allies_in_range": -0.3, "ally_low_health": -0.2, "enemy_nodes_controlled": 0.2,
            "ally_nodes_controlled": 0.0, "bias": 0.0
        },
        "defend": {
            "enemies_in_range": -0.3, "current_health": 0.2, "under_attack": -0.4,
            "allies_in_range": 0.3, "ally_low_health": 0.1, "enemy_nodes_controlled": -0.4,
            "ally_nodes_controlled": 0.6, "bias": 0.0
        },
        "follow": {
            "enemies_in_range": -0.2, "current_health": -0.1, "under_attack": -0.3,
            "allies_in_range": 0.6, "ally_low_health": 0.2, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": 0.0
        },
        "activate_stealth": {
            "enemies_in_range": 0.9, "current_health": -0.4, "under_attack": 0.8,
            "allies_in_range": -0.2, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": -0.2
        },
        "find_cover": {
            "enemies_in_range": 0.3, "current_health": -0.5, "under_attack": 0.7,
            "allies_in_range": 0.0, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": -0.7
        }
    },
    "tank": {
        "attack": {
            "enemies_in_range": 0.9, "current_health": 0.2, "under_attack": 0.1,
            "allies_in_range": 0.3, "ally_low_health": 0.1, "enemy_nodes_controlled": 0.5,
            "ally_nodes_controlled": -0.2, "bias": 0.0
        },
        "retreat": {
            "enemies_in_range": 0.2, "current_health": -0.8, "under_attack": 0.3,
            "allies_in_range": -0.2, "ally_low_health": -0.3, "enemy_nodes_controlled": 0.1,
            "ally_nodes_controlled": 0.0, "bias": 0.0
        },
        "defend": {
            "enemies_in_range": -0.2, "current_health": 0.3, "under_attack": -0.3,
            "allies_in_range": 0.4, "ally_low_health": 0.2, "enemy_nodes_controlled": -0.5,
            "ally_nodes_controlled": 0.7, "bias": 0.0
        },
        "follow": {
            "enemies_in_range": -0.1, "current_health": -0.3, "under_attack": -0.2,
            "allies_in_range": 0.5, "ally_low_health": 0.3, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": 0.0
        },
        "activate_shield": {
            "enemies_in_range": 0.9, "current_health": -0.2, "under_attack": 0.7,
            "allies_in_range": 0.0, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": -0.2
        },
        "taunt_enemies": {
            "enemies_in_range": 0.7, "current_health": 0.5, "under_attack": 0.2,
            "allies_in_range": 0.5, "ally_low_health": 0.4, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": -0.8
        },
        "find_cover": {
            "enemies_in_range": 0.2, "current_health": -0.6, "under_attack": 0.5,
            "allies_in_range": 0.0, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": -0.8
        }
    },
    "sniper": {
        "attack": {
            "enemies_in_range": 0.3, "current_health": 0.5, "under_attack": -0.6,
            "allies_in_range": 0.1, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.3,
            "ally_nodes_controlled": -0.1, "bias": 0.0
        },
        "retreat": {
            "enemies_in_range": 0.8, "current_health": -0.6, "under_attack": 0.9,
            "allies_in_range": -0.4, "ally_low_health": -0.2, "enemy_nodes_controlled": 0.2,
            "ally_nodes_controlled": 0.0, "bias": 0.0
        },
        "defend": {
            "enemies_in_range": -0.4, "current_health": 0.2, "under_attack": -0.5,
            "allies_in_range": 0.2, "ally_low_health": 0.1, "enemy_nodes_controlled": -0.3,
            "ally_nodes_controlled": 0.5, "bias": 0.0
        },
        "follow": {
            "enemies_in_range": -0.3, "current_health": -0.4, "under_attack": -0.4,
            "allies_in_range": 0.4, "ally_low_health": 0.2, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": 0.0
        },
        "charge_shot": {
            "enemies_in_range": 0.7, "current_health": 0.3, "under_attack": -0.4,
            "allies_in_range": 0.0, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": -0.6
        },
        "find_cover": {
            "enemies_in_range": 0.6, "current_health": -0.5, "under_attack": 0.8,
            "allies_in_range": 0.0, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": -0.6
        }
    },
    "medic": {
        "attack": {
            "enemies_in_range": 0.2, "current_health": 0.3, "under_attack": -0.3,
            "allies_in_range": 0.3, "ally_low_health": -0.2, "enemy_nodes_controlled": 0.2,
            "ally_nodes_controlled": -0.1, "bias": 0.0
        },
        "retreat": {
            "enemies_in_range": 0.7, "current_health": -0.7, "under_attack": 0.9,
            "allies_in_range": -0.4, "ally_low_health": -0.3, "enemy_nodes_controlled": 0.2,
            "ally_nodes_controlled": 0.0, "bias": 0.0
        },
        "defend": {
            "enemies_in_range": -0.4, "current_health": 0.2, "under_attack": -0.4,
            "allies_in_range": 0.6, "ally_low_health": 0.3, "enemy_nodes_controlled": -0.2,
            "ally_nodes_controlled": 0.4, "bias": 0.0
        },
        "follow": {
            "enemies_in_range": -0.2, "current_health": 0.0, "under_attack": -0.3,
            "allies_in_range": 0.8, "ally_low_health": 0.7, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": 0.0
        },
        "heal_ally": {
            "enemies_in_range": 0.1, "current_health": 0.2, "under_attack": -0.1,
            "allies_in_range": 1.0, "ally_low_health": 2.2, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": 0.0
        },
        "find_cover": {
            "enemies_in_range": 0.6, "current_health": -0.4, "under_attack": 0.8,
            "allies_in_range": 0.0, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": -0.7
        }
    },
    "engineer": {
        "attack": {
            "enemies_in_range": 0.6, "current_health": 0.4, "under_attack": -0.2,
            "allies_in_range": 0.2, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.3,
            "ally_nodes_controlled": -0.1, "bias": 0.0
        },
        "retreat": {
            "enemies_in_range": 0.5, "current_health": -0.7, "under_attack": 0.8,
            "allies_in_range": -0.3, "ally_low_health": -0.2, "enemy_nodes_controlled": 0.1,
            "ally_nodes_controlled": 0.0, "bias": 0.0
        },
        "defend": {
            "enemies_in_range": -0.3, "current_health": 0.3, "under_attack": -0.4,
            "allies_in_range": 0.4, "ally_low_health": 0.2, "enemy_nodes_controlled": -0.6,
            "ally_nodes_controlled": 0.8, "bias": 0.0
        },
        "follow": {
            "enemies_in_range": -0.2, "current_health": -0.2, "under_attack": -0.4,
            "allies_in_range": 0.5, "ally_low_health": 0.3, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": 0.0
        },
        "construct_turret": {
            "enemies_in_range": 0.3, "current_health": 0.4, "under_attack": -0.5,
            "allies_in_range": 0.3, "ally_low_health": 0.3, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.8, "bias": -0.4
        },
        "repair": {
            "enemies_in_range": -0.4, "current_health": 0.0, "under_attack": -0.3,
            "allies_in_range": 0.5, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.2, "bias": -0.7
        },
        "lay_mines": {
            "enemies_in_range": -0.5, "current_health": 0.0, "under_attack": -0.3,
            "allies_in_range": 0.0, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.3,
            "ally_nodes_controlled": 0.4, "bias": -0.8
        },
        "find_cover": {
            "enemies_in_range": 0.4, "current_health": -0.5, "under_attack": 0.7,
            "allies_in_range": 0.0, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": -0.7
        }
    },
    "general": {
        "attack": {
            "enemies_in_range": 0.7, "current_health": 0.3, "under_attack": 0.0,
            "allies_in_range": 0.2, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.3,
            "ally_nodes_controlled": -0.1, "bias": 0.0
        },
        "retreat": {
            "enemies_in_range": 0.4, "current_health": -0.6, "under_attack": 0.8,
            "allies_in_range": -0.3, "ally_low_health": -0.2, "enemy_nodes_controlled": 0.1,
            "ally_nodes_controlled": 0.0, "bias": 0.0
        },
        "defend": {
            "enemies_in_range": -0.3, "current_health": 0.2, "under_attack": -0.3,
            "allies_in_range": 0.3, "ally_low_health": 0.1, "enemy_nodes_controlled": -0.3,
            "ally_nodes_controlled": 0.6, "bias": 0.0
        },
        "follow": {
            "enemies_in_range": -0.2, "current_health": -0.2, "under_attack": -0.3,
            "allies_in_range": 0.5, "ally_low_health": 0.2, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": 0.0
        },
        "find_cover": {
            "enemies_in_range": 0.3, "current_health": -0.4, "under_attack": 0.6,
            "allies_in_range": 0.0, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.0,
            "ally_nodes_controlled": 0.0, "bias": -0.7
        }
    }
}

# Building configurations
const BUILDING_CONFIGS: Dictionary = {
    "power_spire": {
        "health": 500,
        "cost": 300,
        "construction_time": 30.0,
        "power_generation": 50,
        "power_consumption": 0,
        "range": 15.0
    },
    "defense_tower": {
        "health": 400,
        "cost": 250,
        "construction_time": 25.0,
        "power_generation": 0,
        "power_consumption": 20,
        "damage": 60,
        "range": 12.0,
        "attack_speed": 1.5
    },
    "relay_pad": {
        "health": 200,
        "cost": 150,
        "construction_time": 15.0,
        "power_generation": 0,
        "power_consumption": 30,
        "teleport_range": 20.0,
        "teleport_cooldown": 10.0
    }
}

# Map constants
const MAP_SIZE: Vector2 = Vector2(100, 100)
const CONTROL_POINT_COUNT: int = 9
const CONTROL_POINT_RADIUS: float = 5.0
const CONTROL_POINT_CAPTURE_TIME: float = 10.0

# Victory conditions
const VICTORY_POINTS_TO_WIN: int = 1000
const CONTROL_POINT_VICTORY_THRESHOLD: int = 7
const ELIMINATION_VICTORY_ENABLED: bool = true

# Resource constants
const STARTING_RESOURCES: Dictionary = {
    "energy": 500,
    "minerals": 300
}

const RESOURCE_TICK_RATE: float = 1.0
const RESOURCE_PER_TICK: Dictionary = {
    "energy": 10,
    "minerals": 5
}

# Resource management system constants
const STARTING_ENERGY: int = 1000
const STARTING_MATERIALS: int = 500
const STARTING_RESEARCH: int = 0

const BASE_ENERGY_INCOME: float = 5.0
const BASE_MATERIAL_INCOME: float = 2.0
const BASE_RESEARCH_INCOME: float = 1.0

const MAX_ENERGY_STORAGE: int = 5000
const MAX_MATERIAL_STORAGE: int = 3000
const MAX_RESEARCH_STORAGE: int = 1000

const RESOURCE_UPDATE_INTERVAL: float = 1.0

# UI constants
const UI_SCALE: float = 1.0
const MINIMAP_SIZE: Vector2 = Vector2(200, 200)
const CHAT_MAX_LINES: int = 50
const NOTIFICATION_DURATION: float = 3.0

# Voice/Speech constants
const SPEECH_BUBBLE_DURATION: float = 4.0
const SPEECH_BUBBLE_FADE_TIME: float = 0.5
const MAX_SPEECH_LENGTH: int = 100

# Static utility functions
static func get_unit_config(unit_type: String) -> Dictionary:
    return UNIT_CONFIGS.get(unit_type, {})

static func get_building_config(building_type: String) -> Dictionary:
    return BUILDING_CONFIGS.get(building_type, {})

static func is_valid_unit_type(unit_type: String) -> bool:
    return UNIT_CONFIGS.has(unit_type)

static func is_valid_building_type(building_type: String) -> bool:
    return BUILDING_CONFIGS.has(building_type)

static func get_default_behavior_matrix(unit_archetype: String) -> Dictionary:
    """Get the default behavior matrix for a specific unit archetype"""
    return DEFAULT_BEHAVIOR_MATRICES.get(unit_archetype, DEFAULT_BEHAVIOR_MATRICES.get("general", {}))

static func get_all_unit_archetypes() -> Array:
    return DEFAULT_BEHAVIOR_MATRICES.keys()