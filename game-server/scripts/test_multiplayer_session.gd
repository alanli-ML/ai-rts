extends Node

var test_clients: Array = []
var test_phase: int = 0

func _ready() -> void:
    print("=== Multiplayer Session Test ===")
    print("Testing server-authoritative units with MultiplayerSpawner")

func _on_test_timer_timeout() -> void:
    match test_phase:
        0:
            print("Phase 0: Creating test clients...")
            _create_test_clients()
            test_phase += 1
            _restart_timer(3.0)
        1:
            print("Phase 1: Testing AI commands...")
            _test_ai_commands()
            test_phase += 1
            _restart_timer(5.0)
        2:
            print("Phase 2: Testing unit formations...")
            _test_unit_formations()
            test_phase += 1
            _restart_timer(3.0)
        3:
            print("Phase 3: Testing combat...")
            _test_combat()
            test_phase += 1
            _restart_timer(5.0)
        4:
            print("Phase 4: Cleanup...")
            _cleanup_test()
            print("=== Test Complete ===")

func _create_test_clients() -> void:
    for i in range(2):
        var client = GodotServerClient.new()
        client.name = "TestClient%d" % i
        client.player_name = "Player%d" % i
        client.server_address = "127.0.0.1"
        client.server_port = 7777
        
        add_child(client)
        test_clients.append(client)
        
        client.connect_to_server()
        
        print("Created test client %d" % i)

func _test_ai_commands() -> void:
    print("Testing AI commands...")
    
    for i in range(test_clients.size()):
        var client = test_clients[i]
        if client.is_in_session():
            var unit_ids = ["unit_scout_%d_0" % i, "unit_soldier_%d_1" % i]
            client.send_ai_command("move forward and attack", unit_ids)
            
            await get_tree().create_timer(1.0).timeout
            
            client.send_ai_command("stop all units", unit_ids)

func _test_unit_formations() -> void:
    print("Testing unit formations...")
    
    for i in range(test_clients.size()):
        var client = test_clients[i]
        if client.is_in_session():
            var unit_ids = ["unit_scout_%d_0" % i, "unit_soldier_%d_1" % i, "unit_tank_%d_4" % i]
            client.send_ai_command("form defensive line", unit_ids)
            
            await get_tree().create_timer(2.0).timeout
            
            client.send_ai_command("form circle formation", unit_ids)

func _test_combat() -> void:
    print("Testing combat...")
    
    # Make teams attack each other
    if test_clients.size() >= 2:
        var client1 = test_clients[0]
        var client2 = test_clients[1]
        
        if client1.is_in_session() and client2.is_in_session():
            var unit_ids1 = ["unit_scout_0_0", "unit_soldier_0_1"]
            var unit_ids2 = ["unit_scout_1_0", "unit_soldier_1_1"]
            
            client1.send_ai_command("attack enemy units", unit_ids1)
            client2.send_ai_command("attack enemy units", unit_ids2)

func _cleanup_test() -> void:
    print("Cleaning up test...")
    
    for client in test_clients:
        if client.is_connected():
            client.disconnect_from_server()
    
    test_clients.clear()

func _restart_timer(time: float) -> void:
    var timer = get_node("TestTimer")
    timer.wait_time = time
    timer.start()

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_T:
                print("Restarting test...")
                test_phase = 0
                _on_test_timer_timeout()
            KEY_S:
                print("Skipping to next phase...")
                test_phase += 1
                _on_test_timer_timeout()
            KEY_C:
                print("Cleanup test...")
                _cleanup_test()
            KEY_H:
                print("=== Test Controls ===")
                print("T - Restart test")
                print("S - Skip to next phase")
                print("C - Cleanup")
                print("H - Show help")
                print("===================")

func _notification(what: int) -> void:
    match what:
        NOTIFICATION_WM_CLOSE_REQUEST:
            _cleanup_test()
            get_tree().quit() 