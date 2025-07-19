# UnifiedMain.gd - Refactored main script using manager classes
extends Node

# Scene paths
const LOBBY_SCENE = "res://scenes/ui/lobby.tscn"
const GAME_HUD_SCENE = "res://scenes/ui/game_hud.tscn"
const TEST_MAP_SCENE = "res://scenes/maps/test_map.tscn"

# Node references
var dependency_container
var logger
var lobby_instance: Control
var hud_instance: Control
var map_instance: Node
var client_display_manager: Node
var combat_test_suite: Node
var client_team_id: int = -1

func _ready() -> void:
    print("UnifiedMain starting...")
    
    # Wait for autoloads to be available
    await get_tree().process_frame
    
    # Initialize dependencies using autoload
    dependency_container = get_node("/root/DependencyContainer")
    if not dependency_container:
        push_error("DependencyContainer not found!")
        return
        
    logger = dependency_container.get_logger()
    
    logger.info("UnifiedMain", "Starting unified application")
    
    # Determine if we're running headless (server mode)
    if OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless":
        logger.info("UnifiedMain", "Detected server mode - starting server")
        _start_server_mode()
    else:
        logger.info("UnifiedMain", "Detected client mode - starting client")
        _start_client_mode()
    
    logger.info("UnifiedMain", "UnifiedMain initialization complete")

func _start_server_mode() -> void:
    logger.info("UnifiedMain", "Starting server mode")
    dependency_container.create_server_dependencies()
    # The SessionManager now handles loading the map on the server when a match starts.
    # We no longer connect the match_started signal here to avoid double-loading the map.


func _start_client_mode() -> void:
    logger.info("UnifiedMain", "Starting client mode")
    dependency_container.create_client_dependencies()
    
    # Create the client-side display manager
    var ClientDisplayManagerClass = load("res://scripts/client/client_display_manager.gd")
    client_display_manager = ClientDisplayManagerClass.new()
    client_display_manager.name = "ClientDisplayManager"
    add_child(client_display_manager)
    
    # Show the lobby scene
    var lobby_scene = load(LOBBY_SCENE)
    lobby_instance = lobby_scene.instantiate()
    add_child(lobby_instance)
    
    # Connect to the lobby's start signal
    lobby_instance.start_match_requested.connect(_on_match_start_requested)

@rpc("any_peer", "call_local", "reliable")
func handle_join_session_rpc(preferred_session_id: String = ""):
    var peer_id = multiplayer.get_remote_sender_id()
    if dependency_container.is_server_mode():
        var session_manager = dependency_container.get_node_or_null("SessionManager")
        if session_manager:
            session_manager.handle_join_session(peer_id, preferred_session_id)

@rpc("any_peer", "call_local")
func handle_player_ready_rpc(is_ready: bool):
    var peer_id = multiplayer.get_remote_sender_id()
    if dependency_container.is_server_mode():
        var session_manager = dependency_container.get_node_or_null("SessionManager")
        if session_manager:
            session_manager.handle_player_ready(peer_id, is_ready)

@rpc("any_peer", "call_local")
func handle_start_game_rpc():
    var peer_id = multiplayer.get_remote_sender_id()
    if dependency_container.is_server_mode():
        var session_manager = dependency_container.get_node_or_null("SessionManager")
        if session_manager:
            session_manager.call_deferred("handle_force_start_game", peer_id)

@rpc("any_peer", "call_local")
func submit_command_rpc(command_text: String, unit_ids: Array):
    if not dependency_container.is_server_mode():
        return
    
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("UnifiedMain", "Received command '%s' for units %s from peer %d" % [command_text, unit_ids, peer_id])
    
    var ai_processor = dependency_container.get_ai_command_processor()
    if ai_processor:
        ai_processor.process_command(command_text, unit_ids, peer_id)

@rpc("any_peer", "call_local")
func submit_direct_command_rpc(command_text: String, unit_ids: Array):
    if not dependency_container.is_server_mode():
        return
    
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("UnifiedMain", "Received DIRECT command '%s' for units %s from peer %d" % [command_text, unit_ids, peer_id])
    
    # Execute command directly without AI processing
    _execute_direct_command(command_text, unit_ids)

