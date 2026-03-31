extends Area3D

@export var zone_id: String = "DowntownPlaza"
@onready var socket_client: Node = get_node("/root/SocketIOClient")

func _ready():
	# Connect to area signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	print("[CaptureZone] Ready: ", zone_id)

func _on_body_entered(body: Node3D):
	if body.name == "Player":
		print("[CaptureZone] Local player entered: ", zone_id)
		if socket_client and socket_client.has_method("send_event"):
			socket_client.send_event("zone_enter", {"zoneId": zone_id})

func _on_body_exited(body: Node3D):
	if body.name == "Player":
		print("[CaptureZone] Local player left: ", zone_id)
		if socket_client and socket_client.has_method("send_event"):
			socket_client.send_event("zone_leave", {"zoneId": zone_id})
