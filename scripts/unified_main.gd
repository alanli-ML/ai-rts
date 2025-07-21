# UnifiedMain.gd - Refactored main script using manager classes
extends Node

const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# Scene paths
const LOBBY_SCENE = "res://scenes/ui/lobby.tscn"
const GAME_HUD_SCENE = "res://scenes/ui/game_hud.tscn"
const VICTORY_SCREEN_SCENE = "res://scenes/ui/victory_screen.tscn"
const START_MESSAGE_SCENE = "res://scenes/ui/start_message.tscn"
const TEST_MAP_SCENE = "res://scenes/maps/test_map.tscn"

# Node references
var dependency_container
var logger
var lobby_instance: Control
var hud_instance: Control
var victory_screen_instance: Control
var start_message_instance: Control
var map_instance: Node
var client_display_manager: Node
var combat_test_suite: Node
var client_team_id: int = -1
var fog_of_war_manager: Node

# Cache for static unit plan data received via reliable RPC. This persists
# even if a unit's visual representation is temporarily destroyed.
var unit_plan_cache: Dictionary = {}

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
    
    # Create victory screen instance
    var victory_scene = load(VICTORY_SCREEN_SCENE)
    victory_screen_instance = victory_scene.instantiate()
    victory_screen_instance.name = "VictoryScreen"
    add_child(victory_screen_instance)
    
    # Connect victory screen signals
    victory_screen_instance.play_again_requested.connect(_on_play_again_requested)
    victory_screen_instance.main_menu_requested.connect(_on_main_menu_requested)
    
    # Create start message instance
    var start_message_scene = load(START_MESSAGE_SCENE)
    start_message_instance = start_message_scene.instantiate()
    start_message_instance.name = "StartMessage"
    add_child(start_message_instance)
    
    # Connect start message signals
    start_message_instance.start_message_dismissed.connect(_on_start_message_dismissed)
    
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
func submit_direct_command_rpc(command_data: Dictionary):
    if not dependency_container.is_server_mode():
        return

    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("UnifiedMain", "Received DIRECT command data for units %s from peer %d" % [command_data.get("units", []), peer_id])

    # Execute command directly without AI processing
    _execute_direct_command(command_data)

func _execute_direct_command(command_data: Dictionary):
    """Execute a direct command immediately without AI processing"""
    var game_state = dependency_container.get_game_state()
    if not game_state:
        logger.error("UnifiedMain", "GameState not found for direct command execution")
        return

    var action = command_data.get("action", "")
    var unit_ids = command_data.get("units", [])
    var params = {}

    if action == "move_to":
        var pos = command_data.get("position", Vector3.ZERO)
        params = {"position": [pos.x, pos.y, pos.z]}
    elif action == "attack":
        params = {"target_id": command_data.get("target_id", "")}
    
    var action_data = {"action": action, "params": params}
    
    if action_data.is_empty() or action.is_empty():
        logger.warning("UnifiedMain", "Could not parse direct command from data: %s" % str(command_data))
        return

    # Execute the action on each unit
    for unit_id in unit_ids:
        if game_state.units.has(unit_id):
            var unit = game_state.units[unit_id]
            if is_instance_valid(unit) and unit.has_method("execute_player_override"):
                # The unit's execute_player_override will handle interrupting its own AI plan.
                unit.execute_player_override(action_data)
                logger.info("UnifiedMain", "Executed direct command on unit %s: %s with params: %s" % [unit_id, action_data.action, str(action_data.params)])

# Removed _world_to_team_relative_coords() function as team relative transformations are no longer needed

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

    # Instance and add Fog of War for clients
    if not multiplayer.is_server() or DisplayServer.get_name() != "headless":
        # Check if fog manager already exists to avoid duplicates
        var existing_fog = get_tree().get_root().find_child("FogOfWarManager", true, false)
        if not existing_fog:
            var fog_scene = load("res://scenes/fx/FogOfWar.tscn")
            fog_of_war_manager = fog_scene.instantiate()
            fog_of_war_manager.name = "FogOfWarManager"
            
            # Add to group for easy discovery
            fog_of_war_manager.add_to_group("fog_managers")
            
            add_child(fog_of_war_manager)
            
            # Wait a frame to ensure it's properly initialized
            await get_tree().process_frame
            
            logger.info("UnifiedMain", "Fog of War manager instantiated for client at path: %s" % fog_of_war_manager.get_path())
        else:
            fog_of_war_manager = existing_fog
            logger.info("UnifiedMain", "Found existing Fog of War manager: %s" % existing_fog.get_path())
    

    # CRITICAL: Position camera based on player's team after map is loaded
    # Wait a frame to ensure all map components are fully initialized
    await get_tree().process_frame
    _position_camera_for_team(client_team_id)

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
    
    # Show start message after a short delay to let the game load
    if start_message_instance:
        await get_tree().create_timer(1.0).timeout
        start_message_instance.show_start_message()

