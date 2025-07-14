# Technical Architecture - AI-Driven RTS

## System Overview

The AI-driven RTS is built on a multi-layered architecture that separates concerns between rendering, game logic, networking, and AI decision-making.

```
┌─────────────────────────────────────────────────────────┐
│                     Client Layer                         │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │   Renderer  │  │   UI/Input   │  │  Interpolator │  │
│  │   (60 Hz)   │  │              │  │               │  │
│  └─────────────┘  └──────────────┘  └───────────────┘  │
└─────────────────────────────────────────────────────────┘
                            │
                  Network Protocol (30 Hz)
                            │
┌─────────────────────────────────────────────────────────┐
│                    Server Layer                          │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ Game Logic  │  │   Physics    │  │     FSM       │  │
│  │  (30 Hz)    │  │   (60 Hz)    │  │   (30 Hz)     │  │
│  └─────────────┘  └──────────────┘  └───────────────┘  │
│                                                          │
│  ┌─────────────────────────────────────────────────┐   │
│  │              AI Decision Layer                    │   │
│  │  ┌───────────┐  ┌────────────┐  ┌────────────┐  │   │
│  │  │LLM Bridge │  │ Validator  │  │   Plan     │  │   │
│  │  │(0.5-2 Hz) │  │            │  │ Executor   │  │   │
│  │  └───────────┘  └────────────┘  └────────────┘  │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## Core Systems

### 1. Game State Management

```gdscript
# GameState.gd - Singleton
extends Node

signal state_changed(new_state: GamePhase)

enum GamePhase {
    MENU,
    LOBBY,
    UNIT_LOADOUT,
    IN_GAME,
    POST_MATCH
}

var current_phase: GamePhase = GamePhase.MENU
var match_data: MatchData
var player_data: Dictionary = {}  # peer_id -> PlayerData

class MatchData:
    var map_id: String
    var node_ownership: Dictionary = {}  # node_id -> team_id
    var unit_registry: Dictionary = {}   # unit_id -> Unit
    var building_registry: Dictionary = {} # building_id -> Building
    var tick_number: int = 0
    var match_time: float = 0.0
```

### 2. Networking Architecture

#### Lock-step Implementation
```gdscript
# LockstepManager.gd
extends Node

const LOCKSTEP_DELAY = 3  # frames
const INPUT_BUFFER_SIZE = 10

var input_buffer: Dictionary = {}  # tick -> {peer_id -> input}
var confirmed_tick: int = 0
var predicted_tick: int = 0

func _ready():
    get_tree().physics_ticks_per_second = 60
    
func collect_inputs(tick: int, inputs: Dictionary):
    input_buffer[tick] = inputs
    
func process_confirmed_tick():
    if not input_buffer.has(confirmed_tick + LOCKSTEP_DELAY):
        return false
        
    var tick_inputs = input_buffer[confirmed_tick + LOCKSTEP_DELAY]
    
    # All clients must have sent input
    if tick_inputs.size() < NetworkManager.peer_count:
        return false
        
    # Process the tick
    GameLogic.simulate_tick(confirmed_tick, tick_inputs)
    confirmed_tick += 1
    return true
```

#### State Synchronization
```gdscript
# StateSynchronizer.gd
extends Node

const SYNC_INTERVAL = 0.1  # seconds
const DELTA_THRESHOLD = 10  # units

var last_sync_time: float = 0.0
var state_history: Array = []  # Circular buffer

func should_send_delta(unit: Unit, last_state: Dictionary) -> bool:
    var pos_delta = unit.position.distance_to(last_state.position)
    return pos_delta > DELTA_THRESHOLD or unit.health != last_state.health

func create_state_packet() -> Dictionary:
    var packet = {
        "tick": GameState.match_data.tick_number,
        "units": {},
        "buildings": {},
        "nodes": {}
    }
    
    # Delta compression for units
    for unit_id in GameState.match_data.unit_registry:
        var unit = GameState.match_data.unit_registry[unit_id]
        if should_send_delta(unit, get_last_state(unit_id)):
            packet.units[unit_id] = compress_unit_state(unit)
    
    return packet
```

### 3. AI System Architecture

#### Unit Packet Generation
```gdscript
# UnitPacketGenerator.gd
extends Node

const VISION_ANGLE = 120.0
const VISION_RANGE = 30.0
const DANGER_GRID_SIZE = 8

