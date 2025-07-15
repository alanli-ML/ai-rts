# AI-Driven RTS MVP Implementation Plan

## Overview
This document outlines a 12-week implementation plan for building an MVP of a prompt-driven RTS game in Godot 4, featuring OpenAI integration, multiplayer support, and personality-driven AI units.

## Phase 1: Core Project Setup & Basic Systems (Week 1-2)

### 1.1 Project Structure Setup
- Create folder hierarchy:
  ```
  /scenes
    /units
    /buildings
    /maps
    /ui
  /scripts
    /core
    /networking
    /ai
    /utils
  /resources
    /models     # Kenney.nl assets
    /materials
    /sounds
  /autoload     # Singletons
  ```

### 1.2 Core Singletons
- **GameManager.gd**: Overall game state management
- **NetworkManager.gd**: Multiplayer connection handling
- **EventBus.gd**: Global signal dispatching
- **ConfigManager.gd**: Game settings and constants

### 1.3 Basic Scene Architecture
- **Main.tscn**: Root scene with game state management
- **Map.tscn**: Tilemap-based battlefield with 9 nodes
- **CameraController.gd**: RTS-style camera with pan/zoom

### 1.4 Input System
- Mouse controls for camera and selection
- Keyboard shortcuts for quick commands
- Text input field for natural language commands

### 1.5 Resource Management
- Import Kenney.nl 3D assets
- Create toon shader material
- Set up asset pipeline for models and textures

## Phase 2: Unit System & Basic AI (Week 3-4)

### 2.1 Unit Base Architecture
```gdscript
# Unit.gd
class_name Unit
extends CharacterBody3D

@export var unit_id: String
@export var archetype: String  # scout, tank, sniper, medic, engineer
@export var system_prompt: String
@export var max_health: float = 100.0

var current_health: float
var morale: float = 1.0
var energy: float = 100.0
var vision_cone: Area3D
var current_plan: Dictionary = {}
```

### 2.2 Five Minion Archetypes
1. **Scout**: Fast, low HP, wide vision
2. **Tank**: Slow, high HP, short vision
3. **Sniper**: Long range, narrow vision
4. **Medic**: Support abilities, medium stats
5. **Engineer**: Can build/repair, medium stats

### 2.3 Vision System
- **VisionCone.gd**: 120° cone, 30m range
- Raycast-based occlusion checking
- Generate sensor packets with visible entities
- Implement fog of war visualization

### 2.4 Finite State Machine
```gdscript
# FiniteStateMachine.gd
class_name FiniteStateMachine
extends Node

enum State {IDLE, ALERT, MOVING, ATTACKING, RETREATING, BUILDING}
var current_state: State = State.IDLE
var state_timers: Dictionary = {}

func transition_to(new_state: State) -> bool:
    # Validate transition
    # Apply cooldowns
    # Emergency overrides (auto-retreat < 20% HP)
```

## Phase 3: Multiplayer Foundation (Week 5-6)

### 3.1 Server Architecture
- Godot High-Level Multiplayer API setup
- Authoritative server model
- Client-server communication protocol

### 3.2 Lock-step Synchronization
```gdscript
# NetworkSync.gd
const TICK_RATE = 30  # Hz
var tick_counter: int = 0
var command_buffer: Dictionary = {}

func _physics_process(delta):
    if tick_counter % 2 == 0:  # 30 Hz from 60 Hz
        process_tick()
        broadcast_state_update()
```

### 3.3 Client Prediction & Interpolation
- Implement client-side prediction for smooth movement
- Interpolate remote unit positions
- Handle rollback and reconciliation

### 3.4 Deterministic Simulation
- Fixed timestep physics
- Deterministic random number generation
- State hashing for desync detection

## Phase 4: LLM Integration & Command System (Week 7-8)

### 4.1 OpenAI Bridge
```gdscript
# LLMBridge.gd
class_name LLMBridge
extends Node

const API_ENDPOINT = "https://api.openai.com/v1/chat/completions"
var api_key: String
var request_queue: Array = []

func batch_prompt_units(unit_packets: Array) -> void:
    # Batch 8-32 units per request
    # Format prompts with system prompts
    # Send to OpenAI with function calling
```

### 4.2 Command Parser
- Natural language to intent mapping
- Quick command shortcuts
- Command history and suggestions

### 4.3 Plan Validator
```gdscript
# ActionValidator.gd
func validate_plan(plan: Dictionary) -> bool:
    # Check plan schema
    # Verify action whitelist
    # Validate parameters
    # Check duration limits (< 6s total)
    # Moderate speech content
```

