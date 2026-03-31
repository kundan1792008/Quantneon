extends Node3D

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var label: Label3D = $Label3D
@onready var light: OmniLight3D = $OmniLight3D

var drop_id: String = ""
var item_id: String = ""
var amount: int = 1

func _ready():
	# Visual customization based on what dropped
	if item_id == "medkit":
		label.text = "[ MEDKIT ]"
		light.light_color = Color(0, 1, 0) # Green for health
	elif item_id == "cyber_pistol":
		label.text = "[ CYBER PISTOL ]"
		light.light_color = Color(1, 0.5, 0) # Orange for weapon
	elif item_id == "neon_coin_stack":
		label.text = "[ NEON COINS ]"
		light.light_color = Color(1, 1, 0) # Yellow for money
	else:
		label.text = "[ " + item_id.to_upper() + " ]"
	
	# The properties might be set right after instantiation by NetworkManager
	# So we call a refresh setup here
	call_deferred("_apply_data")

func _apply_data():
	# If network manager sets these, ensure UI updates
	if label.text == "ITEM" and item_id != "":
		_ready()

func _process(delta):
	# Spin the loot drop for visual effect
	mesh.rotate_y(2.0 * delta)
	# Float up and down
	mesh.position.y = 0.5 + sin(Time.get_ticks_msec() * 0.003) * 0.1

func interact():
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.socket_client:
		print("Picking up item: ", item_id)
		nm.socket_client.send_event("inventory_pickup", {"dropId": drop_id})
		# Immediate hide for responsiveness
		hide()
