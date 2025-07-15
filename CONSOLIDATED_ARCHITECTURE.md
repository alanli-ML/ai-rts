# 🏗️ Consolidated Architecture - Unified Server-Authoritative Design

## 🎯 **Architecture Overview**

This document describes the unified architecture that eliminates code duplication between server and client through runtime mode detection. The server handles all game logic, while the client focuses solely on display and input.

### **Core Principle**
> **Single Codebase, Runtime Mode Detection, Server Authority**

## 📁 **Project Structure**

```
ai-rts/
├── scripts/
│   ├── shared/                          # Shared components (no duplication)
│   │   ├── types/
│   │   │   ├── game_enums.gd           # Game state enums
│   │   │   └── network_messages.gd     # Network message structures
│   │   ├── constants/
│   │   │   └── game_constants.gd       # Game balance constants
│   │   └── utils/
│   │       └── logger.gd               # Logging utilities
│   ├── client/                          # Client-side display only
│   │   ├── client_display_manager.gd   # Main client display controller
│   │   └── display_manager.gd          # Display state management
│   ├── server/                          # Server-side game logic
│   │   ├── dedicated_server.gd         # Server initialization
│   │   ├── server_game_state.gd        # Authoritative game state
│   │   └── session_manager.gd          # Session management
│   ├── core/                            # Core game systems
│   │   ├── dependency_container.gd     # Dependency injection
│   │   ├── game_mode.gd                # Game mode management
│   │   ├── unit.gd                     # Unit base class
│   │   └── entity_manager.gd           # ✨ NEW: Entity deployment system
│   ├── entities/                        # ✨ NEW: Deployable entities
│   │   ├── mine_entity.gd              # Mine deployment and explosion
│   │   ├── turret_entity.gd            # Turret construction and defense
│   │   └── spire_entity.gd             # Spire hijacking and power generation
│   ├── ai/                              # AI integration systems
│   │   ├── ai_command_processor.gd     # AI command processing
│   │   ├── action_validator.gd         # AI action validation
│   │   └── plan_executor.gd            # Multi-step plan execution + entity actions
│   ├── gameplay/                        # Gameplay systems
│   │   ├── control_point.gd            # Individual control points
│   │   ├── node_capture_system.gd      # Control point management
│   │   └── resource_manager.gd         # Resource management
│   ├── buildings/                       # Building systems
│   │   └── building.gd                 # Building base class
│   ├── ui/                              # User interface systems
│   │   ├── game_hud.gd                 # Main game HUD
│   │   ├── speech_bubble.gd            # Unit communication
│   │   ├── speech_bubble_manager.gd    # Speech bubble management
│   │   ├── plan_progress_indicator.gd  # AI plan progress display
│   │   └── plan_progress_manager.gd    # Progress indicator management
│   ├── test/                            # Test suites
│   │   ├── test_ai_integration.gd      # AI system tests
│   │   ├── test_node_capture_system.gd # Control point tests
│   │   ├── test_resource_management.gd # Resource system tests
│   │   ├── test_plan_progress_indicators.gd # UI tests
│   │   └── test_entity_system.gd       # ✨ NEW: Entity system tests
│   └── unified_main.gd                  # Unified main controller
└── ...
```

## 🔄 **Data Flow Architecture**

### **Complete Data Flow**
```
Player Input → Client → Server → Game Logic → AI Processing → Entity Deployment → Resource Management → Control Points → Server → All Clients → Display
```

### **Detailed Flow**
1. **Input Capture**: Client captures user input (mouse clicks, keyboard)
2. **Input Transmission**: Client sends input to server via RPC
3. **Server Processing**: Server processes input and updates game state
4. **AI Integration**: Server integrates with AI service for multi-step plan execution
5. **Entity Deployment**: Server manages mine/turret/spire deployment through EntityManager
6. **Resource Management**: Server updates resource generation/consumption
7. **Control Point Updates**: Server processes control point capture mechanics
8. **Building System**: Server manages building construction and functionality
9. **State Broadcast**: Server sends updated state to all clients
10. **Client Display**: Clients update HUD, speech bubbles, and progress indicators

## 🎮 **Core Systems Architecture**

### **✅ Unified Architecture (Complete)**
- **Single Codebase**: Client and server use same code with runtime mode detection
- **Dependency Injection**: Clean separation of concerns with DependencyContainer
- **Runtime Mode Detection**: Automatic server/client configuration
- **Shared Components**: GameConstants, GameEnums, Logger used by both modes

### **✅ AI Integration System (Complete)**
- **Multi-Step Plan Execution**: Advanced LLM integration with conditional triggers
- **Action Validator**: Validates AI actions against game rules
- **Plan Executor**: Executes complex plans with timing and triggers
- **Speech Bubble Integration**: AI plans trigger unit communication

