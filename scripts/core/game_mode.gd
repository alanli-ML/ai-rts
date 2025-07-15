# GameMode.gd - Manages game mode and dependencies
extends Node

enum Mode {
    CLIENT,
    SERVER,
    STANDALONE
}

# Current mode
var current_mode: Mode = Mode.CLIENT
var dependency_container: Node
var is_started: bool = false

# Determine mode based on runtime conditions
func setup(container: Node, mode: Mode) -> void:
    """Setup game mode with dependency container"""
    dependency_container = container
    current_mode = mode
    
    print("GameMode: Setup with mode %s" % get_mode_string())

func start() -> void:
    """Start the game mode"""
    if is_started:
        print("GameMode: Already started")
        return
    
    print("GameMode: Starting mode %s" % get_mode_string())
    
    # Create dependencies based on mode
    match current_mode:
        Mode.SERVER:
            dependency_container.create_server_dependencies()
        Mode.CLIENT:
            dependency_container.create_client_dependencies()
        Mode.STANDALONE:
            dependency_container.create_client_dependencies()
    
    is_started = true
    print("GameMode: Started successfully")

func get_mode_string() -> String:
    """Get string representation of current mode"""
    match current_mode:
        Mode.CLIENT:
            return "CLIENT"
        Mode.SERVER:
            return "SERVER"
        Mode.STANDALONE:
            return "STANDALONE"
        _:
            return "UNKNOWN"

func is_server() -> bool:
    """Check if in server mode"""
    return current_mode == Mode.SERVER

func is_client() -> bool:
    """Check if in client mode"""
    return current_mode == Mode.CLIENT

func is_standalone() -> bool:
    """Check if in standalone mode"""
    return current_mode == Mode.STANDALONE

func stop() -> void:
    """Stop the game mode"""
    if not is_started:
        return
    
    print("GameMode: Stopping mode %s" % get_mode_string())
    
    # Cleanup dependencies
    if dependency_container:
        dependency_container.cleanup()
    
    is_started = false
    print("GameMode: Stopped")

func cleanup() -> void:
    """Cleanup resources"""
    stop()
    print("GameMode: Cleanup complete") 