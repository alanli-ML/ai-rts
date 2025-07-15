# main_client.gd
extends Node3D

# Client display manager (singleton)
var client_display_manager: ClientDisplayManager

# Camera setup
var camera: Camera3D
var camera_pivot: Node3D

# UI components
var ui_root: Control
var connection_ui: Control
var game_ui: Control

# State
var is_connected: bool = false
var is_in_game: bool = false

func _ready() -> void:
    Logger.info("MainClient", "Starting AI-RTS Client...")
    
    # Set up camera
    _setup_camera()
    
    # Set up UI
    _setup_ui()
    
    # Initialize client display manager
    client_display_manager = ClientDisplayManager.new()
    client_display_manager.name = "ClientDisplayManager"
    add_child(client_display_manager)
    
    # Connect signals
    client_display_manager.connection_status_changed.connect(_on_connection_status_changed)
    client_display_manager.unit_selected.connect(_on_units_selected)
    client_display_manager.ai_command_entered.connect(_on_ai_command_entered)
    
    Logger.info("MainClient", "Client initialized successfully")
    
    # Show connection UI
    _show_connection_ui()

func _setup_camera() -> void:
    # Create camera pivot for smooth camera movement
    camera_pivot = Node3D.new()
    camera_pivot.name = "CameraPivot"
    add_child(camera_pivot)
    
    # Create camera
    camera = Camera3D.new()
    camera.name = "Camera3D"
    camera.position = Vector3(0, 20, 20)
    camera.look_at(Vector3.ZERO, Vector3.UP)
    camera_pivot.add_child(camera)
    
    Logger.info("MainClient", "Camera setup complete")

func _setup_ui() -> void:
    # Create UI root
    ui_root = Control.new()
    ui_root.name = "UIRoot"
    ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(ui_root)
    
    # Create connection UI
    connection_ui = _create_connection_ui()
    ui_root.add_child(connection_ui)
    
    # Create game UI
    game_ui = _create_game_ui()
    ui_root.add_child(game_ui)
    game_ui.visible = false
    
    Logger.info("MainClient", "UI setup complete")

func _create_connection_ui() -> Control:
    var container = VBoxContainer.new()
    container.name = "ConnectionUI"
    container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    
    # Title
    var title = Label.new()
    title.text = "AI-RTS Cooperative Game"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    container.add_child(title)
    
    # Server address input
    var address_label = Label.new()
    address_label.text = "Server Address:"
    container.add_child(address_label)
    
    var address_input = LineEdit.new()
    address_input.name = "AddressInput"
    address_input.text = "127.0.0.1"
    address_input.custom_minimum_size = Vector2(200, 30)
    container.add_child(address_input)
    
    # Port input
    var port_label = Label.new()
    port_label.text = "Port:"
    container.add_child(port_label)
    
    var port_input = SpinBox.new()
    port_input.name = "PortInput"
    port_input.value = 7777
    port_input.min_value = 1024
    port_input.max_value = 65535
    container.add_child(port_input)
    
    # Connect button
    var connect_button = Button.new()
    connect_button.name = "ConnectButton"
    connect_button.text = "Connect to Server"
    connect_button.pressed.connect(_on_connect_pressed)
    container.add_child(connect_button)
    
    # Status label
    var status_label = Label.new()
    status_label.name = "StatusLabel"
    status_label.text = "Not connected"
    status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    container.add_child(status_label)
    
    return container

func _create_game_ui() -> Control:
    var container = VBoxContainer.new()
    container.name = "GameUI"
    container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    
    # Selected units display
    var selected_units_label = Label.new()
    selected_units_label.name = "SelectedUnitsLabel"
    selected_units_label.text = "No units selected"
    container.add_child(selected_units_label)
    
    # AI command input
    var ai_input_label = Label.new()
    ai_input_label.text = "AI Command (Press Enter):"
    container.add_child(ai_input_label)
    
    var ai_input = LineEdit.new()
    ai_input.name = "AIInput"
    ai_input.placeholder_text = "Enter AI command for selected units..."
    ai_input.custom_minimum_size = Vector2(400, 30)
    ai_input.text_submitted.connect(_on_ai_input_submitted)
    container.add_child(ai_input)
    
    # Disconnect button
    var disconnect_button = Button.new()
    disconnect_button.name = "DisconnectButton"
    disconnect_button.text = "Disconnect"
    disconnect_button.pressed.connect(_on_disconnect_pressed)
    container.add_child(disconnect_button)
    
    return container

