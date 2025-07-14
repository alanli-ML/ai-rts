# LobbyUI.gd
extends Control

# UI Node references
@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var address_input: LineEdit = $VBoxContainer/AddressInput
@onready var port_input: SpinBox = $VBoxContainer/PortInput
@onready var player_list: ItemList = $VBoxContainer/PlayerList
@onready var ready_button: Button = $VBoxContainer/ReadyButton
@onready var start_button: Button = $VBoxContainer/StartButton
@onready var disconnect_button: Button = $VBoxContainer/DisconnectButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

# State tracking
var is_ready: bool = false

func _ready() -> void:
	# Connect UI signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	
	# Connect NetworkManager signals
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.player_ready_changed.connect(_on_player_ready_changed)
	NetworkManager.match_started_signal.connect(_on_match_started)
	NetworkManager.match_ended_signal.connect(_on_match_ended)
	NetworkManager.network_error_signal.connect(_on_network_error)
	
	# Set initial state
	_update_ui_state()
	
	# Set default values
	address_input.text = "127.0.0.1"
	port_input.value = NetworkManager.DEFAULT_PORT

func _update_ui_state() -> void:
	var state = NetworkManager.current_state
	
	# Show/hide controls based on network state
	var is_offline = state == NetworkManager.NetworkState.OFFLINE
	var is_connected = state == NetworkManager.NetworkState.CONNECTED
	var is_hosting = state == NetworkManager.NetworkState.HOSTING
	var is_in_match = state == NetworkManager.NetworkState.IN_MATCH
	
	# Connection controls
	host_button.visible = is_offline
	join_button.visible = is_offline
	address_input.visible = is_offline
	port_input.visible = is_offline
	
	# Lobby controls
	player_list.visible = is_connected or is_hosting
	ready_button.visible = is_connected or is_hosting
	start_button.visible = is_hosting and not is_in_match
	disconnect_button.visible = not is_offline
	
	# Update button states
	if is_connected or is_hosting:
		ready_button.text = "Ready" if not is_ready else "Not Ready"
		start_button.disabled = not _can_start_match()
	
	# Update status
	match state:
		NetworkManager.NetworkState.OFFLINE:
			status_label.text = "Offline - Select Host or Join"
		NetworkManager.NetworkState.HOSTING:
			status_label.text = "Hosting on port %d - Waiting for players" % NetworkManager.server_port
		NetworkManager.NetworkState.JOINING:
			status_label.text = "Connecting to server..."
		NetworkManager.NetworkState.CONNECTED:
			status_label.text = "Connected to server - Waiting for match"
		NetworkManager.NetworkState.IN_MATCH:
			status_label.text = "In Match - %s" % NetworkManager.match_id

func _update_player_list() -> void:
	player_list.clear()
	
	# Group players by team for cooperative display
	var teams_data = {}
	for player_data in NetworkManager.get_all_players():
		var team_id = player_data.team_id
		if team_id not in teams_data:
			teams_data[team_id] = []
		teams_data[team_id].append(player_data)
	
	# Display teams with their cooperative members
	for team_id in teams_data.keys():
		var team_players = teams_data[team_id]
		var team_text = "TEAM %d - Cooperative Control (%d/2 players)" % [team_id, team_players.size()]
		player_list.add_item(team_text, null, false)  # Team header, not selectable
		
		for player_data in team_players:
			var status_text = "[READY]" if player_data.is_ready else "[NOT READY]"
			var leader_text = " (Leader)" if player_data.is_team_leader else ""
			var teammate_text = ""
			if player_data.teammate_id != -1:
				var teammate = NetworkManager.get_player_data(player_data.teammate_id)
				if teammate:
					teammate_text = " + %s" % teammate.player_name
			
			var display_text = "  %s%s%s %s" % [player_data.player_name, leader_text, teammate_text, status_text]
			player_list.add_item(display_text)

func _can_start_match() -> bool:
	if not NetworkManager.is_server:
		return false
	
	var players = NetworkManager.get_all_players()
	if players.size() < 2:
		return false
	
	for player_data in players:
		if not player_data.is_ready:
			return false
	
	return true

# UI Event Handlers
func _on_host_pressed() -> void:
	var port = int(port_input.value)
	if NetworkManager.host_game(port):
		status_label.text = "Starting server on port %d..." % port
	else:
		status_label.text = "Failed to start server"

func _on_join_pressed() -> void:
	var address = address_input.text.strip_edges()
	var port = int(port_input.value)
	
	if address.is_empty():
		status_label.text = "Please enter server address"
		return
	
	if NetworkManager.join_game(address, port):
		status_label.text = "Connecting to %s:%d..." % [address, port]
	else:
		status_label.text = "Failed to connect"

func _on_ready_pressed() -> void:
	is_ready = not is_ready
	NetworkManager.set_player_ready(is_ready)
	_update_ui_state()

func _on_start_pressed() -> void:
	if NetworkManager.start_match():
		status_label.text = "Starting match..."
	else:
		status_label.text = "Cannot start match - check all players are ready"

func _on_disconnect_pressed() -> void:
	NetworkManager.disconnect_from_game()
	is_ready = false
	_update_ui_state()

# Network Event Handlers
func _on_player_connected(player_data) -> void:
	Logger.info("LobbyUI", "Player connected: %s" % player_data.player_name)
	_update_player_list()
	_update_ui_state()

func _on_player_disconnected(peer_id: int) -> void:
	Logger.info("LobbyUI", "Player disconnected: %d" % peer_id)
	_update_player_list()
	_update_ui_state()

func _on_player_ready_changed(peer_id: int, ready: bool) -> void:
	Logger.info("LobbyUI", "Player %d ready state: %s" % [peer_id, ready])
	_update_player_list()
	_update_ui_state()

func _on_match_started() -> void:
	Logger.info("LobbyUI", "Match started - transitioning to game")
	_update_ui_state()
	
	# Transition to game scene
	await get_tree().create_timer(1.0).timeout
	GameManager.change_state(GameManager.GameState.IN_GAME)

func _on_match_ended(winner_team: int) -> void:
	Logger.info("LobbyUI", "Match ended - winner: Team %d" % winner_team)
	status_label.text = "Match ended - Team %d wins!" % winner_team
	is_ready = false
	_update_ui_state()

func _on_network_error(message: String) -> void:
	Logger.error("LobbyUI", "Network error: %s" % message)
	status_label.text = "Network Error: %s" % message
	is_ready = false
	_update_ui_state()

# Public interface
func show_lobby() -> void:
	visible = true
	_update_ui_state()

func hide_lobby() -> void:
	visible = false 