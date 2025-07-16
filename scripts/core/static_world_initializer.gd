# StaticWorldInitializer.gd - This script has been intentionally disabled.
# All world initialization logic is now handled by the SessionManager and other
# modern systems to prevent duplicate entity spawning.
class_name StaticWorldInitializer
extends Node

signal static_world_initialized()

func setup(_logger_instance, _scene_3d_instance, _control_points_container_instance, _buildings_container_instance, _units_container_instance) -> void:
    # This function is intentionally left empty.
    pass

func initialize_static_world() -> void:
    # This function is intentionally left empty but emits the signal
    # to ensure any dependent systems can continue their flow without crashing.
    static_world_initialized.emit()

func cleanup() -> void:
    # This function is intentionally left empty.
    pass