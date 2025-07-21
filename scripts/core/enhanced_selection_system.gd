# EnhancedSelectionSystem.gd - Rewritten for simplicity and robustness
class_name EnhancedSelectionSystem
extends Control

const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

signal selection_changed(selected_units: Array)
signal unit_hovered(unit: Unit)

var camera: Camera3D
var game_world: World3D = null
var selected_units: Array[Unit] = []
var hovered_unit: Unit = null

# Box selection
var is_box_selecting: bool = false
var box_start_position: Vector2 = Vector2.ZERO
var box_end_position: Vector2 = Vector2.ZERO

func _ready():
    GameConstants.debug_print("EnhancedSelectionSystem: Initializing selection system...", "SELECTION")
    
    # Add to selection_systems group so GameHUD can find us
    add_to_group("selection_systems")
    
    # Configure Control node to receive mouse events properly
    # Set mouse filter to STOP to ensure we receive events but don't pass them through
    mouse_filter = Control.MOUSE_FILTER_STOP
    
    # Set size to fill the screen to capture all mouse events
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    
    # Ensure this node is positioned correctly in the scene tree
    # Move to front if it's not already, so mouse events reach us first
    move_to_front()
    
    # Get viewport size for box selection
    var viewport = get_viewport()
    if viewport:
        size = viewport.get_visible_rect().size
    
    GameConstants.debug_print("EnhancedSelectionSystem: Setup complete, mouse_filter=%d, waiting for camera..." % mouse_filter, "SELECTION")
    
    # Find camera after a frame delay
    call_deferred("_find_camera")

func _find_camera():
    # Wait a frame to ensure all nodes are ready
    await get_tree().process_frame
    
    # Try multiple camera detection methods
    camera = get_viewport().get_camera_3d()
    
    # If direct camera not found, look for RTSCamera system
    if not camera:
        var rts_cameras = get_tree().get_nodes_in_group("rts_cameras")
        if rts_cameras.size() > 0:
            var rts_camera = rts_cameras[0]
            # RTSCamera has a camera_3d property
            if rts_camera.has_method("get") and "camera_3d" in rts_camera:
                camera = rts_camera.camera_3d
            elif rts_camera.has_method("get_camera_3d"):
                camera = rts_camera.get_camera_3d()
            else:
                # Look for Camera3D child in RTSCamera
                for child in rts_camera.get_children():
                    if child is Camera3D:
                        camera = child
                        break
    
    # Final fallback: search the entire scene tree
    if not camera:
        camera = get_tree().get_first_node_in_group("cameras")
    
    if camera:
        print("EnhancedSelectionSystem: Camera found successfully: %s (parent: %s)" % [camera.name, camera.get_parent().name if camera.get_parent() else "None"])
        var viewport = camera.get_viewport()
        if viewport:
            game_world = viewport.world_3d
            print("EnhancedSelectionSystem: Game world reference obtained from camera's viewport.")
        else:
            print("EnhancedSelectionSystem: WARNING - Camera has no viewport, click selection may fail.")
    else:
        print("EnhancedSelectionSystem: WARNING - No camera found, but input will remain enabled")
        # Don't disable input - keep trying to find camera each frame
        set_process(true)  # Enable _process to keep looking for camera

func _find_camera_fallback():
    # Quick camera search without disabling input
    var viewport_camera = get_viewport().get_camera_3d()
    if viewport_camera:
        camera = viewport_camera
        var viewport = camera.get_viewport()
        if viewport:
            game_world = viewport.world_3d
        set_process(false)  # Stop searching once found
        print("EnhancedSelectionSystem: Camera found via fallback: %s" % camera.name)

func _process(_delta):
    # Keep looking for camera if we don't have one
    if not camera:
        _find_camera_fallback()

func _physics_process(_delta):
    if not camera or is_box_selecting:
        if hovered_unit: # Clear hover if we start box selecting
            hovered_unit = null
            unit_hovered.emit(null)
        return
    
    var unit = _get_unit_at_position(get_viewport().get_mouse_position())
    if unit != hovered_unit:
        hovered_unit = unit
        unit_hovered.emit(hovered_unit)

func _gui_input(event: InputEvent):
    """Fallback input handling using _gui_input in case _unhandled_input doesn't work"""
    print("EnhancedSelectionSystem: _gui_input fallback processing: %s" % event)
    _process_input_event(event)

func _unhandled_input(event: InputEvent):
    """Primary input handling using _unhandled_input for better event priority"""
    
    # Only process if we're visible and have camera
    if not visible:
        print("EnhancedSelectionSystem: Skipping input - not visible")
        return
        
    if not camera:
        print("EnhancedSelectionSystem: Skipping input - no camera")
        return
    
    GameConstants.debug_print("EnhancedSelectionSystem: _unhandled_input processing: %s" % event, "SELECTION")
    _process_input_event(event)

