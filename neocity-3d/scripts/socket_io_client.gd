## Minimal Socket.IO v4 Client for Godot 4
## Handles handshake, namespace connection, and event serialization.

extends Node

signal connected(sid)
signal event_received(event_name, data)
signal disconnected

@export var socket_url: String = "ws://localhost:3000/socket.io/?EIO=4&transport=websocket"
@export var socket_namespace: String = "/world/neocity"

var ws = WebSocketPeer.new()
var is_connected: bool = false
var sid: String = ""
var last_ping: int = 0
var ping_interval: int = 25000
var event_handlers: Dictionary = {}

func _ready():
	set_process(true)
	_connect()

func _connect():
	print("[Network] Connecting to ", socket_url)
	var err = ws.connect_to_url(socket_url)
	if err != OK:
		print("[Network] Connection failed: ", err)

func _process(delta):
	ws.poll()
	var state = ws.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			# Just opened, wait for SocketIO '0' message
			pass
		
		# Heartbeat (Ping/Pong)
		if Time.get_ticks_msec() - last_ping > ping_interval:
			_send_packet("2") # Socket.IO Ping
			last_ping = Time.get_ticks_msec()
			
		while ws.get_available_packet_count() > 0:
			var packet = ws.get_packet().get_string_from_utf8()
			_handle_packet(packet)
			
	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected:
			is_connected = false
			disconnected.emit()
			print("[Network] Disconnected. Retrying in 5s...")
			get_tree().create_timer(5.0).timeout.connect(_connect)

func _handle_packet(packet: String):
	# Socket.IO Packet format: <engine_id><socket_id>[<namespace>,][<data>]
	# 0: Open (Handshake)
	# 2: Ping
	# 3: Pong
	# 40: Namespace Connect
	# 42: Event
	
	if packet.begins_with("0"):
		var raw_data = packet.substr(1)
		var json = JSON.parse_string(raw_data)
		sid = json.sid
		ping_interval = json.pingInterval
		print("[Network] Handshake complete. SID: ", sid)
		# Now connect to namespace
		_send_packet("40" + socket_namespace + ",")
		
	elif packet.begins_with("40" + socket_namespace):
		print("[Network] Connected to namespace: ", socket_namespace)
		is_connected = true
		connected.emit(sid)
		
	elif packet.begins_with("42" + socket_namespace):
		# Format: 42/namespace,["event", {data}]
		var json_start = packet.find("[")
		if json_start != -1:
			var raw_json = packet.substr(json_start)
			var data_array = JSON.parse_string(raw_json)
			if data_array is Array and data_array.size() >= 2:
				var ev_name = data_array[0]
				var ev_data = data_array[1]
				event_received.emit(ev_name, ev_data)
				if event_handlers.has(ev_name):
					event_handlers[ev_name].call(ev_data)
				
	elif packet == "2":
		_send_packet("3") # Pong

func _send_packet(data: String):
	ws.send_text(data)

func send_event(event_name: String, data: Dictionary):
	if is_connected:
		var packet = "42" + socket_namespace + "," + JSON.stringify([event_name, data])
		_send_packet(packet)

func on_event(event_name: String, callback: Callable):
	event_handlers[event_name] = callback
