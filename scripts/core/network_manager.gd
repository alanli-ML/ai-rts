# NetworkManager.gd - Handles creating and joining multiplayer games.
class_name NetworkManager
extends Node

const DEFAULT_PORT = 7777
const MAX_CLIENTS = 4

var peer: ENetMultiplayerPeer
var dependency_container
var is_hosting: bool = false

signal server_created
signal connected_to_server
signal connection_failed

func _ready():
    dependency_container = get_node("/root/DependencyContainer")
    
    # Connect multiplayer signals
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func host_game(port: int = DEFAULT_PORT):
    peer = ENetMultiplayerPeer.new()
    var error = peer.create_server(port, MAX_CLIENTS)
    if error != OK:
        print("Failed to create server.")
        return

    multiplayer.multiplayer_peer = peer
    is_hosting = true
    print("Server created on port %d." % port)
    
    # A client that hosts is also a server, so it needs server dependencies.
    dependency_container.create_server_dependencies()
    
    server_created.emit()

func join_game(address: String, port: int = DEFAULT_PORT):
    # Don't try to join if we're already hosting
    if is_hosting:
        print("Already hosting - no need to join as client")
        connected_to_server.emit()  # Simulate successful connection for hosted games
        return
        
    peer = ENetMultiplayerPeer.new()
    var error = peer.create_client(address, port)
    if error != OK:
        print("Failed to create client.")
        connection_failed.emit()
        return
    
    multiplayer.multiplayer_peer = peer
    print("Joining server at %s:%d..." % [address, port])

func disconnect_from_game():
    if multiplayer.multiplayer_peer:
        multiplayer.multiplayer_peer.close()
        multiplayer.multiplayer_peer = null
    is_hosting = false

func _on_connected_to_server():
    print("NetworkManager: Connected to server!")
    connected_to_server.emit()

func _on_connection_failed():
    print("NetworkManager: Connection failed.")
    connection_failed.emit()

func _on_peer_connected(id: int):
    print("NetworkManager: Peer connected: " + str(id))
    if dependency_container.is_server_mode():
        var session_manager = dependency_container.get_node_or_null("SessionManager")
        if session_manager:
            session_manager.on_client_connected(id)

func _on_peer_disconnected(id: int):
    print("NetworkManager: Peer disconnected: " + str(id))
    if dependency_container.is_server_mode():
        var session_manager = dependency_container.get_node_or_null("SessionManager")
        if session_manager:
            session_manager.on_client_disconnected(id, {})