func _show_connection_ui() -> void:
    connection_ui.visible = true
    game_ui.visible = false

func _show_game_ui() -> void:
    connection_ui.visible = false
    game_ui.visible = true

func _on_connect_pressed() -> void:
    var address_input = connection_ui.get_node("AddressInput") as LineEdit
    var port_input = connection_ui.get_node("PortInput") as SpinBox
    var status_label = connection_ui.get_node("StatusLabel") as Label
    
    var address = address_input.text.strip_edges()
    var port = int(port_input.value)
    
    if address.is_empty():
        status_label.text = "Please enter server address"
        return
    
    status_label.text = "Connecting to %s:%d..." % [address, port]
    client_display_manager.connect_to_server(address, port)

func _on_disconnect_pressed() -> void:
    client_display_manager.disconnect_from_server()

func _on_connection_status_changed(connected: bool) -> void:
    is_connected = connected
    var status_label = connection_ui.get_node("StatusLabel") as Label
    
    if connected:
        status_label.text = "Connected to server"
        _show_game_ui()
        is_in_game = true
        Logger.info("MainClient", "Connected to server successfully")
    else:
        status_label.text = "Disconnected from server"
        _show_connection_ui()
        is_in_game = false
        Logger.info("MainClient", "Disconnected from server")

func _on_units_selected(unit_ids: Array) -> void:
    var selected_units_label = game_ui.get_node("SelectedUnitsLabel") as Label
    
    if unit_ids.size() == 0:
        selected_units_label.text = "No units selected"
    else:
        selected_units_label.text = "Selected: %d units" % unit_ids.size()

func _on_ai_input_submitted(command: String) -> void:
    var ai_input = game_ui.get_node("AIInput") as LineEdit
    
    if command.strip_edges().is_empty():
        return
    
    # Clear input
    ai_input.text = ""
    
    # Send command
    client_display_manager.ai_command_entered.emit(command)
    Logger.info("MainClient", "AI command sent: %s" % command)

func _on_ai_command_entered(command: String) -> void:
    Logger.info("MainClient", "AI command processed: %s" % command)

func _input(event: InputEvent) -> void:
    if not is_in_game:
        return
    
    # Handle camera movement
    if event is InputEventKey:
        _handle_camera_input(event)
    elif event is InputEventMouseButton:
        _handle_mouse_input(event)

func _handle_camera_input(event: InputEventKey) -> void:
    var camera_speed = 20.0
    var camera_delta = get_process_delta_time() * camera_speed
    
    if event.pressed:
        match event.keycode:
            KEY_W, KEY_UP:
                camera_pivot.translate(Vector3(0, 0, -camera_delta))
            KEY_S, KEY_DOWN:
                camera_pivot.translate(Vector3(0, 0, camera_delta))
            KEY_A, KEY_LEFT:
                camera_pivot.translate(Vector3(-camera_delta, 0, 0))
            KEY_D, KEY_RIGHT:
                camera_pivot.translate(Vector3(camera_delta, 0, 0))
            KEY_ENTER:
                # Focus AI input
                var ai_input = game_ui.get_node("AIInput") as LineEdit
                ai_input.grab_focus()

func _handle_mouse_input(event: InputEventMouseButton) -> void:
    # Mouse wheel for zoom
    if event.button_index == MOUSE_BUTTON_WHEEL_UP:
        var new_pos = camera.position * 0.9
        camera.position = new_pos
        camera.look_at(Vector3.ZERO, Vector3.UP)
    elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
        var new_pos = camera.position * 1.1
        camera.position = new_pos
        camera.look_at(Vector3.ZERO, Vector3.UP)

func _process(delta: float) -> void:
    # Update camera to follow action if needed
    pass

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        if client_display_manager:
            client_display_manager.disconnect_from_server()
        get_tree().quit() 