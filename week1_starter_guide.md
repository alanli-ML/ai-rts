# Week 1 Starter Guide: Project Foundation

This guide provides step-by-step instructions for setting up the AI-RTS project foundation in the first week.

## Day 1-2: Environment Setup

### Step 1: Project Creation
1. Open Godot 4.4+
2. Create new project: "AI-RTS"
3. Set project settings:
   - Rendering → Renderer → Rendering Method: "Forward+"
   - Display → Window → Size: 1920x1080
   - Physics → 3D → Physics Ticks Per Second: 60

### Step 2: Directory Structure
Create the following folders in the FileSystem dock:

```
res://
├── scenes/
│   ├── units/
│   ├── buildings/
│   ├── maps/
│   ├── ui/
│   └── components/
├── scripts/
│   ├── core/
│   ├── networking/
│   ├── ai/
│   ├── utils/
│   └── autoload/
├── resources/
│   ├── models/
│   ├── materials/
│   ├── textures/
│   └── sounds/
└── assets/
    └── kenney/
```

### Step 3: Git Setup
Create `.gitignore`:
```
# Godot 4+ specific ignores
.godot/
export.cfg
export_presets.cfg

# Imported translations (automatically generated from CSV files)
*.translation

# Mono-specific ignores
.mono/
data_*/
mono_crash.*.json

# System/tool-specific ignores
.DS_Store
.vscode/
*.tmp

# Commonly ignored files
*.log
*.pid
*.seed
*.pid.lock

# API Keys and sensitive data
.env
config/secrets.cfg
```

### Step 4: Download Assets
1. Visit https://kenney.nl/assets?q=3d
2. Download these packs:
   - Tower Defense Kit
   - RTS Medieval Kit  
   - Animated Characters 2
3. Extract to `res://assets/kenney/`

### Step 5: Project Configuration
Create `res://project.godot` settings:
```ini
[application]
config/name="AI-RTS"
config/version="0.1.0"
run/main_scene="res://scenes/Main.tscn"
config/features=PackedStringArray("4.4", "Forward Plus")
config/icon="res://icon.svg"

[autoload]
GameManager="*res://scripts/autoload/game_manager.gd"
EventBus="*res://scripts/autoload/event_bus.gd"
ConfigManager="*res://scripts/autoload/config_manager.gd"

[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/mode=3
window/stretch/mode="canvas_items"

[rendering]
renderer/rendering_method="forward_plus"
lights_and_shadows/directional_shadow/size=4096
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=3
anti_aliasing/quality/msaa_3d=2
```

## Day 3-4: Core Singletons

### Step 1: GameManager Singleton
Create `res://scripts/autoload/game_manager.gd`:

```gdscript
# GameManager.gd
extends Node

signal game_state_changed(new_state: GameState)
signal match_started()
signal match_ended(winner: String)

enum GameState {
    MENU,
    LOBBY,
    LOADING,
    IN_GAME,
    PAUSED,
    POST_MATCH
}

var current_state: GameState = GameState.MENU
var current_match: Dictionary = {}
var player_data: Dictionary = {}

func _ready() -> void:
    print("GameManager initialized")
    process_mode = Node.PROCESS_MODE_ALWAYS

func change_state(new_state: GameState) -> void:
    if current_state == new_state:
        return
    
    var old_state = current_state
    current_state = new_state
    
    print("Game state changed from %s to %s" % [
        GameState.keys()[old_state],
        GameState.keys()[new_state]
    ])
    
    game_state_changed.emit(new_state)

func start_match(match_config: Dictionary) -> void:
    current_match = match_config
    change_state(GameState.LOADING)
    
    # Load the map scene
    var map_path = "res://scenes/maps/%s.tscn" % match_config.get("map", "test_map")
    
    # Defer scene change to next frame
    call_deferred("_load_match_scene", map_path)

func _load_match_scene(map_path: String) -> void:
    get_tree().change_scene_to_file(map_path)
    change_state(GameState.IN_GAME)
    match_started.emit()

func end_match(winner: String) -> void:
    change_state(GameState.POST_MATCH)
    match_ended.emit(winner)
    
    # Clear match data after a delay
    await get_tree().create_timer(3.0).timeout
    current_match.clear()
```

### Step 2: EventBus Singleton
Create `res://scripts/autoload/event_bus.gd`:

