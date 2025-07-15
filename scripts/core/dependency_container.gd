# DependencyContainer.gd - Autoload for dependency injection
extends Node

# Shared dependencies - use generic types to avoid class_name issues
var game_constants
var network_messages
var logger

# Mode-specific dependencies
var game_state: Node
var dedicated_server: Node
var session_manager: Node
var display_manager: Node
var client_main: Node

# New gameplay systems
var ai_command_processor: Node
var action_validator: Node
var plan_executor: Node
var langsmith_client: Node
var trigger_evaluation_engine: Node
var resource_manager: Node
var node_capture_system: Node
var building_system: Node

# New UI systems
var game_hud: Node
var speech_bubble_manager: Node
var plan_progress_manager: Node

# Procedural generation system
var map_generator: Node
var asset_loader: Node

# Dependency state
var is_initialized: bool = false
var current_mode: String = "unknown"

# Preload shared classes
const GameConstantsClass = preload("res://scripts/shared/constants/game_constants.gd")
const NetworkMessagesClass = preload("res://scripts/shared/types/network_messages.gd")
const LoggerClass = preload("res://scripts/shared/utils/logger.gd")
const GameEnumsClass = preload("res://scripts/shared/types/game_enums.gd")

# Preload mode-specific classes
const GameStateClass = preload("res://scripts/server/game_state.gd")
const DedicatedServerClass = preload("res://scripts/server/dedicated_server.gd")
const SessionManagerClass = preload("res://scripts/server/session_manager.gd")
const DisplayManagerClass = preload("res://scripts/client/display_manager.gd")
const ClientMainClass = preload("res://scripts/client/client_main.gd")

# Preload new AI system classes
const AICommandProcessorClass = preload("res://scripts/ai/ai_command_processor.gd")
const ActionValidatorClass = preload("res://scripts/ai/action_validator.gd")
const PlanExecutorClass = preload("res://scripts/ai/plan_executor.gd")
const LangSmithClientClass = preload("res://scripts/ai/langsmith_client.gd")
const TriggerEvaluationEngineClass = preload("res://scripts/ai/trigger_evaluation_engine.gd")

# Preload new gameplay system classes
const ResourceManagerClass = preload("res://scripts/gameplay/resource_manager.gd")
const NodeCaptureSystemClass = preload("res://scripts/gameplay/node_capture_system.gd")
# const BuildingClass = preload("res://scripts/buildings/building.gd")

# Preload new UI system classes
const GameHUDClass = preload("res://scripts/ui/game_hud.gd")
const SpeechBubbleManagerClass = preload("res://scripts/ui/speech_bubble_manager.gd")
const PlanProgressManagerClass = preload("res://scripts/ui/plan_progress_manager.gd")

# Preload procedural generation system classes
const MapGeneratorClass = preload("res://scripts/procedural/map_generator.gd")
const AssetLoaderClass = preload("res://scripts/procedural/asset_loader.gd")

# Initialization
func _ready() -> void:
    print("DependencyContainer: Initializing...")
    
    # Create shared dependencies
    _create_shared_dependencies()
    
    is_initialized = true
    print("DependencyContainer: Initialized successfully")

func _create_shared_dependencies() -> void:
    """Create shared dependencies that both client and server need"""
    
    # Create logger first
    logger = LoggerClass.new()
    logger.name = "Logger"
    add_child(logger)
    
    # TEMPORARY: Disable INFO level logs from procedural generation system
    logger.set_log_level(logger.LogLevel.WARNING)
    
    # Create game constants (not a Node)
    game_constants = GameConstantsClass.new()
    
    # Create network messages (not a Node)
    network_messages = NetworkMessagesClass.new()
    
    # Create shared procedural generation systems
    asset_loader = AssetLoaderClass.new()
    asset_loader.name = "AssetLoader"
    add_child(asset_loader)
    asset_loader.setup(logger)
    
    logger.info("DependencyContainer", "Shared dependencies created")

