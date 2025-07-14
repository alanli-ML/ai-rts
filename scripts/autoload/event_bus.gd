# EventBus.gd
extends Node

# Unit Events
@warning_ignore("unused_signal")
signal unit_spawned(unit: Variant)
@warning_ignore("unused_signal")
signal unit_died(unit: Variant)
@warning_ignore("unused_signal")
signal unit_selected(unit: Variant)
@warning_ignore("unused_signal")
signal unit_deselected(unit: Variant)
signal unit_command_issued(unit_id: String, command: String)
@warning_ignore("unused_signal")
signal unit_spawn_requested(archetype: String, team_id: int, position: Vector3)
@warning_ignore("unused_signal")
signal unit_destroy_requested(unit_id: String)
@warning_ignore("unused_signal")
signal unit_command_received(command: Dictionary)
@warning_ignore("unused_signal")
signal enemy_sighted(sighting_report: Dictionary)

# Building Events
@warning_ignore("unused_signal")
signal building_placed(building: Variant)
@warning_ignore("unused_signal")
signal building_completed(building: Variant)
@warning_ignore("unused_signal")
signal building_destroyed(building: Variant)

# Node Events
@warning_ignore("unused_signal")
signal node_captured(node_id: String, team: String)
@warning_ignore("unused_signal")
signal node_lost(node_id: String, team: String)

# Player Events
@warning_ignore("unused_signal")
signal player_joined(peer_id: int, player_info: Dictionary)
@warning_ignore("unused_signal")
signal player_left(peer_id: int)
@warning_ignore("unused_signal")
signal player_ready(peer_id: int)

# UI Events
@warning_ignore("unused_signal")
signal ui_command_entered(command: String)
@warning_ignore("unused_signal")
signal ui_radial_command(command_id: String)

# Network Events
@warning_ignore("unused_signal")
signal network_peer_connected(peer_id: int)
@warning_ignore("unused_signal")
signal network_peer_disconnected(peer_id: int)
@warning_ignore("unused_signal")
signal network_connection_failed()
@warning_ignore("unused_signal")
signal network_server_created()

func _ready() -> void:
    print("EventBus initialized")

# Helper function to emit unit commands
func emit_unit_command(unit_id: String, command: String) -> void:
    unit_command_issued.emit(unit_id, command)
    print("Command issued: %s -> %s" % [unit_id, command])

# Helper function for debug logging
func log_event(event_name: String, data: Dictionary = {}) -> void:
    if OS.is_debug_build():
        print("[EVENT] %s: %s" % [event_name, data]) 