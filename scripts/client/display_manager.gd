# ClientDisplayManager.gd - Client display manager with dependency injection
extends Node

# Injected dependencies
var logger
var game_constants

# Display state
var is_active: bool = false
var current_session_id: String = ""
var displayed_entities: Dictionary = {}

# Camera and viewport
var camera: Camera3D
var viewport: SubViewport

# UI elements
var resource_display: Control
var unit_selection_ui: Control
var command_input: Control

# Signals
signal entity_selected(entity_id: String)
signal command_issued(command: String)
signal display_updated()

func setup(logger_ref, constants_ref):
    """Setup dependencies - called by DependencyContainer"""
    logger = logger_ref
    game_constants = constants_ref
    
    logger.info("ClientDisplayManager", "Setting up client display manager")
    
    # Initialize display
    _initialize_display()

func _initialize_display():
    """Initialize the display system"""
    is_active = true
    logger.info("ClientDisplayManager", "Client display manager initialized")

func update_game_state(state_data: Dictionary) -> void:
    """Update the display with new game state"""
    if not is_active:
        return
    
    # Update entities
    var units = state_data.get("units", [])
    var buildings = state_data.get("buildings", [])
    
    # Update displayed entities
    for unit_data in units:
        var unit_id = unit_data.get("id", "")
        if unit_id != "":
            _update_entity_display(unit_id, unit_data)
    
    for building_data in buildings:
        var building_id = building_data.get("id", "")
        if building_id != "":
            _update_entity_display(building_id, building_data)
    
    # Update UI
    _update_ui(state_data)
    
    display_updated.emit()

func _update_entity_display(entity_id: String, entity_data: Dictionary) -> void:
    """Update an entity's display"""
    # This would be implemented based on the specific display needs
    logger.debug("ClientDisplayManager", "Updating entity display: %s" % entity_id)

func _update_ui(state_data: Dictionary) -> void:
    """Update the UI with new state"""
    # Update resource display
    var resources = state_data.get("resources", {})
    
    # Update game time
    var game_time = state_data.get("game_time", 0.0)
    
    # Update match state
    var match_state = state_data.get("match_state", "unknown")

func cleanup() -> void:
    """Cleanup resources"""
    is_active = false
    displayed_entities.clear()
    logger.info("ClientDisplayManager", "Client display manager cleaned up") 