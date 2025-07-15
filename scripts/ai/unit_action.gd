# scripts/ai/unit_action.gd
class_name UnitAction
extends Resource

## The name of the action to execute. This should correspond to a method on the unit's script.
@export var action_name: String = ""

## A dictionary of parameters for the action. The keys should match the parameter names of the method.
@export var parameters: Dictionary = {}

func _init(p_action_name: String = "", p_params: Dictionary = {}):
    action_name = p_action_name
    parameters = p_params

## Executes the action on the given unit.
func execute(unit: Node) -> void:
    if not is_instance_valid(unit):
        printerr("UnitAction: execute() called with an invalid unit.")
        return

    # Try to call a method directly on the unit's script.
    if unit.has_method(action_name):
        var args = parameters.values()
        if args.is_empty():
            unit.call(action_name)
        else:
            unit.callv(action_name, args)
    else:
        # Fallback to EventBus for actions not on the unit script.
        # This allows for more decoupled command execution.
        var command_string = action_name
        if not parameters.is_empty():
            # A simple way to format parameters for the event bus.
            # Example: "move_to:{\"x\":10,\"y\":20}"
            command_string += ":" + JSON.stringify(parameters)
            
        var unit_id = ""
        if unit.has_method("get_unit_id"):
            unit_id = unit.get_unit_id()
        elif "unit_id" in unit:
            unit_id = unit.unit_id
            
        if not unit_id.is_empty() and has_node("/root/EventBus"):
            get_node("/root/EventBus").emit_unit_command(unit_id, command_string)
        else:
            printerr("UnitAction: Unit has no get_unit_id() method or unit_id property, or EventBus is not available. Cannot emit command.")