func _position_camera_for_team(team_id: int) -> void:
    """Position the camera to focus on the team's home base for optimal tactical view"""
    if team_id <= 0:
        logger.warning("UnifiedMain", "Invalid team ID %d for camera positioning, using default view" % team_id)
        return
    
    logger.info("UnifiedMain", "Positioning camera for team %d" % team_id)
    
    # Find the RTS camera in the map
    var rts_camera: RTSCamera = null
    if map_instance:
        rts_camera = map_instance.get_node_or_null("RTSCamera")
    
    # If not found in map, search globally
    if not rts_camera:
        var rts_cameras = get_tree().get_nodes_in_group("rts_cameras")
        if rts_cameras.size() > 0:
            rts_camera = rts_cameras[0]
    
    if rts_camera:
        # Use the team-based camera positioning
        rts_camera.position_for_team_base(team_id, true)
        logger.info("UnifiedMain", "Successfully positioned camera for team %d" % team_id)
    else:
        logger.warning("UnifiedMain", "Could not find RTS camera for team-based positioning")

@rpc("any_peer", "call_local") # Use unreliable for high-frequency state updates
func _on_game_state_update(state: Dictionary) -> void:
    if client_display_manager:
        client_display_manager.update_state(state)
    
    # Update HUD unit status panel with units data
    if hud_instance and is_instance_valid(hud_instance) and state.has("units"):
        # Use the client's team ID directly instead of relying on peer ID lookup
        hud_instance.update_player_units(state.units, multiplayer.get_unique_id())
        # Also manually update team ID if the lookup is failing
        if client_team_id != -1:
            hud_instance.set("player_team_id_override", client_team_id)

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

@rpc("any_peer", "call_local", "reliable")
func update_unit_behavior_plan_rpc(unit_id: String, behavior_matrix: Dictionary, attack_sequence: Array, strategic_goal: String):
    """
    Called by the server to update a unit's behavior plan, strategic goal, and attack sequence on clients.
    This is the reliable RPC mechanism that updates client-side unit instances.
    """
    if multiplayer.is_server():
        return  # Server doesn't need to process its own RPC
    
    logger.info("UnifiedMain", "Received behavior plan update for unit %s: goal='%s', sequence=%s" % [unit_id, strategic_goal, str(attack_sequence)])
    
    # Store in the unit plan cache for persistence
    unit_plan_cache[unit_id] = {
        "behavior_matrix": behavior_matrix.duplicate(),
        "control_point_attack_sequence": attack_sequence.duplicate(),
        "strategic_goal": strategic_goal
    }
    
    # Also try to update the HUD directly if it exists
    if hud_instance and is_instance_valid(hud_instance):
        var unit_data_for_hud = {
            "id": unit_id,
            "strategic_goal": strategic_goal,
            "control_point_attack_sequence": attack_sequence,
            "team_id": client_team_id  # Use the correct client team ID
        }
        hud_instance.update_unit_data(unit_id, unit_data_for_hud)
    
    # Update the client-side unit instance if it exists
    if client_display_manager and client_display_manager.displayed_units.has(unit_id):
        var unit_instance = client_display_manager.displayed_units[unit_id]
        if is_instance_valid(unit_instance):
            # Update the unit's properties directly (safer than using set() method)
            unit_instance.behavior_matrix = behavior_matrix.duplicate()
            unit_instance.control_point_attack_sequence = attack_sequence.duplicate()
            unit_instance.strategic_goal = strategic_goal
            
            # Also mark that this unit has received first command for UI purposes
            if "has_received_first_command" in unit_instance:
                unit_instance.has_received_first_command = true
            
            # Refresh the status bar to show new goals immediately
            if unit_instance.has_method("refresh_status_bar"):
                unit_instance.refresh_status_bar()
            
            # Also force refresh the status bar directly 
            _force_refresh_unit_status_bar(unit_instance, unit_id)
        else:
            logger.warning("UnifiedMain", "Unit instance %s found but not valid for behavior plan update" % unit_id)
    else:
        logger.info("UnifiedMain", "Unit %s not yet displayed on client, cached plan data for when it spawns" % unit_id)

func _force_refresh_unit_status_bar(unit_instance: Node, unit_id: String) -> void:
    """Force refresh a unit's status bar as a fallback mechanism"""
    if not is_instance_valid(unit_instance):
        return
    
    var status_bar = unit_instance.get("status_bar")
    if status_bar and status_bar.has_method("force_refresh"):
        status_bar.force_refresh()

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
        GameConstants.debug_print("UnifiedMain: Spawned impact effect at %s" % str(position), "FX")