func generate_packet(unit: Unit) -> Dictionary:
    var packet = {
        "meta": {
            "unit_id": unit.unit_id,
            "owner": unit.team_id,
            "arch": unit.archetype,
            "sys_prompt": unit.system_prompt
        },
        "stats": {
            "health": unit.current_health,
            "morale": unit.morale,
            "energy": unit.energy
        },
        "pos": {"x": int(unit.position.x), "y": int(unit.position.z)},
        "heading": int(unit.rotation.y),
        "sensor": generate_sensor_data(unit),
        "orders": unit.current_orders,
        "fsm_state": unit.fsm.current_state_name,
        "memory": unit.short_term_memory,
        "legal_actions": get_legal_actions(unit)
    }
    return packet

func generate_sensor_data(unit: Unit) -> Dictionary:
    var visible_entities = VisionSystem.get_visible_entities(unit)
    
    return {
        "enemies": format_entities(visible_entities.enemies),
        "friendlies": format_entities(visible_entities.friendlies),
        "cover_tiles": find_nearby_cover(unit),
        "danger_grid": generate_danger_grid(unit),
        "terrain": get_terrain_code(unit.position)
    }
```

#### LLM Integration
```gdscript
# LLMBridge.gd
extends Node

const MAX_BATCH_SIZE = 32
const REQUEST_TIMEOUT = 5.0

var http_request: HTTPRequest
var pending_requests: Dictionary = {}

func batch_process_units(units: Array) -> void:
    var batches = []
    var current_batch = []
    
    for unit in units:
        current_batch.append(unit)
        if current_batch.size() >= MAX_BATCH_SIZE:
            batches.append(current_batch)
            current_batch = []
    
    if current_batch.size() > 0:
        batches.append(current_batch)
    
    for batch in batches:
        _send_batch_request(batch)

func _send_batch_request(units: Array) -> void:
    var prompts = []
    
    for unit in units:
        var packet = UnitPacketGenerator.generate_packet(unit)
        var prompt = format_prompt(packet, unit.system_prompt)
        prompts.append(prompt)
    
    var request_body = {
        "model": "gpt-4-turbo",
        "messages": prompts,
        "functions": [get_plan_schema()],
        "function_call": {"name": "create_plan"},
        "temperature": 0.7,
        "max_tokens": 50
    }
    
    var headers = [
        "Content-Type: application/json",
        "Authorization: Bearer " + ConfigManager.openai_api_key
    ]
    
    http_request.request(
        "https://api.openai.com/v1/chat/completions",
        headers,
        HTTPClient.METHOD_POST,
        JSON.stringify(request_body)
    )
```

### 4. Plan Execution System

```gdscript
# PlanExecutor.gd
extends Node

class PlanStep:
    var action: String
    var params: Dictionary
    var duration_ms: int = 0
    var trigger: String = ""
    var speech: String = ""
    var start_time: float = 0.0

var active_plans: Dictionary = {}  # unit_id -> Array[PlanStep]
var current_steps: Dictionary = {} # unit_id -> PlanStep

func _process(delta: float):
    for unit_id in active_plans:
        if not current_steps.has(unit_id):
            _start_next_step(unit_id)
        else:
            _check_step_completion(unit_id)

func execute_plan(unit_id: String, plan: Array) -> void:
    var validated_steps = []
    
    for step_data in plan:
        var step = PlanStep.new()
        step.action = step_data.action
        step.params = step_data.get("params", {})
        step.duration_ms = step_data.get("duration_ms", 0)
        step.trigger = step_data.get("trigger", "")
        step.speech = step_data.get("speech", "")
        validated_steps.append(step)
    
    active_plans[unit_id] = validated_steps
    _start_next_step(unit_id)

func _check_step_completion(unit_id: String) -> void:
    var step = current_steps[unit_id]
    var unit = GameState.match_data.unit_registry[unit_id]
    
    # Check trigger conditions
    if step.trigger != "":
        if not _evaluate_trigger(step.trigger, unit):
            return
    
    # Check duration
    elif step.duration_ms > 0:
        var elapsed = (Time.get_ticks_msec() - step.start_time)
        if elapsed < step.duration_ms:
            return
    
    # Step complete
    current_steps.erase(unit_id)
    active_plans[unit_id].pop_front()
    
    if active_plans[unit_id].is_empty():
        active_plans.erase(unit_id)
        _request_new_plan(unit_id)
```

### 5. Vision System

```gdscript
# VisionSystem.gd
extends Node

const VISION_LAYERS = {
    "units": 1,
    "buildings": 2,
    "terrain": 3
}

