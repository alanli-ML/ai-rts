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
    # Server doesn't need to load scenes, it will just manage state.
    # We can connect to a signal from SessionManager to know when a match starts.
    var session_manager = dependency_container.get_node("SessionManager")
    session_manager.match_started.connect(_on_match_start_requested)


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

@rpc("any_peer")
func submit_command_rpc(command_text: String, unit_ids: Array[String]):
    if not dependency_container.is_server_mode():
        return
    
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("UnifiedMain", "Received command '%s' for units %s from peer %d" % [command_text, unit_ids, peer_id])
    
    var ai_processor = dependency_container.get_ai_command_processor()
    if ai_processor:
        var game_state = dependency_container.get_game_state()
        var state_dict = {}
        if game_state and game_state.has_method("get_context_for_ai"):
            state_dict = game_state.get_context_for_ai()
        ai_processor.process_command(command_text, unit_ids, state_dict)

func _on_match_start_requested() -> void:
    logger.info("UnifiedMain", "Match start requested.")
    
    # Hide lobby UI if it exists
    if is_instance_valid(lobby_instance):
        lobby_instance.queue_free()
        lobby_instance = null

    # Instance and add the game map
    var map_scene = load(TEST_MAP_SCENE)
    map_instance = map_scene.instantiate()
    add_child(map_instance)

    # Pass map reference to client display manager so it can find the 'Units' node
    if client_display_manager:
        client_display_manager.setup_map_references(map_instance)
    
    # Instance and add the game HUD
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

@rpc("any_peer")
func remove_unit_rpc(unit_id: String):
    if client_display_manager:
        client_display_manager.remove_unit(unit_id)

@rpc("any_peer")
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

@rpc("any_peer", "reliable")
func spawn_explosion_effect_rpc(position: Vector3):
    # This runs on clients to show a visual-only effect
    if dependency_container.is_server_mode(): return

    var impact_effect_scene = preload("res://scenes/fx/ImpactEffect.tscn")
    if impact_effect_scene:
        var effect = impact_effect_scene.instantiate()
        # Add to a container for effects, or root for now
        get_tree().root.add_child(effect)
        effect.global_position = position
        effect.emitting = true
        logger.info("UnifiedMain", "Spawned explosion effect at %s" % str(position))
    
# =============================================================================

func get_client_team_id() -> int:
    return client_team_id

func _exit_tree() -> void:
    if dependency_container:
        dependency_container.cleanup()