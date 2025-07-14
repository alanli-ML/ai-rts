extends Node

var server_client: Node
var test_phase: int = 0
var test_start_time: float = 0.0
var test_results: Dictionary = {}

func _ready() -> void:
    print("=== Testing Godot Dedicated Server ===")
    print("Starting client connection test...")
    
    # Load and create server client
    var GodotServerClient = load("res://scripts/network/godot_server_client.gd")
    server_client = GodotServerClient.new()
    server_client.name = "ServerClient"
    server_client.player_name = "TestPlayer"
    server_client.server_address = "127.0.0.1"
    server_client.server_port = 7777
    
    add_child(server_client)
    
    # Connect signals
    server_client.connected_to_server.connect(_on_connected_to_server)
    server_client.authentication_result.connect(_on_authentication_result)
    server_client.session_joined.connect(_on_session_joined)
    server_client.ai_command_executed.connect(_on_ai_command_executed)
    server_client.ai_command_error.connect(_on_ai_command_error)
    
    test_start_time = Time.get_ticks_msec()
    
    # Start connection test
    _start_connection_test()

func _start_connection_test() -> void:
    print("Phase 0: Testing server connection...")
    test_phase = 0
    
    if server_client.connect_to_server():
        print("✓ Connection initiated successfully")
        test_results["connection_initiated"] = true
    else:
        print("✗ Failed to initiate connection")
        test_results["connection_initiated"] = false
        _end_test()

func _on_connected_to_server() -> void:
    print("✓ Connected to server successfully")
    test_results["server_connection"] = true
    
    # Authentication should happen automatically
    print("Phase 1: Waiting for authentication...")
    test_phase = 1

func _on_authentication_result(success: bool, player_id: String) -> void:
    if success:
        print("✓ Authentication successful: %s" % player_id)
        test_results["authentication"] = true
        test_phase = 2
    else:
        print("✗ Authentication failed")
        test_results["authentication"] = false
        _end_test()

func _on_session_joined(session_id: String) -> void:
    print("✓ Joined session: %s" % session_id)
    test_results["session_join"] = true
    test_phase = 3
    
    # Wait for units to spawn
    print("Phase 3: Waiting for units to spawn...")
    await get_tree().create_timer(2.0).timeout
    
    # Start AI command testing
    _test_ai_commands()

func _test_ai_commands() -> void:
    print("Phase 4: Testing AI commands...")
    test_phase = 4
    
    # Test basic AI command
    var test_units = ["unit_scout_0_0", "unit_scout_0_1", "unit_soldier_0_2"]
    server_client.send_ai_command("move all units forward", test_units)
    
    # Wait for response
    await get_tree().create_timer(3.0).timeout
    
    # Test formation command
    server_client.send_ai_command("form defensive line", test_units)
    
    await get_tree().create_timer(2.0).timeout
    
    # Test attack command
    server_client.send_ai_command("attack nearest enemies", test_units)
    
    await get_tree().create_timer(2.0).timeout
    
    # Test stop command
    server_client.send_ai_command("stop all units", test_units)
    
    print("✓ AI commands sent successfully")
    test_results["ai_commands"] = true
    
    # Complete test
    _end_test()

func _on_ai_command_executed(data: Dictionary) -> void:
    print("✓ AI command executed: %s" % data.get("commands", []))
    test_results["ai_command_execution"] = true

func _on_ai_command_error(error: String) -> void:
    print("✗ AI command error: %s" % error)
    test_results["ai_command_error"] = error

func _on_test_timer_timeout() -> void:
    var elapsed_time = (Time.get_ticks_msec() - test_start_time) / 1000.0
    
    # Show periodic status
    match test_phase:
        0:
            print("Connecting to server... (%.1fs)" % elapsed_time)
        1:
            print("Authenticating... (%.1fs)" % elapsed_time)
        2:
            print("Joining session... (%.1fs)" % elapsed_time)
        3:
            print("Waiting for units... (%.1fs)" % elapsed_time)
        4:
            print("Testing AI commands... (%.1fs)" % elapsed_time)
    
    # Timeout after 30 seconds
    if elapsed_time > 30.0:
        print("✗ Test timeout after 30 seconds")
        _end_test()

func _end_test() -> void:
    var elapsed_time = (Time.get_ticks_msec() - test_start_time) / 1000.0
    
    print("\n=== Test Results ===")
    print("Test duration: %.1f seconds" % elapsed_time)
    print("Connection initiated: %s" % test_results.get("connection_initiated", false))
    print("Server connection: %s" % test_results.get("server_connection", false))
    print("Authentication: %s" % test_results.get("authentication", false))
    print("Session join: %s" % test_results.get("session_join", false))
    print("AI commands: %s" % test_results.get("ai_commands", false))
    print("AI command execution: %s" % test_results.get("ai_command_execution", false))
    
    if test_results.get("ai_command_error", ""):
        print("AI command error: %s" % test_results.get("ai_command_error"))
    
    # Calculate success rate
    var total_tests = 6
    var passed_tests = 0
    
    for key in ["connection_initiated", "server_connection", "authentication", "session_join", "ai_commands", "ai_command_execution"]:
        if test_results.get(key, false):
            passed_tests += 1
    
    var success_rate = (float(passed_tests) / float(total_tests)) * 100.0
    print("Success rate: %.1f%% (%d/%d)" % [success_rate, passed_tests, total_tests])
    
    if success_rate >= 80.0:
        print("✓ Test PASSED - Server is working correctly!")
    else:
        print("✗ Test FAILED - Server has issues")
    
    print("===================")
    
    # Clean up
    if server_client and server_client.connection_state != 0:  # Not DISCONNECTED
        server_client.disconnect_from_server()
    
    await get_tree().create_timer(2.0).timeout
    get_tree().quit()

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_Q:
                print("Quit requested")
                _end_test()
            KEY_R:
                print("Restarting test...")
                get_tree().reload_current_scene()
            KEY_S:
                print("Skipping to next phase...")
                test_phase += 1
                _on_test_timer_timeout()

func _notification(what: int) -> void:
    match what:
        NOTIFICATION_WM_CLOSE_REQUEST:
            _end_test() 