func create_server_dependencies() -> void:
    """Create server-specific dependencies"""
    if not is_initialized:
        push_error("DependencyContainer not initialized")
        return
    
    current_mode = "server"
    
    # Create core server systems
    game_state = GameStateClass.new()
    game_state.name = "GameState"
    add_child(game_state)
    
    session_manager = SessionManagerClass.new()
    session_manager.name = "SessionManager"
    add_child(session_manager)
    
    dedicated_server = DedicatedServerClass.new()
    dedicated_server.name = "DedicatedServer"
    add_child(dedicated_server)
    
    # Create AI systems
    ai_command_processor = AICommandProcessorClass.new()
    ai_command_processor.name = "AICommandProcessor"
    add_child(ai_command_processor)
    
    action_validator = ActionValidatorClass.new()
    action_validator.name = "ActionValidator"
    add_child(action_validator)
    
    # Create LangSmith client for LLM observability
    langsmith_client = LangSmithClientClass.new()
    langsmith_client.name = "LangSmithClient"
    add_child(langsmith_client)
    
    # Create Trigger Evaluation Engine
    trigger_evaluation_engine = TriggerEvaluationEngineClass.new()
    trigger_evaluation_engine.name = "TriggerEvaluationEngine"
    add_child(trigger_evaluation_engine)
    
    # Create gameplay systems
    resource_manager = ResourceManagerClass.new()
    resource_manager.name = "ResourceManager"
    add_child(resource_manager)
    
    node_capture_system = NodeCaptureSystemClass.new()
    node_capture_system.name = "NodeCaptureSystem"
    add_child(node_capture_system)
    
    # Create procedural generation system (server-only)
    map_generator = MapGeneratorClass.new()
    map_generator.name = "MapGenerator"
    add_child(map_generator)
    map_generator.setup(logger, asset_loader)
    
    # Setup dependencies
    _setup_server_dependencies()
    
    logger.info("DependencyContainer", "Server dependencies created")

func _setup_server_dependencies() -> void:
    """Setup server system dependencies after creation"""
    
    # Setup core dependencies
    game_state.setup(logger, game_constants, network_messages)
    session_manager.setup(logger, game_state)
    dedicated_server.setup(logger, session_manager)
    
    # Setup AI system dependencies
    ai_command_processor.setup(logger, game_constants, action_validator, null)
    
    # Setup gameplay system dependencies
    # node_capture_system uses _ready() for initialization
    
    # Connect systems
    _connect_server_systems()
    
    logger.info("DependencyContainer", "Server dependencies setup complete")

func create_client_dependencies() -> void:
    """Create client-specific dependencies"""
    if not is_initialized:
        push_error("DependencyContainer not initialized")
        return
    
    current_mode = "client"
    
    # Create display manager
    display_manager = DisplayManagerClass.new()
    display_manager.name = "DisplayManager"
    add_child(display_manager)
    
    # Create client main
    client_main = ClientMainClass.new()
    client_main.name = "ClientMain"
    add_child(client_main)
    
    # Create UI systems
    game_hud = GameHUDClass.new()
    game_hud.name = "GameHUD"
    add_child(game_hud)
    
    speech_bubble_manager = SpeechBubbleManagerClass.new()
    speech_bubble_manager.name = "SpeechBubbleManager"
    add_child(speech_bubble_manager)
    
    plan_progress_manager = PlanProgressManagerClass.new()
    plan_progress_manager.name = "PlanProgressManager"
    add_child(plan_progress_manager)
    
    # Create Trigger Evaluation Engine for client-side evaluation if needed for UI/FX
    trigger_evaluation_engine = TriggerEvaluationEngineClass.new()
    trigger_evaluation_engine.name = "TriggerEvaluationEngine"
    add_child(trigger_evaluation_engine)
    
    # Create procedural generation system for client mode (for unified testing)
    map_generator = MapGeneratorClass.new()
    map_generator.name = "MapGenerator"
    add_child(map_generator)
    map_generator.setup(logger, asset_loader)
    
    # Setup client dependencies
    display_manager.setup(logger, game_constants)
    client_main.setup(logger, display_manager)
    
    # Setup UI system dependencies
    game_hud.setup(logger, game_constants)
    speech_bubble_manager.setup(logger, game_constants)
    plan_progress_manager.setup(logger, game_constants)
    
    # Connect client systems
    _connect_client_systems()
    
    logger.info("DependencyContainer", "Client dependencies created")

