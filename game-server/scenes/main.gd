extends Node

func _ready() -> void:
    print("=== AI-RTS Dedicated Server Starting ===")
    print("Godot version: %s" % Engine.get_version_info())
    print("Server starting at: %s" % Time.get_datetime_string_from_system())
    
    # Wait a moment for autoloads to initialize
    await get_tree().create_timer(0.1).timeout
    
    # Print initial status
    print("Server initialization complete")
    print("Port: %d" % DedicatedServer.DEFAULT_PORT)
    print("Max clients: %d" % DedicatedServer.MAX_CLIENTS)
    print("Ready to accept connections!")
    print("=====================================")

func _on_stats_timer_timeout() -> void:
    # Print server statistics every 10 seconds
    var stats = DedicatedServer.get_server_stats()
    var session_stats = SessionManager.get_session_stats()
    
    print("=== Server Statistics ===")
    print("Connected clients: %d" % stats.connected_clients)
    print("Active sessions: %d" % session_stats.active_sessions)
    print("Waiting sessions: %d" % session_stats.waiting_sessions)
    print("Total players: %d" % session_stats.total_players)
    print("Server uptime: %d seconds" % (stats.uptime / 1000))
    print("========================")

func _input(event: InputEvent) -> void:
    # Handle server commands via keyboard input
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_Q:
                print("Shutting down server...")
                DedicatedServer.stop_server()
                get_tree().quit()
            KEY_S:
                # Print detailed statistics
                _print_detailed_stats()
            KEY_H:
                # Print help
                _print_help()

func _print_detailed_stats() -> void:
    print("=== Detailed Server Statistics ===")
    
    # Server stats
    var stats = DedicatedServer.get_server_stats()
    print("Server running: %s" % stats.running)
    print("Connected clients: %d" % stats.connected_clients)
    print("Server uptime: %d seconds" % (stats.uptime / 1000))
    
    # Session stats
    var session_stats = SessionManager.get_session_stats()
    print("Total sessions: %d" % session_stats.total_sessions)
    print("Active sessions: %d" % session_stats.active_sessions)
    print("Waiting sessions: %d" % session_stats.waiting_sessions)
    print("Total players: %d" % session_stats.total_players)
    
    # AI stats
    print("AI service URL: %s" % AIIntegration.ai_service_url)
    print("Pending AI requests: %d" % AIIntegration.pending_requests.size())
    
    # Client details
    print("Connected clients details:")
    for peer_id in DedicatedServer.connected_clients:
        var client = DedicatedServer.connected_clients[peer_id]
        print("  Peer %d: %s (session: %s, auth: %s)" % [
            peer_id,
            client.player_id,
            client.session_id,
            client.authenticated
        ])
    
    # Session details
    print("Active sessions details:")
    for session_id in SessionManager.sessions:
        var session = SessionManager.sessions[session_id]
        var unit_spawner = session.game_scene.get_node("UnitSpawner")
        var unit_count = unit_spawner.get_unit_count() if unit_spawner else 0
        
        print("  Session %s: %d players, state: %s, %d units" % [
            session_id,
            session.players.size(),
            session.state,
            unit_count
        ])
    
    print("==================================")

func _print_help() -> void:
    print("=== Server Commands ===")
    print("Q - Quit server")
    print("S - Show detailed statistics")
    print("H - Show this help")
    print("======================")

func _notification(what: int) -> void:
    match what:
        NOTIFICATION_WM_CLOSE_REQUEST:
            print("Server shutdown requested")
            DedicatedServer.stop_server()
            get_tree().quit()
        NOTIFICATION_APPLICATION_FOCUS_OUT:
            # Server keeps running when losing focus
            pass 