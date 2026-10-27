extends Node
# Сеть (автозагрузка "Net"): режим игры, ENet-сервер/клиент, поиск игр по LAN через UDP-рассылку.

signal peers_changed
signal joined_ok
signal join_failed
signal server_lost

const PORT := 24680
const DISC_PORT := 24681
const MAX_PLAYERS := 4

var mode := "single"        # single / host / client
var player_name := "Игрок"
var started := false
var names := {}             # peer_id -> имя
var found := {}             # ip -> {name, n, t}

var _bcast: PacketPeerUDP
var _listen: PacketPeerUDP
var _bcast_t := 0.0
var _wired := false


func _wire() -> void:
	if _wired:
		return
	_wired = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


func host_game() -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return false
	multiplayer.multiplayer_peer = peer
	mode = "host"
	started = false
	names = {1: player_name}
	_wire()
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	_bcast.set_dest_address("255.255.255.255", DISC_PORT)
	return true


func join_game(ip: String) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), PORT)
	if err != OK:
		return false
	multiplayer.multiplayer_peer = peer
	mode = "client"
	started = false
	names = {}
	_wire()
	return true


func leave() -> void:
	stop_listen()
	_bcast = null
	var p := multiplayer.multiplayer_peer
	if p != null:
		p.close()
	multiplayer.multiplayer_peer = null
	mode = "single"
	started = false
	names = {}


func start_game() -> void:
	if mode == "host":
		multiplayer.multiplayer_peer.refuse_new_connections = true
		rpc("_do_start")
	else:
		_do_start()


@rpc("authority", "call_local", "reliable")
func _do_start() -> void:
	started = true
	get_tree().change_scene_to_file("res://main.tscn")


@rpc("any_peer", "reliable")
func _reg_name(n: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	names[id] = n.substr(0, 16)
	if multiplayer.is_server():
		rpc("_sync_names", names)
	peers_changed.emit()


@rpc("authority", "reliable")
func _sync_names(d: Dictionary) -> void:
	names = d
	peers_changed.emit()


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server() and started:
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	names.erase(id)
	if multiplayer.is_server() and not started:
		rpc("_sync_names", names)
	peers_changed.emit()


func _on_connected() -> void:
	rpc_id(1, "_reg_name", player_name)
	joined_ok.emit()


func _on_failed() -> void:
	leave()
	join_failed.emit()


func _on_server_gone() -> void:
	leave()
	server_lost.emit()


# ---------- поиск игр в локальной сети ----------

func start_listen() -> void:
	stop_listen()
	found.clear()
	_listen = PacketPeerUDP.new()
	_listen.set_broadcast_enabled(true)
	if _listen.bind(DISC_PORT) != OK:
		_listen = null


func stop_listen() -> void:
	if _listen != null:
		_listen.close()
		_listen = null


func local_ips() -> Array:
	var res: Array = []
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.count(".") == 3 and not s.begins_with("127.") and not s.begins_with("169.254."):
			res.append(s)
	return res


func _process(delta: float) -> void:
	if mode == "host" and not started and _bcast != null:
		_bcast_t += delta
		if _bcast_t >= 1.0:
			_bcast_t = 0.0
			var msg := "METEL|%s|%d" % [player_name, names.size()]
			_bcast.put_packet(msg.to_utf8_buffer())
	if _listen != null:
		while _listen.get_available_packet_count() > 0:
			var txt: String = _listen.get_packet().get_string_from_utf8()
			var ip: String = _listen.get_packet_ip()
			var parts := txt.split("|")
			if parts.size() >= 3 and parts[0] == "METEL":
				found[ip] = {"name": parts[1], "n": parts[2], "t": Time.get_ticks_msec()}
		for k in found.keys():
			if Time.get_ticks_msec() - int(found[k]["t"]) > 4500:
				found.erase(k)
