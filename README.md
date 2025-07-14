# AI-RTS: Cooperative Real-Time Strategy Game

## 🎮 Project Overview

AI-RTS is an innovative cooperative real-time strategy game built with Godot 4.4, featuring team-based shared unit control where 2 players per team control the same 5 units collaboratively in 2v2 matches. The game integrates AI-powered natural language commands for intuitive unit control.

## ✨ Key Features

### 🤝 Cooperative Gameplay
- **Shared Unit Control**: Multiple players control the same units simultaneously
- **Team-Based Strategy**: 2v2 matches with coordinated team gameplay
- **Seamless Collaboration**: Real-time shared control without conflicts

### 🤖 AI Integration
- **Natural Language Commands**: Control units using plain English
- **OpenAI Integration**: Powered by GPT for intelligent command interpretation
- **Voice Command Support**: Speak commands directly to your units
- **Context-Aware**: AI understands game state and unit capabilities

### 🎯 Unit System
- **5 Unit Types**: Scout, Soldier, Tank, Medic, Engineer
- **Unique Abilities**: Each unit type has distinct roles and capabilities
- **Combat System**: Health, damage, and tactical combat mechanics
- **Vision System**: Realistic fog of war and unit detection

### 🌐 Multiplayer Architecture
- **Dedicated Server**: Scalable server architecture for multiplayer matches
- **Real-time Synchronization**: Server-authoritative game state
- **100 Client Capacity**: Supports large-scale multiplayer sessions
- **Session Management**: Automatic matchmaking and session cleanup

## 🚀 Quick Start

### Prerequisites
- Godot 4.4.1 or later
- OpenAI API key (optional, for AI features)

### Running the Game
1. Clone the repository
2. Open `project.godot` in Godot
3. Run the main scene (`scenes/Main.tscn`)

### Controls
- **Camera**: WASD/Arrow keys to pan, Mouse wheel to zoom
- **Unit Selection**: Click and drag to select units
- **Commands**: Press Enter to type AI commands
- **Voice**: Press 'V' for voice commands (if configured)

## 🛠️ Technical Architecture

### Core Systems
- **Game Manager**: Central game state management
- **Selection System**: Multi-unit selection with visual feedback
- **Command Processing**: AI-powered command interpretation
- **Network Layer**: ENetMultiplayerPeer for real-time communication

### AI Components
- **OpenAI Client**: Natural language processing
- **Command Translator**: Converts AI responses to game commands
- **Voice Recognition**: Speech-to-text integration

### Dedicated Server
- **Server-Authoritative**: All game logic runs on server
- **Real-time Physics**: Server-side collision and movement
- **AI Integration**: Server processes AI commands
- **Session Management**: Automatic player matchmaking

## 🎮 Development Status

### ✅ Completed Features
- [x] Cooperative team-based unit control
- [x] 5 unit types with unique abilities
- [x] AI natural language command processing
- [x] Real-time multiplayer with dedicated server
- [x] Vision and combat systems
- [x] Session management and matchmaking
- [x] Comprehensive testing framework

### 🔄 Current Phase
**Phase 4**: Client-Server Integration
- Migrating client game to use dedicated server
- Implementing client-side prediction
- Adding visual synchronization

## 🧪 Testing

### Test Coverage
- Unit spawning and management
- Combat and healing mechanics
- AI command processing
- Multiplayer networking
- Session management
- Client-server communication

### Running Tests
```bash
# Run main game tests
godot scenes/Main.tscn

# Run dedicated server tests
cd game-server
godot --headless scenes/main.gd

# Run client connection tests
godot TestServerClient.tscn
```

## 🏗️ Project Structure

```
ai-rts/
├── scenes/                 # Game scenes
│   ├── Main.tscn          # Main game scene
│   ├── units/             # Unit scene templates
│   └── ui/                # User interface
├── scripts/               # Game logic
│   ├── core/              # Core systems
│   ├── ai/                # AI integration
│   ├── ui/                # UI controllers
│   └── autoload/          # Singleton systems
├── game-server/           # Dedicated server
│   ├── server/            # Server core
│   ├── multiplayer/       # Multiplayer logic
│   └── game_logic/        # Game systems
└── resources/             # Assets and resources
```

## 🔧 Configuration

### Environment Variables
- `OPENAI_API_KEY`: Your OpenAI API key for AI features
- `SERVER_PORT`: Dedicated server port (default: 7777)
- `MAX_CLIENTS`: Maximum client connections (default: 100)

### Game Settings
- Team sizes: 2 players per team
- Unit count: 5 units per team
- Match format: 2v2 multiplayer

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Follow the `.cursorrules` coding guidelines
4. Add tests for new features
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Built with Godot 4.4
- AI powered by OpenAI
- Networking with ENetMultiplayerPeer
- Testing framework for comprehensive validation

## 📞 Support

For questions, issues, or contributions, please open an issue on GitHub.

---

**Current Version**: 1.0.0 (Phase 4 Implementation Complete)
**Last Updated**: December 2024 