func _connect_server_systems() -> void:
    """Connect server systems with proper signal connections"""
    
    # Connect AI systems
    # ai_command_processor.plan_created.connect(plan_executor._on_plan_created)
    # plan_executor.plan_step_completed.connect(ai_command_processor._on_plan_step_completed)
    # plan_executor.plan_failed.connect(ai_command_processor._on_plan_failed)
    
    # Connect resource management - TODO: Add these signal handlers to ServerGameState
    # resource_manager.resource_changed.connect(game_state._on_resource_changed)
    # resource_manager.resource_depleted.connect(game_state._on_resource_depleted)
    
    # Connect control points - TODO: Add these signal handlers to ServerGameState
    # node_capture_system.control_point_captured.connect(game_state._on_control_point_captured)
    # node_capture_system.victory_achieved.connect(game_state._on_victory_achieved)
    
    logger.info("DependencyContainer", "Server systems connected")

func _connect_client_systems() -> void:
    """Connect client systems with proper signal connections"""
    
    # Connect UI systems to EventBus
    # EventBus.game_state_updated.connect(game_hud._on_game_state_updated)
    # EventBus.resource_updated.connect(game_hud._on_resource_updated)
    # EventBus.control_point_updated.connect(game_hud._on_control_point_updated)
    
    # Connect speech bubble system
    # EventBus.unit_speech_requested.connect(speech_bubble_manager._on_unit_speech_requested)
    # EventBus.plan_step_completed.connect(speech_bubble_manager._on_plan_step_completed)
    
    # Connect plan progress system
    # EventBus.plan_started.connect(plan_progress_manager._on_plan_started)
    # EventBus.plan_progress_updated.connect(plan_progress_manager._on_plan_progress_updated)
    # EventBus.plan_completed.connect(plan_progress_manager._on_plan_completed)
    
    logger.info("DependencyContainer", "Client systems connected")

# Getter methods for dependencies
func get_logger():
    return logger

func get_game_constants():
    return game_constants

func get_network_messages():
    return network_messages

func get_game_state():
    return game_state

func get_ai_command_processor():
    return ai_command_processor

func get_resource_manager():
    return resource_manager

func get_node_capture_system():
    return node_capture_system

func get_game_hud():
    return game_hud

func get_speech_bubble_manager():
    return speech_bubble_manager

func get_plan_progress_manager():
    return plan_progress_manager

func get_langsmith_client() -> Node:
    """Get the LangSmith client instance"""
    return langsmith_client

func get_trigger_evaluation_engine() -> Node:
    """Get the TriggerEvaluationEngine instance"""
    return trigger_evaluation_engine

func get_map_generator() -> Node:
    """Get the MapGenerator instance"""
    return map_generator

func get_asset_loader() -> Node:
    """Get the AssetLoader instance"""
    return asset_loader

func is_server_mode() -> bool:
    return current_mode == "server"

func is_client_mode() -> bool:
    return current_mode == "client"

func cleanup() -> void:
    """Cleanup all dependencies"""
    logger.info("DependencyContainer", "Cleaning up dependencies")
    
    # Clean up mode-specific dependencies
    if game_state and game_state.has_method("cleanup"):
        game_state.cleanup()
    
    if dedicated_server and dedicated_server.has_method("cleanup"):
        dedicated_server.cleanup()
    
    if session_manager and session_manager.has_method("cleanup"):
        session_manager.cleanup()
    
    if display_manager and display_manager.has_method("cleanup"):
        display_manager.cleanup()
    
    if client_main and client_main.has_method("cleanup"):
        client_main.cleanup()
    
    # Clean up shared dependencies
    if logger and logger.has_method("cleanup"):
        logger.cleanup()
    
    is_initialized = false
    logger.info("DependencyContainer", "Cleanup complete") 