@rpc("any_peer", "unreliable")
func spawn_healing_effect_rpc(position: Vector3):
    # This runs on clients to show a visual-only healing effect
    if multiplayer.is_server(): return

    var healing_effect_scene = preload("res://scenes/fx/HealingEffect.tscn")
    if healing_effect_scene:
        var effect = healing_effect_scene.instantiate()
        get_tree().root.add_child(effect)
        effect.global_position = position
        effect.emitting = true
        logger.info("UnifiedMain", "Spawned healing effect at %s" % str(position))
        
        # Auto-remove effect after duration
        await get_tree().create_timer(3.0).timeout
        if is_instance_valid(effect):
            effect.emitting = false
            await get_tree().create_timer(2.0).timeout
            if is_instance_valid(effect):
                effect.queue_free()

@rpc("any_peer", "unreliable")
func spawn_visual_projectile_rpc(start_pos: Vector3, p_direction: Vector3, p_team_id: int, p_speed: float, p_lifetime: float):
    # This runs on clients
    if multiplayer.is_server(): return

    var projectile_scene = preload("res://scenes/fx/Projectile.tscn")
    if projectile_scene:
        var projectile = projectile_scene.instantiate()
        
        # Set properties BEFORE adding to scene tree so _ready() has correct values
        projectile.global_position = start_pos
        projectile.direction = p_direction
        projectile.shooter_team_id = p_team_id
        projectile.speed = p_speed
        projectile.lifetime = p_lifetime
        projectile.damage = 0 # Visual only
        
        # Add to scene tree after setting properties
        get_tree().root.add_child(projectile)

@rpc("any_peer", "unreliable")
func display_damage_indicator_rpc(unit_id: String, damage_amount: float):
    if multiplayer.is_server(): return

    if client_display_manager and client_display_manager.displayed_units.has(unit_id):
        var unit_instance = client_display_manager.displayed_units[unit_id]
        if is_instance_valid(unit_instance) and unit_instance.has_method("show_damage_indicator"):
            unit_instance.show_damage_indicator(damage_amount)

@rpc("any_peer", "call_local", "reliable")
func _on_match_ended_rpc(winning_team: int, match_data: Dictionary) -> void:
    """Handle match ended signal from server - show victory screen"""
    logger.info("UnifiedMain", "Match ended: Team %d wins" % winning_team)
    
    if victory_screen_instance:
        # Show victory screen with client team context
        victory_screen_instance.show_victory_screen(winning_team, client_team_id, match_data)
    else:
        logger.warning("UnifiedMain", "Victory screen not available to display match end")

func _on_play_again_requested() -> void:
    """Handle play again request from victory screen"""
    logger.info("UnifiedMain", "Play again requested")
    
    # Hide victory screen
    if victory_screen_instance:
        victory_screen_instance.hide_victory_screen()
    
    # TODO: Implement restart match logic
    # For now, just return to lobby
    _return_to_lobby()

func _on_main_menu_requested() -> void:
    """Handle main menu request from victory screen"""
    logger.info("UnifiedMain", "Main menu requested")
    
    # Hide victory screen
    if victory_screen_instance:
        victory_screen_instance.hide_victory_screen()
    
    # Return to lobby/main menu
    _return_to_lobby()

func _return_to_lobby() -> void:
    """Return to lobby screen and clean up game state"""
    # Hide and cleanup game elements
    if hud_instance and is_instance_valid(hud_instance):
        hud_instance.queue_free()
        hud_instance = null
    
    if map_instance and is_instance_valid(map_instance):
        map_instance.queue_free()
        map_instance = null
    
    # Reset start message for potential new game
    if start_message_instance:
        start_message_instance.reset_for_new_game()
    
    # Reset client team
    client_team_id = -1
    
    # Show lobby again if not already visible
    if not lobby_instance or not is_instance_valid(lobby_instance):
        var lobby_scene = load(LOBBY_SCENE)
        lobby_instance = lobby_scene.instantiate()
        add_child(lobby_instance)
        lobby_instance.start_match_requested.connect(_on_match_start_requested)
    else:
        lobby_instance.visible = true

# =============================================================================

func get_client_team_id() -> int:
    return client_team_id

func _exit_tree() -> void:
    if dependency_container:
        dependency_container.cleanup()

func _on_start_message_dismissed() -> void:
    """Handle start message being dismissed"""
    logger.info("UnifiedMain", "Start message was dismissed")