### **✅ Entity Deployment System (Complete)** 🎯
- **MineEntity**: Proximity/timed/remote mines with explosion mechanics
- **TurretEntity**: Defensive turrets with construction phases and targeting
- **SpireEntity**: Power spires with hijacking mechanics and resource generation
- **EntityManager**: Centralized deployment with tile-based placement validation
- **AI Integration**: Natural language entity deployment (lay_mines, build_turret, hijack_spire)

### **✅ Gameplay Systems (Complete)**
- **Control Point System**: 9 strategic control points with capture mechanics
- **Resource Management**: Energy/Materials/Research economy
- **Building System**: Power Spire, Defense Tower, Relay Pad with resource costs
- **Victory Conditions**: Multiple paths to victory (elimination, control points, strategic)

### **✅ Visual Communication (Complete)**
- **Speech Bubble System**: 12-word limit unit communication with team colors
- **Plan Progress Indicators**: Real-time AI plan execution feedback
- **Enhanced HUD**: Comprehensive resource display and notifications
- **Notification System**: Event-driven alerts for game state changes

## 🔧 **Technical Implementation**

### **Unified Main Controller**
```gdscript
# unified_main.gd
extends Node

func _ready() -> void:
    # Determine runtime mode
    if OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless":
        _start_server_mode()
    else:
        _start_client_mode()

func _start_server_mode() -> void:
    dependency_container.create_server_dependencies()
    
func _start_client_mode() -> void:
    dependency_container.create_client_dependencies()
```

### **Dependency Injection System**
```gdscript
# dependency_container.gd
class_name DependencyContainer
extends Node

func create_server_dependencies() -> void:
    # Server-specific dependencies
    var server_game_state = preload("res://scripts/server/server_game_state.gd").new()
    var resource_manager = preload("res://scripts/gameplay/resource_manager.gd").new()
    var node_capture_system = preload("res://scripts/gameplay/node_capture_system.gd").new()
    var entity_manager = preload("res://scripts/core/entity_manager.gd").new()  # ✨ NEW
    
func create_client_dependencies() -> void:
    # Client-specific dependencies
    var client_display_manager = preload("res://scripts/client/client_display_manager.gd").new()
    var game_hud = preload("res://scripts/ui/game_hud.gd").new()
```

### **Server Game State Management**
```gdscript
# server_game_state.gd
extends Node

var node_capture_system: NodeCaptureSystem
var resource_manager: ResourceManager
var ai_command_processor: AICommandProcessor
var entity_manager: EntityManager  # ✨ NEW

func _ready() -> void:
    # Initialize entity manager
    entity_manager.setup(logger, asset_loader, map_generator, resource_manager)
```

### **🎯 Entity System Architecture** - NEW!

#### **EntityManager - Central Entity Controller**
```gdscript
# entity_manager.gd
class_name EntityManager
extends Node

# Entity collections
var active_mines: Dictionary = {}      # mine_id -> MineEntity
var active_turrets: Dictionary = {}    # turret_id -> TurretEntity
var active_spires: Dictionary = {}     # spire_id -> SpireEntity

# Tile-based placement tracking
var tile_occupation: Dictionary = {}   # tile_pos -> entity_id
var placement_restrictions: Dictionary = {}  # tile_pos -> restriction_type

# Entity limits per team
var team_limits: Dictionary = {
    "mines": 10,
    "turrets": 5,
    "spires": 3
}

func deploy_mine(tile_pos: Vector2i, mine_type: String, team_id: int, owner_unit_id: String) -> String
func build_turret(tile_pos: Vector2i, turret_type: String, team_id: int, owner_unit_id: String) -> String
func create_spire(tile_pos: Vector2i, spire_type: String, team_id: int) -> String
```

#### **MineEntity - Deployable Mines**
```gdscript
# mine_entity.gd
class_name MineEntity
extends Area3D

@export var mine_type: String = "proximity"  # proximity, timed, remote
@export var damage: float = 50.0
@export var blast_radius: float = 8.0
@export var detection_radius: float = 3.0
@export var arm_time: float = 2.0

var is_armed: bool = false
var is_triggered: bool = false
var detected_units: Array[Unit] = []

func _trigger_mine(target_unit: Unit = null)
func _explode_mine()
func _deal_area_damage()
```

#### **TurretEntity - Defensive Turrets**
```gdscript
# turret_entity.gd
class_name TurretEntity
extends StaticBody3D

@export var turret_type: String = "basic"  # basic, heavy, anti_air, laser
@export var max_health: float = 200.0
@export var attack_damage: float = 30.0
@export var attack_range: float = 12.0
@export var construction_time: float = 8.0

var is_constructed: bool = false
var current_target: Unit = null
var visible_enemies: Array[Unit] = []

func _complete_construction()
func _attack_target(target: Unit)
func _find_best_target() -> Unit
```