```gdscript
# EventBus.gd
extends Node

# Unit Events
signal unit_spawned(unit: Unit)
signal unit_died(unit: Unit)
signal unit_selected(unit: Unit)
signal unit_deselected(unit: Unit)
signal unit_command_issued(unit_id: String, command: String)

# Building Events
signal building_placed(building: Building)
signal building_completed(building: Building)
signal building_destroyed(building: Building)

# Node Events
signal node_captured(node_id: String, team: String)
signal node_lost(node_id: String, team: String)

# Player Events
signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int)
signal player_ready(peer_id: int)

# UI Events
signal ui_command_entered(command: String)
signal ui_radial_command(command_id: String)

# Network Events
signal network_peer_connected(peer_id: int)
signal network_peer_disconnected(peer_id: int)
signal network_connection_failed()
signal network_server_created()

func _ready() -> void:
    print("EventBus initialized")

# Helper function to emit unit commands
func emit_unit_command(unit_id: String, command: String) -> void:
    unit_command_issued.emit(unit_id, command)
    print("Command issued: %s -> %s" % [unit_id, command])

# Helper function for debug logging
func log_event(event_name: String, data: Dictionary = {}) -> void:
    if OS.is_debug_build():
        print("[EVENT] %s: %s" % [event_name, data])
```

### Step 3: ConfigManager Singleton
Create `res://scripts/autoload/config_manager.gd`:

```gdscript
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
        "speed": 15.0,
        "health": 60.0,
        "vision_range": 40.0,
        "vision_angle": 120.0,
        "attack_range": 15.0,
        "attack_damage": 20.0
    },
    "tank": {
        "speed": 5.0,
        "health": 200.0,
        "vision_range": 20.0,
        "vision_angle": 120.0,
        "attack_range": 10.0,
        "attack_damage": 40.0
    },
    "sniper": {
        "speed": 8.0,
        "health": 80.0,
        "vision_range": 50.0,
        "vision_angle": 60.0,
        "attack_range": 40.0,
        "attack_damage": 60.0
    },
    "medic": {
        "speed": 10.0,
        "health": 100.0,
        "vision_range": 30.0,
        "vision_angle": 120.0,
        "attack_range": 0.0,
        "heal_range": 15.0,
        "heal_rate": 10.0
    },
    "engineer": {
        "speed": 8.0,
        "health": 120.0,
        "vision_range": 30.0,
        "vision_angle": 120.0,
        "attack_range": 12.0,
        "attack_damage": 25.0,
        "build_speed": 2.0
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
```

### Step 4: Create Logging Utility
Create `res://scripts/utils/logger.gd`:

```gdscript
# Logger.gd
class_name Logger
extends RefCounted

enum LogLevel {
    DEBUG,
    INFO,
    WARNING,
    ERROR
}

static var _instance: Logger
static var _log_file: FileAccess
static var _log_level: LogLevel = LogLevel.DEBUG

static func _static_init() -> void:
    _instance = Logger.new()
    
    if OS.is_debug_build():
        var log_path = "user://game_log_%s.txt" % Time.get_datetime_string_from_system().replace(":", "-")
        _log_file = FileAccess.open(log_path, FileAccess.WRITE)

static func log(level: LogLevel, category: String, message: String) -> void:
    if level < _log_level:
        return
    
    var timestamp = Time.get_time_string_from_system()
    var level_str = LogLevel.keys()[level]
    var log_entry = "[%s] [%s] [%s] %s" % [timestamp, level_str, category, message]
    
    print(log_entry)
    
    if _log_file:
        _log_file.store_line(log_entry)
        _log_file.flush()

static func debug(category: String, message: String) -> void:
    log(LogLevel.DEBUG, category, message)

static func info(category: String, message: String) -> void:
    log(LogLevel.INFO, category, message)

static func warning(category: String, message: String) -> void:
    log(LogLevel.WARNING, category, message)
    push_warning(message)

static func error(category: String, message: String) -> void:
    log(LogLevel.ERROR, category, message)
    push_error(message)
```

## Day 5: Basic Map

### Step 1: Create Main Scene
Create `res://scenes/Main.tscn`:

1. Create a new 3D Scene
2. Add Node3D as root, rename to "Main"
3. Save as Main.tscn

### Step 2: Create Test Map
Create `res://scenes/maps/test_map.tscn`:

1. Create new 3D Scene
2. Structure:
```
TestMap (Node3D)
├── Environment (Node3D)
│   ├── DirectionalLight3D
│   ├── WorldEnvironment
│   └── Terrain (CSGBox3D or GridMap)
├── CaptureNodes (Node3D)
│   ├── Node1 (Area3D)
│   ├── Node2 (Area3D)
│   └── ... (9 total)
├── SpawnPoints (Node3D)
│   ├── Team1Spawn (Marker3D)
│   └── Team2Spawn (Marker3D)
└── Camera (Camera3D)
```

### Step 3: Map Setup Script
Create `res://scripts/core/map.gd`:

```gdscript
# Map.gd
class_name Map
extends Node3D

@export var map_name: String = "Test Map"
@export var map_size: Vector2 = Vector2(100, 100)
@export var node_count: int = 9

@onready var capture_nodes: Node3D = $CaptureNodes
@onready var spawn_points: Node3D = $SpawnPoints

var node_positions: Array[Vector3] = []
var team_spawns: Dictionary = {}

func _ready() -> void:
    Logger.info("Map", "Loading map: %s" % map_name)
    setup_capture_nodes()
    setup_spawn_points()

func setup_capture_nodes() -> void:
    # Create a 3x3 grid of capture nodes
    var spacing = map_size.x / 4  # Divide map into quarters
    var center = Vector3(map_size.x / 2, 0, map_size.y / 2)
    
    for i in range(3):
        for j in range(3):
            var node_index = i * 3 + j
            var x_offset = (i - 1) * spacing
            var z_offset = (j - 1) * spacing
            var pos = Vector3(center.x + x_offset, 0, center.z + z_offset)
            
            node_positions.append(pos)
            
            # Position existing nodes or create new ones
            if node_index < capture_nodes.get_child_count():
                var node = capture_nodes.get_child(node_index)
                node.position = pos
            else:
                create_capture_node(pos, "Node%d" % (node_index + 1))

func create_capture_node(pos: Vector3, node_name: String) -> void:
    var area = Area3D.new()
    area.name = node_name
    area.position = pos
    
    var collision = CollisionShape3D.new()
    var shape = CylinderShape3D.new()
    shape.radius = 5.0
    shape.height = 0.5
    collision.shape = shape
    area.add_child(collision)
    
    # Visual representation
    var mesh_instance = MeshInstance3D.new()
    var cylinder_mesh = CylinderMesh.new()
    cylinder_mesh.radial_segments = 16
    cylinder_mesh.rings = 1
    cylinder_mesh.top_radius = 5.0
    cylinder_mesh.bottom_radius = 5.0
    cylinder_mesh.height = 0.5
    mesh_instance.mesh = cylinder_mesh
    area.add_child(mesh_instance)
    
    capture_nodes.add_child(area)

func setup_spawn_points() -> void:
    for child in spawn_points.get_children():
        if child is Marker3D:
            var team_name = child.name.replace("Spawn", "")
            team_spawns[team_name] = child.position
            Logger.debug("Map", "Registered spawn point for %s at %s" % [team_name, child.position])

func get_spawn_position(team: String) -> Vector3:
    return team_spawns.get(team, Vector3.ZERO)

func get_random_node_position() -> Vector3:
    if node_positions.is_empty():
        return Vector3.ZERO
    return node_positions.pick_random()
```

### Step 4: Environment Setup
In the test_map scene:

1. **DirectionalLight3D settings:**
   - Rotation: (-45, -45, 0)
   - Light Energy: 1.0
   - Shadow Enabled: true

2. **WorldEnvironment:**
   - Create new Environment resource
   - Background Mode: Sky
   - Create ProceduralSkyMaterial
   - Add some fog for atmosphere

3. **Basic Terrain:**
   - Add CSGBox3D
   - Size: (100, 1, 100)
   - Material: Create simple green material

## Testing Your Setup

### Create Test Script
Create `res://scripts/test_setup.gd` and attach to Main scene:

```gdscript
extends Node3D

func _ready() -> void:
    print("=== AI-RTS Test Setup ===")
    print("Game Version: %s" % ConfigManager.GAME_VERSION)
    print("Godot Version: %s" % Engine.get_version_info().string)
    
    # Test singleton access
    assert(GameManager != null, "GameManager not loaded")
    assert(EventBus != null, "EventBus not loaded")
    assert(ConfigManager != null, "ConfigManager not loaded")
    
    # Test logging
    Logger.info("Test", "All systems initialized successfully")
    
    # Test game state
    GameManager.game_state_changed.connect(_on_game_state_changed)
    GameManager.change_state(GameManager.GameState.MENU)
    
    # Load test map after a short delay
    await get_tree().create_timer(1.0).timeout
    GameManager.start_match({"map": "test_map", "players": 2})

func _on_game_state_changed(new_state: GameManager.GameState) -> void:
    Logger.info("Test", "Game state changed to: %s" % GameManager.GameState.keys()[new_state])
```

### Run Tests
1. Set Main.tscn as main scene
2. Run the project (F5)
3. Check console for initialization messages
4. Verify map loads after 1 second

## Next Steps

With the foundation in place, you're ready for Week 2:
- Implement RTS camera controls
- Create selection system
- Build command input UI

## Troubleshooting

### Common Issues:

1. **Singleton not found:**
   - Check autoload order in Project Settings
   - Ensure script paths are correct

2. **Map not loading:**
   - Verify scene file paths
   - Check for errors in map setup

3. **Performance issues:**
   - Ensure Forward+ renderer is selected
   - Check shadow quality settings

## Additional Resources

- [Godot 4 Documentation](https://docs.godotengine.org/en/stable/)
- [Kenney Assets](https://kenney.nl/assets)
- [GDScript Style Guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html) 