func _execute_direct_command(command_text: String, unit_ids: Array):
    """Execute a direct command immediately without AI processing"""
    var game_state = dependency_container.get_game_state()
    if not game_state:
        logger.error("UnifiedMain", "GameState not found for direct command execution")
        return
    
    # Parse the command to extract action and parameters
    var action_data = _parse_direct_command(command_text)
    if action_data.is_empty():
        logger.warning("UnifiedMain", "Could not parse direct command: %s" % command_text)
        return
    
    # Execute the action on each unit
    for unit_id in unit_ids:
        if game_state.units.has(unit_id):
            var unit = game_state.units[unit_id]
            if is_instance_valid(unit):
                # Interrupt any existing plan first
                var plan_executor = dependency_container.get_node_or_null("PlanExecutor")
                if plan_executor:
                    plan_executor.interrupt_plan(unit_id, "Direct command override", false)
                
                # Use coordinates directly from selection system (now scene-local coordinates)
                # No team-relative conversion needed since selection system provides proper coordinates
                if action_data.action == "move_to" and action_data.params.has("position"):
                    var local_pos = Vector3(action_data.params.position[0], action_data.params.position[1], action_data.params.position[2])
                    logger.info("UnifiedMain", "Unit %s: Using scene-local coordinates [%s, %s, %s] directly" % [unit_id, local_pos.x, local_pos.y, local_pos.z])
                
                # Execute the direct action
                unit.set_current_action(action_data)
                logger.info("UnifiedMain", "Executed direct command on unit %s: %s with params: %s" % [unit_id, action_data.action, str(action_data.params)])

func _parse_direct_command(command_text: String) -> Dictionary:
    """Parse direct command text into action data"""
    var action_data = {}
    
    # Handle move commands: "Move to position (x, y, z)"
    var move_regex = RegEx.new()
    move_regex.compile(r"Move to position \(([^,]+), ([^,]+), ([^)]+)\)")
    var move_result = move_regex.search(command_text)
    if move_result:
        var x = float(move_result.get_string(1))
        var y = float(move_result.get_string(2))
        var z = float(move_result.get_string(3))
        action_data = {
            "action": "move_to",
            "params": {
                "position": [x, y, z],
                "target_id": null
            }
        }
        return action_data
    
    # Handle attack commands: "Attack target [unit_id]"
    var attack_regex = RegEx.new()
    attack_regex.compile(r"Attack target (.+)")
    var attack_result = attack_regex.search(command_text)
    if attack_result:
        var target_id = attack_result.get_string(1)
        action_data = {
            "action": "attack",
            "params": {
                "position": null,
                "target_id": target_id
            }
        }
        return action_data
    
    return {}

func _world_to_team_relative_coords(world_pos: Vector3, team_id: int) -> Vector3:
    """Convert world coordinates to team-relative coordinates"""
    # Get the team transform (same logic as Unit._get_team_transform())
    var home_base_manager = get_tree().get_first_node_in_group("home_base_managers")
    if not home_base_manager:
        logger.error("UnifiedMain", "HomeBaseManager not found for coordinate conversion!")
        return world_pos
    
    var my_base_pos = home_base_manager.get_home_base_position(team_id)
    var enemy_team_id = 2 if team_id == 1 else 1
    var enemy_base_pos = home_base_manager.get_home_base_position(enemy_team_id)
    
    if my_base_pos == Vector3.ZERO or enemy_base_pos == Vector3.ZERO:
        logger.error("UnifiedMain", "Home base positions not set up correctly for coordinate conversion.")
        return world_pos
    
    # Create the same team transform as the unit does
    var forward_vec = (enemy_base_pos - my_base_pos).normalized()
    var right_vec = forward_vec.cross(Vector3.UP).normalized()
    var up_vec = right_vec.cross(forward_vec).normalized()
    var team_transform = Transform3D(right_vec, up_vec, forward_vec, my_base_pos)
    
    # Apply inverse transform to convert world coordinates to team-relative coordinates
    var team_relative_pos = team_transform.inverse() * world_pos
    
    return team_relative_pos

@rpc("any_peer", "call_local")
func submit_test_command_rpc(command_text: String):
    if not dependency_container.is_server_mode():
        return
    
    if not is_instance_valid(combat_test_suite):
        var CombatTestSuiteScene = load("res://scenes/testing/CombatTestSuite.tscn")
        combat_test_suite = CombatTestSuiteScene.instantiate()
        add_child(combat_test_suite)
        combat_test_suite.setup(dependency_container)

    combat_test_suite.execute_command(command_text)

func _on_match_start_requested() -> void:
    logger.info("UnifiedMain", "Match start requested.")

    # Hide lobby UI if it exists
    if is_instance_valid(lobby_instance):
        lobby_instance.queue_free()
        lobby_instance = null

    # Instance and add the game map, but only if it doesn't exist yet.
    # This prevents the listen-server from loading it twice.
    map_instance = get_tree().get_root().find_child("TestMap", true, false)
    if not is_instance_valid(map_instance):
        var map_scene = load(TEST_MAP_SCENE)
        map_instance = map_scene.instantiate()
        add_child(map_instance)

    # Pass map reference to client display manager so it can find the 'Units' node
    if client_display_manager:
        client_display_manager.setup_map_references(map_instance)

    # Instance and add the game HUD, but only if it doesn't exist
    if not get_tree().get_root().find_child("GameHUD", false):
        var hud_scene = load(GAME_HUD_SCENE)
        hud_instance = hud_scene.instantiate()
        add_child(hud_instance)

    # Server-side initialization is now fully handled by the SessionManager
    # when it receives the match_started signal. This avoids duplicate logic.