func _process_input_event(event: InputEvent):
    """Common input processing logic used by both _gui_input and _unhandled_input"""
    
    if event is InputEventMouseButton:
        GameConstants.debug_print("EnhancedSelectionSystem: Mouse button %d, pressed=%s" % [event.button_index, event.pressed], "SELECTION")
        
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                GameConstants.debug_print("EnhancedSelectionSystem: Starting box selection at %s" % event.position, "SELECTION")
                is_box_selecting = true
                box_start_position = event.position
                box_end_position = event.position
                queue_redraw()
                get_viewport().set_input_as_handled()
            else:
                if is_box_selecting:
                    GameConstants.debug_print("EnhancedSelectionSystem: Finishing selection at %s" % event.position, "SELECTION")
                    is_box_selecting = false
                    _finish_selection(event.position)
                    queue_redraw()
                    get_viewport().set_input_as_handled()
        elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
            GameConstants.debug_print("EnhancedSelectionSystem: Right-click detected at %s" % event.position, "SELECTION")
            if not camera:
                GameConstants.debug_print("EnhancedSelectionSystem: No camera available for right-click processing", "SELECTION")
            elif selected_units.is_empty():
                GameConstants.debug_print("EnhancedSelectionSystem: No units selected for right-click command", "SELECTION")
            else:
                GameConstants.debug_print("EnhancedSelectionSystem: Processing right-click with %d selected units" % selected_units.size(), "SELECTION")
                _handle_right_click(event.position)
                get_viewport().set_input_as_handled()
    
    elif event is InputEventMouseMotion and is_box_selecting:
        box_end_position = event.position
        queue_redraw()
        get_viewport().set_input_as_handled()

func _draw():
    if is_box_selecting:
        var rect = Rect2(box_start_position, box_end_position - box_start_position).abs()
        draw_rect(rect, Color(0.2, 1.0, 0.2, 0.2))
        draw_rect(rect, Color(0.2, 1.0, 0.2, 0.8), false, 2.0)

func _finish_selection(end_pos: Vector2):
    var new_selection: Array[Unit]
    var drag_distance = box_start_position.distance_to(end_pos)

    # Get client team ID from the game state
    var client_team_id = 1  # Default fallback
    var unified_main = get_node_or_null("/root/UnifiedMain")
    if unified_main and unified_main.has_method("get_client_team_id"):
        client_team_id = unified_main.get_client_team_id()

    if drag_distance < 5.0:
        # Click selection
        var unit = _get_unit_at_position(end_pos)
        if unit:
            new_selection.append(unit)
    else:
        # Box selection
        new_selection = _get_units_in_box()

    var final_selection: Array[Unit]
    for unit in new_selection:
        if unit.team_id == client_team_id:
            final_selection.append(unit)

    # Clear previous selection visual feedback
    for unit in selected_units:
        if is_instance_valid(unit) and unit.has_method("deselect"):
            unit.deselect()

    if Input.is_key_pressed(KEY_SHIFT):
        # Add to selection
        for unit in final_selection:
            if not selected_units.has(unit):
                selected_units.append(unit)
    else:
        selected_units = final_selection

    # Apply visual feedback to selected units
    for unit in selected_units:
        if is_instance_valid(unit) and unit.has_method("select"):
            unit.select()

    print("EnhancedSelectionSystem: Selected %d units" % selected_units.size())
    selection_changed.emit(selected_units)

