class_name Net
extends Node
## LAN multiplayer (1-4 players, join any time). The world is generated the
## same everywhere from its seed, so the host only sends the seed and where
## it is; after that each player sends its own movement ~20 times a second
## (unreliable, relayed by the host) and everyone else draws it as a
## RemotePlayer. The host's game is the one that's saved.
##
## Hosts advertise themselves with a small UDP broadcast every second so the
## join screen can list them; typing the host's IP works too (some phones
## and routers block broadcasts).

signal hosts_changed                          # discovery list updated
signal joined(info: Dictionary)               # client: {seed, pos, yaw, number}
signal join_failed(reason: String)
signal disconnected(reason: String)           # client lost the host
signal roster_changed
signal peer_state(id: int, state: Dictionary)
signal peer_left(id: int)

const PORT := 47120
const DISCOVERY_PORT := 47121
const MAX_PLAYERS := 4
const MAGIC := "BROOMS1"

var active := false
var is_host := false
## id -> {"number": int, "name": String}
var roster := {}
## ip -> {"name", "players", "last"}
var hosts := {}
## Called on the host when someone joins: returns {seed, pos, yaw}.
var world_info: Callable

var _beacon: PacketPeerUDP
var _listener: PacketPeerUDP
var _beacon_t := 0.0
var _name := "Player"
var _number := 7


func _ready() -> void:
	# Network node paths relative to the Game node, so they match on every
	# device whatever the scene tree above it looks like.
	(multiplayer as SceneMultiplayer).root_path = get_parent().get_path()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void:
		_close()
		join_failed.emit("Couldn't connect to that game."))
	multiplayer.server_disconnected.connect(func() -> void:
		_close()
		disconnected.emit("Lost the connection to the host."))


func my_id() -> int:
	return multiplayer.get_unique_id() if active else 1


func my_number() -> int:
	return int(roster.get(my_id(), {}).get("number", _number))


# --------------------------------------------------------------- hosting ---
func host(player_name: String, number: int) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	_name = player_name
	_number = number
	roster = {1: {"number": number, "name": player_name}}
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	roster_changed.emit()
	return OK


func join(ip: String, player_name: String, number: int) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = false
	_name = player_name
	_number = number
	return OK


func leave() -> void:
	if active and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	_close()


func _close() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	is_host = false
	roster.clear()
	_beacon = null


# ------------------------------------------------------------- discovery ---
## Start/stop listening for hosts on the LAN (join screen).
func browse(on: bool) -> void:
	if on and _listener == null:
		_listener = PacketPeerUDP.new()
		if _listener.bind(DISCOVERY_PORT) != OK:
			_listener = null
	elif not on and _listener != null:
		_listener.close()
		_listener = null
		hosts.clear()


func _process(delta: float) -> void:
	if _beacon and is_host:
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			var msg := "%s|%s|%d|%d" % [MAGIC, _name.replace("|", " "), roster.size(), MAX_PLAYERS]
			_beacon.put_packet(msg.to_utf8_buffer())
	if _listener:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var pkt := _listener.get_packet().get_string_from_utf8()
			var ip := _listener.get_packet_ip()
			var parts := pkt.split("|")
			if parts.size() >= 4 and parts[0] == MAGIC:
				hosts[ip] = {"name": parts[1], "players": int(parts[2]), "max": int(parts[3]), "last": Time.get_ticks_msec()}
				changed = true
		var now := Time.get_ticks_msec()
		for ip in hosts.keys():
			if now - int(hosts[ip].last) > 3500:
				hosts.erase(ip)
				changed = true
		if changed:
			hosts_changed.emit()


## This device's LAN addresses (shown on the host's screen for manual joins).
static func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and a.count(".") == 3):
			out.append(a)
	return out


# ------------------------------------------------------------- handshake ---
func _on_connected() -> void:
	_hello.rpc_id(1, _number, _name)


func _on_peer_connected(id: int) -> void:
	_relax_timeout(id)


## ENet drops a peer after ~30 s without an answer at most. A weak phone can
## stall that long (building the Field, compiling shaders) and phone Wi-Fi
## naps in power saving, so allow up to 90 s before calling it lost.
func _relax_timeout(id: int) -> void:
	var mp := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if mp == null:
		return
	var p := mp.get_peer(id)
	if p:
		p.set_timeout(0, 20000, 90000)


func _on_peer_disconnected(id: int) -> void:
	if roster.has(id):
		roster.erase(id)
		if is_host:
			_set_roster.rpc(roster)
		roster_changed.emit()
	peer_left.emit(id)


@rpc("any_peer", "reliable")
func _hello(number: int, player_name: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if roster.size() >= MAX_PLAYERS:
		_refuse.rpc_id(id, "That game is full (%d players)." % MAX_PLAYERS)
		return
	# Everyone gets a different number: the one they chose, or the next free.
	var taken := {}
	for k in roster:
		taken[int(roster[k].number)] = true
	var n := clampi(number, 0, 99)
	while taken.has(n):
		n = (n + 1) % 100
	roster[id] = {"number": n, "name": player_name.left(16)}
	var info: Dictionary = world_info.call() if world_info.is_valid() else {}
	info["number"] = n
	_welcome.rpc_id(id, info)
	_set_roster.rpc(roster)
	roster_changed.emit()


@rpc("authority", "reliable")
func _welcome(info: Dictionary) -> void:
	joined.emit(info)


@rpc("authority", "reliable")
func _refuse(reason: String) -> void:
	leave()
	join_failed.emit(reason)


@rpc("authority", "reliable", "call_local")
func _set_roster(r: Dictionary) -> void:
	roster = r
	roster_changed.emit()


# ------------------------------------------------------------ gameplay ---
## Sends this player's state to everyone (called ~20 times a second).
func send_state(state: Dictionary) -> void:
	if active and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_state.rpc(state)


@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func _state(state: Dictionary) -> void:
	peer_state.emit(multiplayer.get_remote_sender_id(), state)