### 4.4 Plan Execution System
```gdscript
# PlanExecutor.gd
var active_plans: Dictionary = {}  # unit_id -> plan
var step_timers: Dictionary = {}

func execute_step(unit_id: String, step: Dictionary):
    # Parse action and parameters
    # Check triggers (health_pct, enemy_dist, etc.)
    # Dispatch to FSM
    # Show speech bubble
```

## Phase 5: Core Gameplay Loop (Week 9-10)

### 5.1 Node Capture System
- 9 capturable nodes on the map
- Capture progress visualization
- Node ownership tracking

### 5.2 Building System
```gdscript
# Building.gd
enum BuildingType {POWER_SPIRE, DEFENSE_TOWER, RELAY_PAD}
@export var building_type: BuildingType
@export var construction_time: float = 5.0
var construction_progress: float = 0.0
```

### 5.3 Combat System
- Projectile-based combat
- Damage calculation
- Cover system implementation
- Area denial (mines)

### 5.4 Victory Conditions
- Node control percentage (≥ 60%)
- HQ destruction
- 5-minute sudden death timer
- Energy drain acceleration

### 5.5 Action Implementation
- **move_to**: A* pathfinding with local avoidance
- **peek_and_fire**: Cover-based shooting
- **lay_mines**: Area denial patterns
- **hijack_enemy_spire**: Sabotage mechanics
- **retreat**: Emergency movement to cover

## Phase 6: Polish & MVP Features (Week 11-12)

### 6.1 UI/UX Implementation
- Main menu and lobby system
- Unit loadout screen with personality editing
- In-game HUD with unit status
- Radial command menu
- Free text command input

### 6.2 Speech Bubble System
```gdscript
# SpeechBubble.gd
extends Control

@export var fade_duration: float = 2.0
var billboard_mode: bool = true

func show_speech(text: String):
    # Limit to 12 words
    # Position above unit
    # Fade after duration
```

### 6.3 Post-Match Summary
- Node flip timeline
- Kill/death log
- "Best Prompt" voting
- "Funniest Line" voting
- ELO rating calculation

### 6.4 Performance Optimization
- LOD system for units
- Occlusion culling
- Network packet optimization
- GPU instancing for projectiles

### 6.5 Testing & Debugging
- Replay system implementation
- Desync detection and logging
- Performance profiling
- Automated test scenarios

## Technical Implementation Details

### Network Architecture
```
Client → Command → Server → LLMBridge → OpenAI
                     ↓
              ActionValidator
                     ↓
              PlanExecutor → FSM → PathPlanner
                     ↓
            State Broadcast → All Clients
```

### Tick Rate Management
- **60 Hz**: Physics, animations, local feedback
- **30 Hz**: FSM updates, plan step activation
- **0.5-2 Hz**: LLM brain ticks (adaptive based on load)

### Data Flow
1. Player inputs command
2. Server batches unit prompts
3. OpenAI returns JSON plans
4. Validator approves plans
5. Executor manages multi-step execution
6. FSM enforces state transitions
7. PathPlanner handles movement
8. Clients receive state updates

## MVP Deliverables Checklist

- [ ] Online 1v1 matches lasting 15+ minutes
- [ ] OpenAI integration with <1s median latency
- [ ] 5 distinct minion archetypes
- [ ] Editable system prompts per unit
- [ ] 3 building types (Spire, Tower, Relay)
- [ ] Single 9-node map with fog of war
- [ ] Vision-based sensor packets
- [ ] Multi-step plan execution with triggers
- [ ] Speech bubble system
- [ ] 4 core actions (move, peek_and_fire, lay_mines, hijack)
- [ ] Radial + text command UI
- [ ] Post-match summary screen
- [ ] Local ELO rating system
- [ ] Deterministic replay system
- [ ] Fallback AI for network failures

## Risk Mitigation

1. **LLM Latency**: Implement aggressive batching and caching
2. **Network Desync**: Hash state every tick, automatic resync
3. **Cheating**: Server-authoritative model, plan validation
4. **Performance**: LOD system, network optimization
5. **Content Moderation**: Word filters, OpenAI moderation API

## Development Tools & Setup

### Required Tools
- Godot 4.4+
- Docker for server deployment
- Redis for caching
- Nginx for SSL proxy
- OpenAI API key

### Development Environment
```bash
# Clone repository
git clone [repo-url]

# Install Godot export templates
godot --download-templates

# Set up environment variables
export OPENAI_API_KEY="your-key"
export GAME_SERVER_PORT=7777

# Run local server
godot --headless --server
```

## Next Steps

1. Set up project structure and Git repository
2. Import Kenney.nl assets and create base materials
3. Implement Unit base class with movement
4. Create basic multiplayer lobby
5. Begin OpenAI integration testing

This implementation plan provides a structured approach to building the MVP over 12 weeks, with clear dependencies and deliverables for each phase. 