func _get_unit_at_position(screen_pos: Vector2) -> Unit:
    GameConstants.debug_print("_get_unit_at_position called with screen_pos: %s" % screen_pos, "SELECTION")
    
    if not game_world:
        # Try one last time to get the world from the camera's viewport
        if camera:
            var viewport = camera.get_viewport()
            if viewport:
                game_world = viewport.world_3d
        if not game_world:
            GameConstants.debug_print("_get_unit_at_position: No game_world available for raycast", "SELECTION")
            return null # No 3D world, can't raycast
            
    var space_state = game_world.direct_space_state
    if not space_state:
        GameConstants.debug_print("_get_unit_at_position: No space_state available", "SELECTION")
        return null
        
    var from = camera.project_ray_origin(screen_pos)
    var to = from + camera.project_ray_normal(screen_pos) * 1000
    
    GameConstants.debug_print("_get_unit_at_position: Raycast from %s to %s" % [from, to], "SELECTION")
    
    var query = PhysicsRayQueryParameters3D.create(from, to, 3) # Layer 1 (units) + Layer 2 (buildings/turrets)
    query.collide_with_bodies = true
    query.collide_with_areas = false # We only want to hit unit bodies
    
    GameConstants.debug_print("_get_unit_at_position: Query collision_mask: %d, collide_with_bodies: %s" % [query.collision_mask, query.collide_with_bodies], "SELECTION")
    
    var result = space_state.intersect_ray(query)
    
    GameConstants.debug_print("_get_unit_at_position: Raycast result has %d keys: %s" % [result.size(), result.keys()], "SELECTION")
    
    # Additional debug: try raycast with all layers to see what we're hitting
    if result.is_empty():
        var broad_query = PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF) # All layers
        broad_query.collide_with_bodies = true
        broad_query.collide_with_areas = false
        var broad_result = space_state.intersect_ray(broad_query)
        if not broad_result.is_empty():
            GameConstants.debug_print("_get_unit_at_position: Broad raycast (all layers) hit: %s (layer: %d)" % [broad_result.collider.get_path(), broad_result.collider.collision_layer], "SELECTION")
        else:
            GameConstants.debug_print("_get_unit_at_position: Even broad raycast found nothing", "SELECTION")

    if result.has("collider"):
        var node = result.collider
        GameConstants.debug_print("_get_unit_at_position: Hit collider: %s (type: %s)" % [node.get_path(), node.get_class()], "SELECTION")
        
        # The collider might be a child CollisionShape3D. Get the parent Unit.
        var original_node = node
        while node != null and not node is Unit:
            node = node.get_parent()
            
        if node is Unit:
            GameConstants.debug_print("_get_unit_at_position: Found Unit: %s (team: %d, archetype: %s)" % [node.unit_id, node.team_id, node.archetype], "SELECTION")
            
            # Check if unit is alive (same logic as _get_units_in_box)
            var is_unit_dead = false
            if node.has_method("get") and "is_dead" in node:
                is_unit_dead = node.is_dead
            elif node.has_method("is_dead"):
                is_unit_dead = node.is_dead()
                
            if not is_unit_dead:
                GameConstants.debug_print("_get_unit_at_position: Returning alive unit: %s" % node.unit_id, "SELECTION")
                return node
            else:
                GameConstants.debug_print("_get_unit_at_position: Unit %s is dead, ignoring" % node.unit_id, "SELECTION")
        else:
            GameConstants.debug_print("_get_unit_at_position: Collider %s is not a Unit (walked up to: %s)" % [original_node.get_path(), node.get_path() if node else "null"], "SELECTION")
            return null
    else:
        GameConstants.debug_print("_get_unit_at_position: No collision detected", "SELECTION")
        return null
            
    return null

func _get_units_in_box() -> Array[Unit]:
    var units_in_box: Array[Unit] = []
    var selection_rect = Rect2(box_start_position, box_end_position - box_start_position).abs()
    
    var units_to_check: Array = []

    if multiplayer.is_server():
        # On host/server, get units from the authoritative game state.
        # This is because ClientDisplayManager doesn't populate `displayed_units` for the host.
        var game_state = get_node_or_null("/root/DependencyContainer/GameState")
        if game_state:
            units_to_check = game_state.units.values()
    else:
        # On a pure client, get units from the display manager.
        var display_manager = get_node_or_null("/root/UnifiedMain/ClientDisplayManager")
        if display_manager:
            units_to_check = display_manager.displayed_units.values()
            
    if units_to_check.is_empty():
        return []
    
    for unit in units_to_check:
        if is_instance_valid(unit):
            # Check if unit has is_dead property, otherwise assume it's alive
            var is_unit_dead = false
            if unit.has_method("get") and "is_dead" in unit:
                is_unit_dead = unit.is_dead
            elif unit.has_method("is_dead"):
                is_unit_dead = unit.is_dead()
            
            if not is_unit_dead:
                var screen_pos = camera.unproject_position(unit.global_position)
                if selection_rect.has_point(screen_pos):
                    units_in_box.append(unit)
            else:
                continue
        else:
            continue
                
    return units_in_box

