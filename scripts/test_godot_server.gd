extends Node

@onready var client1: GodotServerClient = GodotServerClient.new()
@onready var client2: GodotServerClient = GodotServerClient.new()

var test_phase: int = 0
var tests_completed: int = 0
var total_tests: int = 6

func _ready() -> void:
    print("=== Starting Godot Server Test ===")
    
    # Set up clients
    client1.player_name = "TestPlayer1"
    client2.player_name = "TestPlayer2"
    
    add_child(client1)
    add_child(client2)
    
    # Connect signals
    client1.session_joined.connect(_on_client1_session_joined)
    client2.session_joined.connect(_on_client2_session_joined)
    client1.ai_command_executed.connect(_on_ai_command_executed)
    client2.ai_command_executed.connect(_on_ai_command_executed)
    
    # Start test
    await get_tree().create_timer(1.0).timeout
    run_tests()

func run_tests() -> void:
    print("Running comprehensive server tests...")
    
    # Test 1: Basic Connection
    print("\n1. Testing basic connection...")
    if client1.connect_to_server():
        await client1.session_joined
        print("✓ Client 1 connected and joined session")
        tests_completed += 1
    else:
        print("✗ Client 1 failed to connect")
    
    # Test 2: Multi-client connection
    print("\n2. Testing multi-client connection...")
    if client2.connect_to_server():
        await client2.session_joined
        print("✓ Client 2 connected and joined session")
        tests_completed += 1
    else:
        print("✗ Client 2 failed to connect")
    
    # Test 3: AI Commands
    print("\n3. Testing AI commands...")
    if client1.is_in_session():
        # Wait for units to spawn
        await get_tree().create_timer(3.0).timeout
        
        # Send AI command with specific unit IDs
        var unit_ids = ["unit_scout_0_0", "unit_scout_0_1", "unit_soldier_0_2"]
        client1.send_ai_command("move all units forward", unit_ids)
        await get_tree().create_timer(2.0).timeout
        print("✓ AI command sent")
        tests_completed += 1
    else:
        print("✗ Client 1 not in session")
    
    # Test 4: Multiple AI Commands
    print("\n4. Testing multiple AI commands...")
    if client1.is_in_session():
        var commands = [
            "attack enemy base",
            "form defensive line",
            "retreat to base"
        ]
        for command in commands:
            var unit_ids = ["unit_scout_0_0", "unit_soldier_0_2"]
            client1.send_ai_command(command, unit_ids)
            await get_tree().create_timer(1.0).timeout
        print("✓ Multiple AI commands sent")
        tests_completed += 1
    else:
        print("✗ Client 1 not in session")
    
    # Test 5: Cross-client AI commands
    print("\n5. Testing cross-client AI commands...")
    if client2.is_in_session():
        var unit_ids = ["unit_scout_1_0", "unit_soldier_1_1"]
        client2.send_ai_command("scout the area", unit_ids)
        await get_tree().create_timer(1.0).timeout
        print("✓ Cross-client AI command sent")
        tests_completed += 1
    else:
        print("✗ Client 2 not in session")
    
    # Test 6: Ping test
    print("\n6. Testing ping...")
    if client1.is_connected_to_server():
        client1.ping_server()
        await get_tree().create_timer(1.0).timeout
        print("✓ Ping test completed")
        tests_completed += 1
    else:
        print("✗ Client 1 not connected")
    
    # Final results
    print_test_results()

func print_test_results() -> void:
    print("\n=== Test Results ===")
    print("Tests completed: %d/%d" % [tests_completed, total_tests])
    print("Success rate: %.1f%%" % (float(tests_completed) / float(total_tests) * 100.0))
    
    if tests_completed == total_tests:
        print("✓ All tests passed!")
    else:
        print("✗ Some tests failed")
    
    # Print client states
    print("\nClient states:")
    print("Client 1: %s" % client1.get_connection_info())
    print("Client 2: %s" % client2.get_connection_info())
    
    print("==================")
    
    # Clean up after tests
    await get_tree().create_timer(2.0).timeout
    cleanup_test()

func cleanup_test() -> void:
    print("\nCleaning up test...")
    client1.disconnect_from_server()
    client2.disconnect_from_server()
    
    await get_tree().create_timer(1.0).timeout
    print("Test cleanup completed")

func _on_client1_session_joined(session_id: String) -> void:
    print("Client 1 joined session: %s" % session_id)

func _on_client2_session_joined(session_id: String) -> void:
    print("Client 2 joined session: %s" % session_id)

func _on_ai_command_executed(data: Dictionary) -> void:
    print("AI command executed: %s by %s" % [data.get("commands", []), data.get("player_id", "")])

# Keyboard shortcuts for manual testing
func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_1:
                print("Manually connecting client 1...")
                client1.connect_to_server()
            KEY_2:
                print("Manually connecting client 2...")
                client2.connect_to_server()
            KEY_A:
                print("Sending AI command from client 1...")
                client1.send_ai_command("test command from client 1")
            KEY_B:
                print("Sending AI command from client 2...")
                client2.send_ai_command("test command from client 2")
            KEY_P:
                print("Pinging server...")
                client1.ping_server()
                client2.ping_server()
            KEY_D:
                print("Disconnecting clients...")
                client1.disconnect_from_server()
                client2.disconnect_from_server()
            KEY_R:
                print("Restarting tests...")
                run_tests()
            KEY_H:
                print_help()

func print_help() -> void:
    print("=== Manual Test Commands ===")
    print("1 - Connect client 1")
    print("2 - Connect client 2")
    print("A - Send AI command (client 1)")
    print("B - Send AI command (client 2)")
    print("P - Ping server")
    print("D - Disconnect clients")
    print("R - Restart tests")
    print("H - Show this help")
    print("============================")

# Auto-run stress test
func run_stress_test() -> void:
    print("\n=== Running Stress Test ===")
    
    # Connect multiple clients rapidly
    for i in range(5):
        var client = GodotServerClient.new()
        client.player_name = "StressClient%d" % i
        add_child(client)
        client.connect_to_server()
        await get_tree().create_timer(0.1).timeout
    
    # Send many AI commands
    await get_tree().create_timer(2.0).timeout
    
    for i in range(20):
        if client1.is_in_session():
            client1.send_ai_command("stress test command %d" % i)
        await get_tree().create_timer(0.1).timeout
    
    print("Stress test completed!")

# Performance monitoring
func _on_performance_timer() -> void:
    print("=== Performance Stats ===")
    print("FPS: %d" % Engine.get_frames_per_second())
    print("Memory usage: %.1f MB" % (OS.get_static_memory_usage() / 1024.0 / 1024.0))
    print("========================")

func _setup_performance_monitoring() -> void:
    var timer = Timer.new()
    timer.wait_time = 5.0
    timer.timeout.connect(_on_performance_timer)
    timer.autostart = true
    add_child(timer) 