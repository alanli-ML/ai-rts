# TestAICommandProcessor.gd
class_name TestAICommandProcessor
extends Node

# Simple test implementation
func _ready() -> void:
    print("Test AI Command Processor initialized")

func setup(logger_instance, game_constants_instance, action_validator_instance, plan_executor_instance) -> void:
    print("Test setup called")
    
func process_command(command_text: String, selected_units: Array = [], game_state: Dictionary = {}) -> void:
    print("Test process command called: " + command_text)
    
func clear_command_queue() -> void:
    print("Test clear command queue called")
    
func is_command_processing() -> bool:
    return false 