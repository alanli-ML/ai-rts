# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AI-driven RTS game built with Godot 4.4 where players control AI minions using natural language commands. The game features OpenAI integration, lock-step multiplayer networking, and a vision-based AI system.

## Development Commands

### Godot Project
- Open project in Godot 4.4+ using `project.godot`
- Run the game from Godot editor or use the export templates
- Main scene: `res://scenes/Main.tscn`

### Node.js MCP Server (godot-mcp/)
- `npm run build` - Build the TypeScript project
- `npm run prepare` - Prepare for distribution (runs build)
- `npm run watch` - Watch for TypeScript changes
- `npm run inspector` - Run MCP inspector

### Environment Setup
Set OpenAI API key:
```bash
export OPENAI_API_KEY="your-key-here"
```

## Architecture Overview

### Core Singletons (Autoloaded)
- **GameManager** (`scripts/autoload/game_manager.gd`): Central game state management, unit registry, victory conditions
- **EventBus** (`scripts/autoload/event_bus.gd`): Global signal dispatching system for loose coupling
- **ConfigManager** (`scripts/autoload/config_manager.gd`): Game constants, unit stats, user settings

### Key Systems
- **Vision System**: Cone-based visibility (120° angle, 30m range) with line-of-sight raycasting
- **Unit Archetypes**: Scout, Tank, Sniper, Medic, Engineer with different stats and abilities
- **AI Integration**: OpenAI GPT-4 integration for natural language command processing
- **Networking**: Lock-step multiplayer with 3-frame delay, 30Hz simulation, 60Hz rendering
- **FSM Framework**: Finite State Machine for unit behaviors

### Data Flow
```
Player Command → LLM Processing → Plan Validation → Plan Execution → Unit FSM → Game Logic
```

### Directory Structure
- `scripts/core/`: Core game systems (camera, map, selection, units)
- `scripts/autoload/`: Singleton managers
- `scripts/units/`: Unit archetype implementations
- `scripts/ui/`: User interface components
- `scripts/networking/`: Multiplayer networking code
- `scripts/ai/`: AI behavior and processing
- `scenes/`: Godot scene files
- `resources/`: Game assets (models, textures, sounds)

## Code Conventions

### From .cursorrules
- Use strict typing in GDScript with type hints for all variables and functions
- Implement lifecycle functions with explicit `super()` calls
- Use `@onready` annotations instead of direct node references in `_ready()`
- Follow Godot naming conventions: PascalCase for nodes, snake_case for methods/variables
- Use signals for loose coupling between nodes
- Document complex functions with docstrings

### Project-Specific Patterns
- **Unit Registration**: Units auto-register with GameManager via EventBus signals
- **Team System**: Teams are identified by integers (1, 2), with team-specific unit tracking
- **Command System**: Commands flow through EventBus for decoupled communication
- **State Management**: Use GameManager.GameState enum for game phase tracking
- **Logging**: Use Logger singleton for consistent debug output

## Key Classes and Systems

### GameManager
- Manages game state transitions (MENU, LOBBY, IN_GAME, GAME_OVER)
- Maintains unit registry and team tracking
- Handles victory condition checking
- Tracks match time and player data

### EventBus
- Provides global signals for unit, building, player, and network events
- Use `EventBus.emit_unit_command()` for unit command dispatching
- All major game events should flow through EventBus

### ConfigManager
- Contains unit archetypes with stats (speed, health, vision, attack)
- Building types and their properties
- Network constants (port, latency, lockstep settings)
- AI constants (LLM timeouts, batch sizes, plan limits)

### Unit System
- Base unit class with common properties (health, team_id, position)
- Archetype-specific implementations (scout_unit.gd, tank_unit.gd, etc.)
- Vision system with cone-based line-of-sight calculations
- FSM integration for behavior states

## Development Notes

### Multiplayer Architecture
- Uses lock-step networking with 3-frame delay
- Server runs at 30Hz, clients render at 60Hz
- State synchronization with delta compression
- Input validation and replay system for cheat prevention

### AI Integration
- OpenAI GPT-4 integration for command processing
- Batch processing for multiple units (max 32 per batch)
- Plan validation and execution system
- Vision-based AI with limited information (no omniscience)

### Performance Considerations
- Object pooling for projectiles and effects
- Network compression for state updates
- Vision system uses raycasting for line-of-sight
- Physics runs at 60Hz, game logic at 30Hz

## Testing and Debugging

### Unit Testing
- Use GameManager.print_debug_info() for system state
- EventBus.log_event() for event debugging
- Logger singleton for consistent debug output

### Performance Testing
- Monitor unit registry size with GameManager.get_total_unit_count()
- Check vision system performance with multiple units
- Test network synchronization with artificial latency