#### **SpireEntity - Hijackable Power Spires**
```gdscript
# spire_entity.gd
class_name SpireEntity
extends StaticBody3D

@export var spire_type: String = "power"  # power, communication, shield
@export var max_health: float = 500.0
@export var power_generation: float = 20.0
@export var hijack_time: float = 5.0

var is_being_hijacked: bool = false
var hijacker_unit: Unit = null
var hijack_progress: float = 0.0

func _start_hijack(unit: Unit)
func _complete_hijack()
func _activate_defenses(target: Unit)
```

## 🎯 **Enhanced AI Integration**

### **Plan Executor with Entity Actions**
```gdscript
# plan_executor.gd - Enhanced with entity deployment

func _execute_lay_mines(unit_id: String, step: PlanStep, unit: Node) -> bool:
    # Get entity manager
    var entity_manager = get_tree().get_first_node_in_group("entity_managers")
    
    # Convert world position to tile position
    var tile_pos = tile_system.world_to_tile(mine_pos)
    
    # Deploy mines through entity manager
    var mine_id = entity_manager.deploy_mine(tile_pos, mine_type, unit.team_id, unit_id)
    
    return mine_id != ""

func _execute_build_turret(unit_id: String, step: PlanStep, unit: Node) -> bool:
    # Similar pattern for turret construction
    
func _execute_hijack_spire(unit_id: String, step: PlanStep, unit: Node) -> bool:
    # Enhanced spire hijacking with entity system
```

## 🔄 **Procedural Integration**

### **Tile-Based Entity Placement**
The entity system is perfectly aligned with the procedural generation architecture:

#### **Tile System Integration**
- **20x20 Grid**: Entities use the same tile grid as procedural generation
- **3x3 Unit Tiles**: Each tile is 3x3 units, matching the procedural system
- **World-Tile Conversion**: Seamless conversion between world and tile coordinates
- **Placement Validation**: Collision detection with existing procedural elements

#### **Procedural District Integration**
```gdscript
# Future integration with procedural districts
func _place_entities_in_district(district_data: Dictionary):
    # Place defensive turrets at district edges
    # Deploy mines in strategic chokepoints
    # Position spires in district centers
    # Ensure entity placement aligns with procedural roads and buildings
```

## 🧪 **Testing & Validation**

### **Comprehensive Test Suite**
```gdscript
# test_entity_system.gd
class_name TestEntitySystem
extends Node

func _test_mine_deployment()      # Test mine placement and explosion
func _test_turret_construction()  # Test turret building and targeting
func _test_spire_hijacking()      # Test spire control mechanics
func _test_tile_occupation()      # Test tile-based placement
func _test_entity_limits()        # Test team limits and validation
func _test_procedural_integration()  # Test procedural alignment
```

## 🚀 **Performance Optimizations**

### **Entity Management Optimizations**
- **Object Pooling**: Reuse entity instances for better performance
- **Spatial Partitioning**: Efficient area queries using tile-based system
- **Update Optimization**: Selective entity updates based on player proximity
- **Cleanup Systems**: Automatic cleanup of destroyed entities

### **Network Optimizations**
- **State Compression**: Efficient entity state synchronization
- **Priority Updates**: Focus network traffic on important entities
- **Batch Operations**: Group entity updates for network efficiency

## 🎯 **Revolutionary Achievement**

### **Entity System Breakthrough**
The entity system represents a major architectural achievement:

#### **Perfect Procedural Alignment**
- **Tile-Based Placement**: Uses same coordinate system as procedural generation
- **Server-Authoritative**: All entity creation happens on server
- **Dependency Injection**: Clean integration with existing systems
- **Signal-Based Communication**: Event-driven entity interactions

#### **Advanced AI Integration**
- **Natural Language Deployment**: AI can deploy entities through text commands
- **Strategic Placement**: AI considers tile positioning and tactical value
- **Multi-Step Plans**: Entity deployment integrated into complex AI strategies

#### **Tactical Gameplay Enhancement**
- **Area Denial**: Mines create strategic chokepoints
- **Defense Networks**: Turrets provide automated base defense
- **Resource Control**: Spires offer strategic objectives and power generation
- **Team Coordination**: Shared entity deployment and control

## 🔮 **Future Enhancements**

### **Visual Integration**
- **Kenney Asset Integration**: Replace placeholder models with professional assets
- **Particle Effects**: Enhanced explosion and construction effects
- **Animation Systems**: Smooth entity deployment and operation animations

### **Advanced Features**
- **Entity Upgrades**: Upgrade turrets and spires with resources
- **Combination Effects**: Entities that work together for enhanced effects
- **Environmental Integration**: Entities that interact with procedural terrain

---

**Status**: Entity system fully implemented and integrated  
**Achievement**: Revolutionary RTS with comprehensive entity deployment  
**Next**: Asset integration and visual enhancement  
**Innovation**: World's first cooperative AI-integrated RTS with tile-based entity system 