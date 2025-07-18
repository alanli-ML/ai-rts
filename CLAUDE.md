# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AI-powered cooperative RTS game built in Godot 4.4. It's a competitive 1v1 (or 2v2) RTS where players command AI-driven robo-minions using natural language commands. The game features:

- **Cooperative Team Control**: Players share control of units with teammates
- **AI Integration**: Natural language command processing with OpenAI GPT-4  
- **Client-Server Architecture**: Unified codebase supporting both client and server modes
- **Real-time Multiplayer**: ENet UDP networking with server authority
- **3D Visualization**: Full 3D game world with SubViewport integration

## Development Commands

### Running the Game
```bash
# Open in Godot Editor and run scenes/UnifiedMain.tscn
# The application auto-detects server vs client mode:
# - Server mode: headless or dedicated_server feature
# - Client mode: normal display available
```

### Environment Setup
```bash
# OpenAI API key (optional for AI features)
export OPENAI_API_KEY="your-api-key-here"
```

### Key Controls (In-Game)
- **WASD**: Camera movement  
- **Mouse**: Unit selection and commands
- **Enter**: Natural language command input
- **Tab**: Toggle between UI panels

## Core Architecture

### Unified Client-Server Design
The project uses a single codebase for both client and server through `scripts/unified_main.gd`. The `DependencyContainer` autoload manages mode-specific dependencies:

- **Server Mode**: Creates game state, session manager, AI systems, and dedicated server
- **Client Mode**: Creates network manager, display manager, and UI systems

### Key Systems

#### Dependency Injection (`scripts/core/dependency_container.gd`)
Central container managing all system dependencies. Use `dependency_container.get_[system]()` to access components rather than direct node references.

#### AI Command Processing (`scripts/ai/`)
- **OpenAI Integration**: `openai_client.gd` handles GPT-4 communication
- **Command Processing**: `ai_command_processor.gd` converts natural language to game actions
- **Plan Execution**: `plan_executor.gd` manages multi-step AI plans
- **Action Validation**: `action_validator.gd` ensures AI commands are valid

#### Unit System (`scripts/units/`)
- **AnimatedUnit**: CharacterBody3D-based units with Kenney character models
- **Team Spawning**: `team_unit_spawner.gd` manages team-based unit creation
- **Unit Types**: Scout, Tank, Sniper, Medic, Engineer with specialized abilities

#### Network Architecture (`scripts/server/` & `scripts/client/`)
- **Server Authority**: All game state managed server-side
- **Session Management**: `session_manager.gd` handles lobbies and matchmaking  
- **Client Display**: `client_display_manager.gd` synchronizes visual state

#### Gameplay Systems (`scripts/gameplay/`)
- **Node Capture**: Control point system for territorial control
- **Resource Management**: Energy economy for unit abilities
- **Entity Deployment**: Mines, turrets, and spires placement system

### Important Conventions

#### Unit Instantiation
- **MUST** instantiate units from scene files using `preload()` and `instantiate()`
- **NEVER** use `Unit.new()` for CharacterBody3D-based classes

#### Group Management
- Add units to `"units"` group for system discovery
- Add cameras to `"cameras"` and `"rts_cameras"` groups
- Use group-based queries for loose coupling

#### Coordinate Systems
- World coordinates: Global 3D positions
- Team-relative coordinates: Transformed relative to team bases
- Tile coordinates: Grid-based for gameplay systems

### Testing and Validation

#### Combat Test Suite
Access via `scenes/testing/CombatTestSuite.tscn` for comprehensive system testing including:
- Unit spawning and control
- AI command processing
- Network synchronization
- Selection system validation

#### Performance Requirements
- **Physics**: 60 Hz for smooth gameplay
- **Network**: 30 Hz state synchronization  
- **AI Processing**: 0.5-2 Hz for natural language commands

### Asset Integration

#### Kenney Asset Collections
Located in `assets/kenney/` with collections for:
- **Characters**: 18 character models for RTS units
- **City Buildings**: Commercial and industrial structures
- **Road Systems**: Modular road building blocks
- **Blaster Kit**: Weapons and combat effects

#### Material and Animation Systems
- Dynamic weapon attachment via attachment points
- Shared textures across models for memory efficiency
- AnimationTree for complex character state management

### Common Patterns

#### Service Access
```gdscript
# Always use dependency container
var logger = dependency_container.get_logger()
var game_state = dependency_container.get_game_state()
```

#### RPC Communication
```gdscript
# Server-to-client communication
@rpc("any_peer", "call_local", "reliable")
func handle_game_event(data: Dictionary):
    # Implementation
```

#### Signal-Based Communication
```gdscript
# Use signals for loose coupling
signal unit_selected(unit_id: String)
signal command_executed(command: String, success: bool)
```

### Development Guidelines

- Follow strict GDScript typing with type hints
- Use dependency injection rather than direct node access
- Implement proper cleanup in `_exit_tree()` 
- Use server-authoritative design for multiplayer consistency
- Validate all AI-generated actions before execution
- Implement proper error handling and fallbacks
- Follow the existing .cursorrules for code style and conventions

### Entry Points

- **Main Scene**: `scenes/UnifiedMain.tscn`
- **Lobby**: `scenes/ui/lobby.tscn` 
- **Game HUD**: `scenes/ui/game_hud.tscn`
- **Test Map**: `scenes/maps/test_map.tscn`
- **Combat Testing**: `scenes/testing/CombatTestSuite.tscn`