func get_visible_entities(unit: Unit) -> Dictionary:
    var result = {
        "enemies": [],
        "friendlies": [],
        "buildings": [],
        "nodes": []
    }
    
    var space_state = unit.get_world_3d().direct_space_state
    var vision_origin = unit.global_position + Vector3(0, 1.5, 0)
    
    # Cast rays in vision cone
    var angle_step = 5.0  # degrees
    var start_angle = -unit.vision_angle / 2.0
    var end_angle = unit.vision_angle / 2.0
    
    for angle in range(start_angle, end_angle + 1, angle_step):
        var direction = unit.transform.basis.z.rotated(Vector3.UP, deg_to_rad(angle))
        var query = PhysicsRayQueryParameters3D.create(
            vision_origin,
            vision_origin + direction * unit.vision_range
        )
        query.collision_mask = VISION_LAYERS.units | VISION_LAYERS.buildings
        
        var collision = space_state.intersect_ray(query)
        if collision:
            _process_visible_entity(collision.collider, result, unit)
    
    return result

func _process_visible_entity(entity: Node3D, result: Dictionary, viewer: Unit):
    if entity is Unit:
        var target_unit = entity as Unit
        if target_unit.team_id == viewer.team_id:
            result.friendlies.append(_create_entity_data(target_unit, viewer))
        else:
            result.enemies.append(_create_entity_data(target_unit, viewer))
    elif entity is Building:
        result.buildings.append(_create_entity_data(entity, viewer))
```

### 6. Performance Optimization

#### Object Pooling
```gdscript
# ObjectPool.gd
extends Node

var projectile_pool: Array = []
var effect_pool: Array = []
var speech_bubble_pool: Array = []

const POOL_SIZES = {
    "projectile": 100,
    "effect": 50,
    "speech_bubble": 20
}

func _ready():
    _initialize_pools()

func get_projectile() -> Projectile:
    if projectile_pool.is_empty():
        return _create_projectile()
    return projectile_pool.pop_back()

func return_projectile(proj: Projectile):
    proj.reset()
    proj.visible = false
    projectile_pool.append(proj)
```

#### Network Compression
```gdscript
# NetworkCompression.gd
extends Node

func compress_position(pos: Vector3) -> Dictionary:
    return {
        "x": int(pos.x * 10),  # 0.1m precision
        "y": int(pos.z * 10)   # Ignore height for 2D gameplay
    }

func compress_unit_state(unit: Unit) -> PackedByteArray:
    var buffer = PackedByteArray()
    
    # Header (1 byte): flags for what's included
    var flags = 0
    if unit.is_moving: flags |= 1
    if unit.is_attacking: flags |= 2
    if unit.health < unit.max_health: flags |= 4
    
    buffer.append(flags)
    
    # Position (4 bytes total)
    buffer.append_array(_pack_int16(int(unit.position.x * 10)))
    buffer.append_array(_pack_int16(int(unit.position.z * 10)))
    
    # Rotation (1 byte: 256 directions)
    buffer.append(int(unit.rotation.y / 360.0 * 255))
    
    # Conditional data based on flags
    if flags & 4:  # Health changed
        buffer.append(int(unit.health / unit.max_health * 255))
    
    return buffer
```

## Data Flow Diagrams

### Command Processing Flow
```
Player Input
    ↓
Command Parser
    ↓
Command Validator
    ↓
Unit Selection
    ↓
Packet Generation
    ↓
LLM Batching
    ↓
OpenAI Request
    ↓
Plan Validation
    ↓
Plan Distribution
    ↓
Unit Execution
```

### State Update Flow
```
Physics Simulation (60 Hz)
    ↓
State Collection (30 Hz)
    ↓
Delta Compression
    ↓
Network Broadcast
    ↓
Client Reception
    ↓
Interpolation
    ↓
Rendering (60 Hz)
```

## Security Considerations

1. **Input Validation**: All player commands validated server-side
2. **Plan Validation**: AI plans checked for legal actions and parameters
3. **State Authority**: Server maintains authoritative game state
4. **Replay System**: All inputs logged for replay and cheat detection
5. **Rate Limiting**: Command frequency capped per player

## Scalability Plan

1. **Horizontal Scaling**: Multiple match servers behind load balancer
2. **LLM Caching**: Redis cache for common prompts/responses
3. **Regional Servers**: Deploy in multiple regions for low latency
4. **Database**: PostgreSQL for persistent data, Redis for sessions
5. **Monitoring**: Prometheus + Grafana for system metrics 