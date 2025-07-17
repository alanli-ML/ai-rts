# ConfigManager.gd
extends Node

# Game Constants
const GAME_VERSION = "0.1.0"
const MAX_PLAYERS = 2
const MAX_UNITS_PER_PLAYER = 10
const MATCH_TIME_LIMIT = 300.0  # 5 minutes
const SUDDEN_DEATH_TIME = 300.0

# Unit Constants
const UNIT_ARCHETYPES = {
    "scout": {
        "speed": 6.0,
        "health": 80.0,
        "vision_range": 20.0,
        "vision_angle": 120.0,
        "attack_range": 6.0,
        "attack_damage": 20.0,
        "cost": 50.0,
        "build_time": 5.0
    },
    "tank": {
        "speed": 2.0,
        "health": 300.0,
        "vision_range": 24.0,
        "vision_angle": 120.0,
        "attack_range": 10.0,
        "attack_damage": 80.0,
        "cost": 200.0,
        "build_time": 20.0
    },
    "sniper": {
        "speed": 4.0,
        "health": 120.0,
        "vision_range": 32.0,
        "vision_angle": 60.0,
        "attack_range": 3.0,
        "attack_damage": 35.0,
        "cost": 75.0,
        "build_time": 8.0
    },
    "medic": {
        "speed": 4.5,
        "health": 100.0,
        "vision_range": 16.0,
        "vision_angle": 120.0,
        "attack_range": 4.0,
        "attack_damage": 10.0,
        "heal_range": 30.0,
        "heal_rate": 10.0,
        "cost": 100.0,
        "build_time": 12.0
    },
    "engineer": {
        "speed": 4.0,
        "health": 90.0,
        "vision_range": 12.0,
        "vision_angle": 120.0,
        "attack_range": 4.0,
        "attack_damage": 15.0,
        "build_speed": 2.0,
        "cost": 80.0,
        "build_time": 10.0
    }
}

# Building Constants
const BUILDING_TYPES = {
    "power_spire": {
        "health": 500.0,
        "build_time": 10.0,
        "energy_generation": 10.0
    },
    "defense_tower": {
        "health": 300.0,
        "build_time": 8.0,
        "attack_range": 30.0,
        "attack_damage": 50.0
    },
    "relay_pad": {
        "health": 200.0,
        "build_time": 5.0,
        "heal_radius": 20.0,
        "heal_rate": 5.0
    }
}

# Network Constants
const DEFAULT_PORT = 7777
const MAX_LATENCY = 250  # ms
const LOCKSTEP_DELAY = 3  # frames

# AI Constants
const LLM_REQUEST_TIMEOUT = 5.0
const LLM_BATCH_SIZE = 32
const MAX_PLAN_STEPS = 3
const MAX_PLAN_DURATION = 6000  # ms
const SPEECH_MAX_WORDS = 12

# User Settings (loaded from file)
var user_settings: Dictionary = {
    "graphics_quality": "high",
    "master_volume": 0.8,
    "sfx_volume": 1.0,
    "music_volume": 0.6,
    "camera_sensitivity": 1.0,
    "edge_scroll_enabled": true,
    "openai_api_key": ""
}

# Runtime Config
var openai_api_key: String = ""
var server_url: String = "localhost"

func _ready() -> void:
    print("ConfigManager initialized")
    load_user_settings()
    
    # Load API key from environment if available
    if OS.has_environment("OPENAI_API_KEY"):
        openai_api_key = OS.get_environment("OPENAI_API_KEY")

func load_user_settings() -> void:
    var config_file = ConfigFile.new()
    var err = config_file.load("user://settings.cfg")
    
    if err != OK:
        print("No settings file found, using defaults")
        save_user_settings()
        return
    
    for key in user_settings.keys():
        user_settings[key] = config_file.get_value("settings", key, user_settings[key])

func save_user_settings() -> void:
    var config_file = ConfigFile.new()
    
    for key in user_settings.keys():
        config_file.set_value("settings", key, user_settings[key])
    
    config_file.save("user://settings.cfg")

func get_unit_stats(archetype: String) -> Dictionary:
    return UNIT_ARCHETYPES.get(archetype, UNIT_ARCHETYPES["scout"])

func get_building_stats(building_type: String) -> Dictionary:
    return BUILDING_TYPES.get(building_type, {}) 