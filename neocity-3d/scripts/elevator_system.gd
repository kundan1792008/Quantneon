extends AnimatableBody3D

@onready var interact_area: Area3D = $InteractArea
@onready var floor_label: Label3D = $FloorLabel

var elevator_id: String = ""
var current_floor: int = 0
var target_floor: int = 0
var current_state: String = "idle"
var target_y: float = 0.0

@onready var network = get_node("/root/NetworkManager")

func _ready():
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)

func _process(delta: float):
	# Smoothly interpolate the Y position based on physical state from the server
	if abs(target_y - position.y) > 0.05:
		position.y = lerp(position.y, target_y, 10.0 * delta)
	else:
		position.y = target_y
	
	# Update Label visual
	if current_state == "moving_up" or current_state == "moving_down":
		floor_label.text = "Moving to Floor: " + str(target_floor)
		floor_label.modulate = Color(1.0, 0.5, 0.0) # ORANGE
	elif current_state == "doors_open":
		floor_label.text = "Floor: " + str(current_floor) + "\nDoors Open"
		floor_label.modulate = Color(0.0, 1.0, 0.0) # GREEN
	else:
		floor_label.text = "Floor: " + str(current_floor) + "\n[E] Use Elevator"
		floor_label.modulate = Color(1.0, 1.0, 1.0) # WHITE

func set_remote_mode(mode: bool):
	pass # Defining this prevents network_manager from tweening 'global_position' and fighting our Y-axis lerp.

func update_state(data: Dictionary):
	elevator_id = data.get("id", elevator_id)
	current_floor = data.get("currentFloor", current_floor)
	target_floor = data.get("targetFloor", target_floor)
	current_state = data.get("state", current_state)
	
	if data.has("currentY"):
		target_y = data.currentY
	
	if data.has("position"):
		var pos = data.position
		position.x = pos.get("x", position.x)
		position.z = pos.get("y", position.z) # In 2D space Y maps to physical Z

func _unhandled_input(event):
	if event.is_action_pressed("interact"):
		var players = interact_area.get_overlapping_bodies()
		for p in players:
			if p.is_in_group("local_player"):
				if network and network.socket:
					var requested_floor = 0
					if current_floor == 0:
						requested_floor = 1
					else:
						requested_floor = 0
					
					if current_state == "idle" or current_state == "doors_open":
						network.socket.emit("select_floor", {"elevatorId": elevator_id, "floor": requested_floor})
						print("Local player requested elevator floor: ", requested_floor)
				break

func _on_body_entered(body: Node3D):
	if body.is_in_group("local_player"):
		floor_label.outline_modulate = Color(1.0, 1.0, 0.0) # YELLOW

func _on_body_exited(body: Node3D):
	if body.is_in_group("local_player"):
		floor_label.outline_modulate = Color(0.0, 0.0, 0.0) # BLACK
