# GameController.gd
class_name GameController
extends Node

# Systems
var selection_manager = null
var command_input = null
var ai_command_processor = null
var command_translator = null

func _ready() -> void:
    # Create selection manager
    var SelectionManagerScript = load("res://scripts/core/selection_manager.gd")
    selection_manager = SelectionManagerScript.new()
    selection_manager.name = "SelectionManager"
    add_child(selection_manager)
    
    # Create AI command processor
    var AICommandProcessorScript = load("res://scripts/ai/ai_command_processor.gd")
    ai_command_processor = AICommandProcessorScript.new()
    ai_command_processor.name = "AICommandProcessor"
    add_child(ai_command_processor)
    
    # Create command translator
    var CommandTranslatorScript = load("res://scripts/ai/command_translator.gd")
    command_translator = CommandTranslatorScript.new()
    command_translator.name = "CommandTranslator"
    add_child(command_translator)
    
    # Create command input UI
    var CommandInputScript = load("res://scripts/ui/command_input_simple.gd")
    command_input = CommandInputScript.new()
    command_input.name = "CommandInput"
    add_child(command_input)
    
    # Connect to EventBus signals
    EventBus.ui_command_entered.connect(_on_command_entered)
    EventBus.ui_radial_command.connect(_on_radial_command)
    
    # Connect selection manager signals
    selection_manager.units_selected.connect(_on_units_selected)
    selection_manager.units_deselected.connect(_on_units_deselected)
    
    # Connect AI system signals
    ai_command_processor.command_processed.connect(_on_ai_command_processed)
    ai_command_processor.command_failed.connect(_on_ai_command_failed)
    ai_command_processor.processing_started.connect(_on_ai_processing_started)
    ai_command_processor.processing_finished.connect(_on_ai_processing_finished)
    
    command_translator.command_executed.connect(_on_command_executed)
    command_translator.command_failed.connect(_on_command_failed)
    
    Logger.info("GameController", "Game controller initialized with AI systems")

func _on_command_entered(command_text: String) -> void:
    Logger.info("GameController", "Processing AI command: " + command_text)
    
    # Get current selected units and game state
    var selected_units = selection_manager.selected_units if selection_manager else []
    var game_state = _get_current_game_state()
    
    # Process command through AI
    ai_command_processor.process_command(command_text, selected_units, game_state)

func _on_radial_command(command: String) -> void:
    Logger.info("GameController", "Quick command: " + command)
    # Process quick commands through AI as well for consistency
    _on_command_entered(command)

func _on_units_selected(units: Array) -> void:
    Logger.info("GameController", "Units selected: " + str(units.size()))
    # Update UI or other systems as needed
    EventBus.emit_signal("selection_changed", units)

func _on_units_deselected(units: Array) -> void:
    Logger.info("GameController", "Units deselected: " + str(units.size()))
    # Update UI or other systems as needed
    EventBus.emit_signal("selection_changed", [])

func _on_ai_command_processed(commands: Array, message: String) -> void:
    """Handle successfully processed AI command"""
    Logger.info("GameController", "AI processed command: " + message)
    
    # Execute commands through translator
    command_translator.execute_commands(commands)
    
    # Show AI response to player
    _show_ai_response(message)

func _on_ai_command_failed(error: String) -> void:
    """Handle AI command processing failure"""
    Logger.error("GameController", "AI command failed: " + error)
    _show_ai_error(error)

func _on_ai_processing_started() -> void:
    """Handle AI processing start"""
    Logger.info("GameController", "AI processing started")
    _show_ai_thinking()

func _on_ai_processing_finished() -> void:
    """Handle AI processing finish"""
    Logger.info("GameController", "AI processing finished")
    _hide_ai_thinking()

func _on_command_executed(_command_id: int, result: String) -> void:
    """Handle successful command execution"""
    Logger.info("GameController", "Command executed: " + result)
    _show_command_result(result)

func _on_command_failed(_command_id: int, error: String) -> void:
    """Handle command execution failure"""
    Logger.error("GameController", "Command failed: " + error)
    _show_command_error(error)

func _get_current_game_state() -> Dictionary:
    """Get current game state for AI context"""
    var game_state = {
        "match_time": 0.0,
        "team_id": 1,
        "enemy_visible": false,
        "map_bounds": {"min": [-50, -50, -50], "max": [50, 50, 50]}
    }
    
    # Get game time if available
    if GameManager and GameManager.has_method("get_game_time"):
        game_state.match_time = GameManager.get_game_time()
    
    # Get team information
    if GameManager and GameManager.has_method("get_local_team_id"):
        game_state.team_id = GameManager.get_local_team_id()
    
    # Check for visible enemies
    var visible_enemies = get_tree().get_nodes_in_group("enemies")
    game_state.enemy_visible = not visible_enemies.is_empty()
    
    return game_state

func _show_ai_response(message: String) -> void:
    """Show AI response to player"""
    # For now, just log it. In the future, show in UI
    Logger.info("GameController", "AI: " + message)

func _show_ai_error(error: String) -> void:
    """Show AI error to player"""
    Logger.error("GameController", "AI Error: " + error)

func _show_ai_thinking() -> void:
    """Show AI thinking indicator"""
    Logger.info("GameController", "AI is thinking...")

func _hide_ai_thinking() -> void:
    """Hide AI thinking indicator"""
    Logger.info("GameController", "AI thinking complete")

func _show_command_result(result: String) -> void:
    """Show command execution result"""
    Logger.info("GameController", "Command result: " + result)

func _show_command_error(error: String) -> void:
    """Show command execution error"""
    Logger.error("GameController", "Command error: " + error)

func get_ai_status() -> Dictionary:
    """Get AI system status"""
    var status = {
        "ai_available": ai_command_processor != null,
        "processing": false,
        "queue_size": 0,
        "selected_units": 0
    }
    
    if ai_command_processor:
        status.processing = ai_command_processor.is_processing()
        status.queue_size = ai_command_processor.get_queue_size()
    
    if selection_manager:
        status.selected_units = selection_manager.selected_units.size()
    
    return status 