# =============================================================================
# RPC Methods - Called by server to communicate with clients
# =============================================================================

@rpc("any_peer", "call_local", "reliable")
func _on_server_welcome(data: Dictionary) -> void:
    """Handle server welcome message"""
    logger.info("UnifiedMain", "Received server welcome: %s" % data)
    # TODO: Delegate to appropriate UI system once UI architecture is clarified

@rpc("any_peer", "call_local", "reliable") 
func _on_session_join_response(data: Dictionary) -> void:
    """Handle session join response from server"""
    logger.info("UnifiedMain", "Received session join response: %s" % data)
    if is_instance_valid(lobby_instance) and data.get("success", false):
        lobby_instance.update_lobby_display(data.get("session_data", {}))

@rpc("any_peer", "call_local", "reliable")
func _on_lobby_update(lobby_data: Dictionary) -> void:
    """Handle lobby update from server"""
    logger.info("UnifiedMain", "Received lobby update: %s" % lobby_data)
    if is_instance_valid(lobby_instance):
        lobby_instance.update_lobby_display(lobby_data)

@rpc("any_peer", "call_local", "reliable")
func _on_game_started(data: Dictionary) -> void:
    """Handle the game started signal from the server."""
    logger.info("UnifiedMain", "Game start signal received from server.")
    client_team_id = data.get("player_team", -1)
    _on_match_start_requested()

@rpc("any_peer", "call_local") # Use unreliable for high-frequency state updates
func _on_game_state_update(state: Dictionary) -> void:
    if client_display_manager:
        client_display_manager.update_state(state)
    
    # Update HUD unit status panel with units data
    if hud_instance and is_instance_valid(hud_instance) and state.has("units"):
        hud_instance.update_player_units(state.units, multiplayer.get_unique_id())

@rpc("any_peer", "call_local", "reliable")
func _on_ai_command_feedback_rpc(summary_message: String, status_message: String):
    """
    Called by the server to send AI command feedback (summary and status)
    to all clients.
    """
    if hud_instance and is_instance_valid(hud_instance):
        hud_instance.update_ai_command_feedback(summary_message, status_message)
    else:
        logger.warning("UnifiedMain", "GameHUD not found for AI command feedback RPC.")

@rpc("any_peer", "call_local")
func display_speech_bubble_rpc(unit_id: String, speech_text: String):
    if not dependency_container.is_client_mode(): return

    var speech_manager = dependency_container.get_speech_bubble_manager()
    if speech_manager:
        # Find the client-side unit to get its team_id for coloring the bubble
        if client_display_manager and client_display_manager.displayed_units.has(unit_id):
            var client_unit = client_display_manager.displayed_units[unit_id]
            speech_manager.show_speech_bubble(unit_id, speech_text, client_unit.team_id)
        else:
            # Fallback if unit not found on client yet
            speech_manager.show_speech_bubble(unit_id, speech_text, 0)

@rpc("any_peer", "unreliable")
func spawn_impact_effect_rpc(position: Vector3):
    # This runs on clients to show a visual-only effect
    if multiplayer.is_server(): return

    var impact_effect_scene = preload("res://scenes/fx/ImpactEffect.tscn")
    if impact_effect_scene:
        var effect = impact_effect_scene.instantiate()
        get_tree().root.add_child(effect)
        effect.global_position = position
        effect.emitting = true
        logger.info("UnifiedMain", "Spawned impact effect at %s" % str(position))

@rpc("any_peer", "unreliable")
func spawn_visual_projectile_rpc(start_pos: Vector3, p_direction: Vector3, p_team_id: int, p_speed: float, p_lifetime: float):
    # This runs on clients
    if multiplayer.is_server(): return

    var projectile_scene = preload("res://scenes/fx/Projectile.tscn")
    if projectile_scene:
        var projectile = projectile_scene.instantiate()
        get_tree().root.add_child(projectile)
        projectile.global_position = start_pos
        projectile.direction = p_direction
        projectile.shooter_team_id = p_team_id
        projectile.speed = p_speed
        projectile.lifetime = p_lifetime
        projectile.damage = 0 # Visual only

@rpc("any_peer", "unreliable")
func display_damage_indicator_rpc(unit_id: String, damage_amount: float):
    if multiplayer.is_server(): return

    if client_display_manager and client_display_manager.displayed_units.has(unit_id):
        var unit_instance = client_display_manager.displayed_units[unit_id]
        if is_instance_valid(unit_instance) and unit_instance.has_method("show_damage_indicator"):
            unit_instance.show_damage_indicator(damage_amount)

# =============================================================================

func get_client_team_id() -> int:
    return client_team_id

func _exit_tree() -> void:
    if dependency_container:
        dependency_container.cleanup()