func _handle_right_click(screen_pos: Vector2):
    if selected_units.is_empty(): 
        GameConstants.debug_print("EnhancedSelectionSystem: Right-click ignored - no units selected", "SELECTION")
        return

    var unit_ids = []
    for unit in selected_units:
        unit_ids.append(unit.unit_id)
    
    # Debug: Show available units in scene for reference
    var all_units = get_tree().get_nodes_in_group("units")
    GameConstants.debug_print("_handle_right_click: Available units in scene: %d" % all_units.size(), "SELECTION")
    for unit in all_units:
        if unit is Unit:
            GameConstants.debug_print("  - Unit %s (team: %d, pos: %s, collision_layer: %d)" % [unit.unit_id, unit.team_id, unit.global_position, unit.collision_layer], "SELECTION")

    var target_unit = _get_unit_at_position(screen_pos)
    var command_data = {}
    
    if target_unit:
        GameConstants.debug_print("_handle_right_click: Detected unit %s (team: %d) at click position" % [target_unit.unit_id, target_unit.team_id], "SELECTION")
        GameConstants.debug_print("_handle_right_click: Selected units team: %d" % selected_units[0].team_id, "SELECTION")
    else:
        GameConstants.debug_print("_handle_right_click: No unit detected at click position, defaulting to move command", "SELECTION")
    
    if target_unit and target_unit.team_id != selected_units[0].team_id:
        # Attack command
        command_data = {
            "action": "attack",
            "target_id": target_unit.unit_id,
            "units": unit_ids
        }
        GameConstants.debug_print("EnhancedSelectionSystem: Generated attack command for %d units to target %s (%s)" % [unit_ids.size(), target_unit.unit_id, target_unit.archetype], "SELECTION")
    else:
        # Move command
        var world_pos = _screen_to_world_ground_pos(screen_pos)
        if world_pos != null:
            command_data = {
                "action": "move_to",
                "position": world_pos,
                "units": unit_ids
            }
            GameConstants.debug_print("EnhancedSelectionSystem: Generated move command for %d units to position %s" % [unit_ids.size(), world_pos], "SELECTION")
        else:
            GameConstants.debug_print("EnhancedSelectionSystem: Failed to calculate world position from screen pos: %s" % screen_pos, "SELECTION")

    if not command_data.is_empty():
        GameConstants.debug_print("EnhancedSelectionSystem: Sending DIRECT command for %d units: %s" % [unit_ids.size(), command_data.action], "SELECTION")
        
        # Find the correct scene root that has the submit_direct_command_rpc method
        var scene_root = get_tree().current_scene
        if scene_root and scene_root.has_method("submit_direct_command_rpc"):
            scene_root.rpc("submit_direct_command_rpc", command_data)
        else:
            # Fallback: try common scene root names
            var possible_roots = [
                get_node_or_null("/root/UnifiedMain"),
                get_node_or_null("/root/Main"),
                get_node_or_null("/root/TestMap"),
                get_node_or_null("/root/CombatTestSuite")
            ]
            
            var command_sent = false
            for root in possible_roots:
                if root and root.has_method("submit_direct_command_rpc"):
                    GameConstants.debug_print("EnhancedSelectionSystem: Found command handler at: %s" % root.get_path(), "SELECTION")
                    root.rpc("submit_direct_command_rpc", command_data)
                    command_sent = true
                    break
            
            if not command_sent:
                GameConstants.debug_print("EnhancedSelectionSystem: ERROR - Could not find submit_direct_command_rpc method in scene", "SELECTION")
    else:
        GameConstants.debug_print("EnhancedSelectionSystem: No command generated for right-click at %s" % screen_pos, "SELECTION")

func _screen_to_world_ground_pos(screen_pos: Vector2) -> Variant:
    var from = camera.project_ray_origin(screen_pos)
    var to = from + camera.project_ray_normal(screen_pos) * 1000
    
    # Intersect with the ground plane (y=0)
    var plane = Plane(Vector3.UP, 0)
    var global_intersection = plane.intersects_ray(from, to)
    
    if global_intersection == null:
        print("DEBUG: Screen raycast failed to intersect ground plane")
        return null
        
    return global_intersection

func _find_city_map_node() -> Node3D:
    """Find the CityMap node to get its transform"""
    # Look for CityMap node in the scene tree
    var scene_root = get_tree().current_scene
    if scene_root.name == "CityMap":
        return scene_root
    
    # Look for CityMap as a child node
    var city_map = scene_root.find_child("CityMap", true, false)
    if city_map:
        return city_map
    
    # Fallback: look in common locations
    var test_map_candidates = [
        get_node_or_null("/root/Main/CityMap"),
        get_node_or_null("/root/UnifiedMain/CityMap"),
        get_node_or_null("/root/TestMap/CityMap")
    ]
    
    for candidate in test_map_candidates:
        if candidate:
            return candidate
    
    return null

func get_selected_units() -> Array[Unit]:
    # Prune dead units from selection
    var live_units: Array[Unit] = []
    for unit in selected_units:
        if is_instance_valid(unit) and not unit.is_dead:
            live_units.append(unit)
    selected_units = live_units
    return selected_units