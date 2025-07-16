# DependencyContainer.gd - Autoload for dependency injection
extends Node

# Shared dependencies
var logger
var game_constants
var network_messages

# Mode-specific dependencies
var game_state: Node
var dedicated_server: Node
var session_manager: Node
var client_main: Node
var network_manager: Node

# Core Systems
var ai_command_processor: Node
var action_validator: Node
var plan_executor: Node
var resource_manager: Node
var node_capture_system: Node
var team_unit_spawner: Node

# UI Systems  
var speech_bubble_manager: Node
var plan_progress_manager: Node

# Dependency state
var is_initialized: bool = false
var current_mode: String = "unknown"

# Preload shared classes
const GameConstantsClass = preload("res://scripts/shared/constants/game_constants.gd")
const NetworkMessagesClass = preload("res://scripts/shared/types/network_messages.gd")
const LoggerClass = preload("res://scripts/shared/utils/logger.gd")

# Mode-specific classes
const SessionManagerClass = preload("res://scripts/server/session_manager.gd")
const ClientMainClass = preload("res://scripts/client/client_main.gd")

# Preload Core System classes
const NetworkManagerClass = preload("res://scripts/core/network_manager.gd")
const AICommandProcessorClass = preload("res://scripts/ai/ai_command_processor.gd")
const ActionValidatorClass = preload("res://scripts/ai/action_validator.gd")
const PlanExecutorClass = preload("res://scripts/ai/plan_executor.gd")
const ResourceManagerClass = preload("res://scripts/gameplay/resource_manager.gd")
const NodeCaptureSystemClass = preload("res://scripts/gameplay/node_capture_system.gd")
const TeamUnitSpawnerClass = preload("res://scripts/units/team_unit_spawner.gd")

# Preload UI system classes
const SpeechBubbleManagerClass = preload("res://scripts/ui/speech_bubble_manager.gd")
const PlanProgressManagerClass = preload("res://scripts/ui/plan_progress_manager.gd")


func _ready() -> void:
    print("DependencyContainer: Initializing...")
    _create_shared_dependencies()
    is_initialized = true
    print("DependencyContainer: Initialized successfully")

func _create_shared_dependencies() -> void:
    logger = LoggerClass.new()
    logger.name = "Logger"
    add_child(logger)
    
    game_constants = GameConstantsClass.new()
    network_messages = NetworkMessagesClass.new()
    
    logger.info("DependencyContainer", "Shared dependencies created")

func create_server_dependencies() -> void:
    if not is_initialized:
        push_error("DependencyContainer not initialized")
        return
    
    current_mode = "server"
    
    # Create core server systems
    var ServerGameStateClass = load("res://scripts/server/server_game_state.gd")
    game_state = ServerGameStateClass.new()
    game_state.name = "GameState"
    add_child(game_state)
    
    session_manager = SessionManagerClass.new()
    session_manager.name = "SessionManager"
    add_child(session_manager)
    
    var DedicatedServerClass = load("res://scripts/server/dedicated_server.gd")
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
    
    plan_executor = PlanExecutorClass.new()
    plan_executor.name = "PlanExecutor"
    add_child(plan_executor)

    # Create gameplay systems
    resource_manager = ResourceManagerClass.new()
    resource_manager.name = "ResourceManager"
    add_child(resource_manager)
    
    node_capture_system = NodeCaptureSystemClass.new()
    node_capture_system.name = "NodeCaptureSystem"
    add_child(node_capture_system)
    
    team_unit_spawner = TeamUnitSpawnerClass.new()
    team_unit_spawner.name = "TeamUnitSpawner"
    add_child(team_unit_spawner)

    _setup_server_dependencies()
    logger.info("DependencyContainer", "Server dependencies created")

func _setup_server_dependencies() -> void:
    # Setup core dependencies
    game_state.setup(logger, game_constants, network_messages)
    session_manager.setup(logger, game_state)
    dedicated_server.setup(logger, session_manager)
    
    # Setup AI system dependencies
    ai_command_processor.setup(logger, game_constants, action_validator, plan_executor)
    plan_executor.setup(logger, game_state)
    
    # Setup gameplay systems
    team_unit_spawner.resource_manager = resource_manager
    
    _connect_server_systems()
    logger.info("DependencyContainer", "Server dependencies setup complete")

func create_client_dependencies() -> void:
    if not is_initialized:
        push_error("DependencyContainer not initialized")
        return
    
    current_mode = "client"

    # Create network manager for client
    network_manager = NetworkManagerClass.new()
    network_manager.name = "NetworkManager"
    add_child(network_manager)
    
    # Create client main
    client_main = ClientMainClass.new()
    client_main.name = "ClientMain"
    add_child(client_main)
    
    # Create UI systems (non-scene based)
    speech_bubble_manager = SpeechBubbleManagerClass.new()
    speech_bubble_manager.name = "SpeechBubbleManager"
    add_child(speech_bubble_manager)
    
    plan_progress_manager = PlanProgressManagerClass.new()
    plan_progress_manager.name = "PlanProgressManager"
    add_child(plan_progress_manager)
    
    # Setup client dependencies
    client_main.setup(logger, null) # display_manager is part of UI now
    
    # Setup UI system dependencies
    speech_bubble_manager.setup(logger, game_constants)
    plan_progress_manager.setup(logger, game_constants)
    
    logger.info("DependencyContainer", "Client dependencies created")

func _connect_server_systems() -> void:
    # Connect resource manager to node capture system
    if node_capture_system and resource_manager:
        node_capture_system.team_node_count_changed.connect(resource_manager.set_income_rate_for_team)
    
    logger.info("DependencyContainer", "Server systems connected")

# Getter methods for dependencies
func get_logger(): return logger
func get_network_manager(): return get_node_or_null("NetworkManager")
func get_game_constants(): return game_constants
func get_network_messages(): return network_messages
func get_game_state(): return game_state
func get_ai_command_processor(): return ai_command_processor
func get_resource_manager(): return resource_manager
func get_node_capture_system(): return node_capture_system
func get_team_unit_spawner(): return team_unit_spawner
func get_game_hud(): return null  # GameHUD is created from scene when match starts
func get_speech_bubble_manager(): return speech_bubble_manager
func get_plan_progress_manager(): return plan_progress_manager

func is_server_mode() -> bool:
    return current_mode == "server"

func is_client_mode() -> bool:
    return current_mode == "client"

func cleanup() -> void:
    logger.info("DependencyContainer", "Cleaning up dependencies")
    
    # Clean up mode-specific dependencies
    if game_state and is_instance_valid(game_state): game_state.queue_free()
    if dedicated_server and is_instance_valid(dedicated_server): dedicated_server.queue_free()
    if session_manager and is_instance_valid(session_manager): session_manager.queue_free()
    if client_main and is_instance_valid(client_main): client_main.queue_free()
    
    is_initialized = false
    logger.info("DependencyContainer", "Cleanup complete") 