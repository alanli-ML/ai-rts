# lobby.gd
extends Control

signal start_match_requested

# UI References
@onready var host_button = $Panel/VBoxContainer/HostButton
@onready var join_button = $Panel/VBoxContainer/JoinButton
@onready var ready_button = $Panel/VBoxContainer/ReadyButton
@onready var start_button = $Panel/VBoxContainer/StartButton
@onready var player_list = $Panel/VBoxContainer/PlayerList
@onready var server_address_input = $Panel/VBoxContainer/ServerAddress

var network_manager
var is_ready: bool = false

func _ready():
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)

	var dc = get_node("/root/DependencyContainer")
	if dc:
		network_manager = dc.get_network_manager()
		if network_manager:
			network_manager.server_created.connect(_on_server_created)
			network_manager.connected_to_server.connect(_on_connected_to_server)
			network_manager.connection_failed.connect(_on_connection_failed)

func _on_host_pressed():
	network_manager.host_game()
	# The host is a client too, so it needs to join its own game.
	# The _on_server_created will handle this.

func _on_join_pressed():
	var address = server_address_input.text
	if address.is_empty():
		address = "127.0.0.1"
	network_manager.join_game(address)

func _on_ready_pressed():
	is_ready = not is_ready
	ready_button.text = "Not Ready" if is_ready else "Ready"
	# Send ready state to server
	get_node("/root/UnifiedMain").rpc_id(1, "handle_player_ready_rpc", is_ready)

func _on_start_pressed():
	# Request server to start the game
	get_node("/root/UnifiedMain").rpc_id(1, "handle_start_game_rpc")

func _on_server_created():
	# The host is also a client, so connect to the server just created.
	print("Lobby: Server created successfully. Host is joining...")
	_on_connected_to_server()

func _on_connected_to_server():
	print("Lobby: Connected to server. Requesting to join session.")
	# The server is always peer_id 1
	get_node("/root/UnifiedMain").rpc_id(1, "handle_join_session_rpc", "")

func _on_connection_failed():
	print("Lobby: Connection failed. Please check the server address and try again.")
	# Optionally, show an error message to the user in the UI.

func update_lobby_display(data: Dictionary):
	if not data.has("players"):
		return
		
	player_list.clear()
	var players = data.get("players", {})
	for player_id in players:
		var player_data = players[player_id]
		var ready_text = "(Ready)" if player_data.get("ready", false) else "(Not Ready)"
		var team_text = "Team %d" % player_data.get("team_id", 0)
		var player_name = player_data.get("player_name", player_id)
		player_list.add_item("%s - %s %s" % [player_name, team_text, ready_text])

	var can_start = data.get("can_start_game", false)
	start_button.disabled = not can_start