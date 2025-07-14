# AI-Driven RTS Game - MVP Implementation

A competitive 1v1 RTS where players command AI minions using natural language, powered by Godot 4 and OpenAI.

## Project Overview

This is an innovative RTS game where each player controls up to 10 personality-driven robotic minions through natural language commands. The AI interprets these commands via OpenAI and converts them into multi-step tactical plans that units execute over several seconds.

### Key Features
- **Natural Language Control**: Issue commands in plain English
- **Vision-Based AI**: Units only know what they can see (120° cone, 30m range)
- **Personality System**: Each unit has a customizable system prompt affecting behavior
- **Multi-Step Planning**: AI generates complex plans with conditional triggers
- **Speech Bubbles**: Units communicate their actions with personality
- **Node Capture**: Control strategic points to build structures
- **Deterministic Multiplayer**: Lock-step networking for competitive play

## Documentation Structure

### 📋 Planning Documents
- **[mvp_implementation_plan.md](mvp_implementation_plan.md)** - Complete 12-week development roadmap
- **[weekly_breakdown.md](weekly_breakdown.md)** - Detailed day-by-day task breakdown
- **[week1_starter_guide.md](week1_starter_guide.md)** - Step-by-step guide for initial setup

### 🏗️ Technical Documents
- **[technical_architecture.md](technical_architecture.md)** - System architecture and code examples

## Quick Start

### Prerequisites
- Godot 4.4+
- OpenAI API key
- Git

### Setup Instructions
1. Clone this repository
2. Open project in Godot 4.4+
3. Follow [week1_starter_guide.md](week1_starter_guide.md) for initial setup
4. Set your OpenAI API key in environment variables:
   ```bash
   export OPENAI_API_KEY="your-key-here"
   ```

## Development Timeline

### Phase 1: Core Setup (Weeks 1-2) ✅
- Project structure and singletons
- Basic map and environment
- Camera and input systems

### Phase 2: Units & AI (Weeks 3-4)
- Unit archetypes (Scout, Tank, Sniper, Medic, Engineer)
- Vision system and fog of war
- Finite State Machine framework

### Phase 3: Networking (Weeks 5-6)
- Multiplayer lobby system
- Lock-step synchronization
- Client prediction and interpolation

### Phase 4: LLM Integration (Weeks 7-8)
- OpenAI API connection
- Command parsing and validation
- Plan execution system

### Phase 5: Gameplay (Weeks 9-10)
- Node capture mechanics
- Building system (Spire, Tower, Relay Pad)
- Combat and special actions

### Phase 6: Polish (Weeks 11-12)
- UI/UX implementation
- Speech bubble system
- Post-match summary and ELO

## Architecture Overview

```
Client (60 Hz) → Commands → Server (30 Hz) → LLM Bridge (0.5-2 Hz)
                                ↓
                          Plan Validator
                                ↓
                          Plan Executor → FSM → Game Logic
```

### Core Systems
- **GameManager**: Overall game state management
- **EventBus**: Global signal dispatching
- **ConfigManager**: Game constants and settings
- **LLMBridge**: OpenAI integration and batching
- **PlanExecutor**: Multi-step AI plan execution
- **VisionSystem**: Cone-based visibility calculations

## MVP Requirements Checklist

- [ ] Online 1v1 matches (15+ minutes)
- [ ] OpenAI integration (<1s latency)
- [ ] 5 minion archetypes
- [ ] System prompt customization
- [ ] 3 building types
- [ ] 9-node map with fog of war
- [ ] Vision-based knowledge system
- [ ] Multi-step plan execution
- [ ] Speech bubble system
- [ ] Core actions (move, peek_and_fire, lay_mines, hijack)
- [ ] Command UI (radial + text)
- [ ] Post-match summary
- [ ] ELO rating system
- [ ] Replay system

## Technologies Used

- **Engine**: Godot 4.4 (GDScript)
- **AI**: OpenAI GPT-4
- **Networking**: Godot High-Level Multiplayer API
- **Assets**: Kenney.nl 3D models
- **Rendering**: Forward+ with toon shading

## Contributing

This is an MVP implementation following the provided PRD. Please refer to the weekly breakdown for current development priorities.

## License

[Your License Here]

## Acknowledgments

- Kenney.nl for 3D assets
- OpenAI for LLM capabilities
- Godot Engine community 