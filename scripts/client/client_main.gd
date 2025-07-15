# ClientMain.gd - Simple client main for unified architecture
extends Node

# Injected dependencies
var logger
var display_manager: Node

# Client state
var is_initialized: bool = false

func setup(logger_ref, display_manager_ref):
    """Setup dependencies - called by DependencyContainer"""
    logger = logger_ref
    display_manager = display_manager_ref
    
    logger.info("ClientMain", "Setting up client main")
    
    # Initialize client
    _initialize_client()

func _initialize_client():
    """Initialize the client"""
    is_initialized = true
    logger.info("ClientMain", "Client main initialized")

func cleanup() -> void:
    """Cleanup resources"""
    is_initialized = false
    logger.info("ClientMain", "Client main cleaned up") 