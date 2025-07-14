# GameController.gd
class_name GameController
extends Node

# Systems
var selection_manager = null
var command_input = null

func _ready() -> void:
    # Create selection manager
    var SelectionManagerScript = load("res://scripts/core/selection_manager.gd")
    selection_manager = SelectionManagerScript.new()
    selection_manager.name = "SelectionManager"
    add_child(selection_manager)
    
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
    
    Logger.info("GameController", "Game controller initialized")

func _on_command_entered(command_text: String) -> void:
    Logger.info("GameController", "Processing command: " + command_text)
    # Future: Process command through LLM and generate unit commands

func _on_radial_command(command: String) -> void:
    Logger.info("GameController", "Quick command: " + command)
    # Future: Execute quick command on selected units

func _on_units_selected(units: Array) -> void:
    Logger.info("GameController", "Units selected: " + str(units.size()))
    # Future: Update UI with selected units

func _on_units_deselected(units: Array) -> void:
    Logger.info("GameController", "Units deselected: " + str(units.size()))
    # Future: Update UI 