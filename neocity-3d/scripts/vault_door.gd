## Vault Door for Neo City
## Interactable object that starts a heist.

extends Node3D

@export var vault_id: String = ""
@export var is_breached: bool = false
@export var progress: float = 0.0
@export var alarm_active: bool = false

@onready var interaction_area: Area3D = $InteractionArea
@onready var status_label: Label3D = $StatusLabel
@onready var door_mesh: MeshInstance3D = $DoorMesh

var state_colors = {
	"locked": Color.CYAN,
	"hacking": Color.YELLOW,
	"breached": Color.GREEN,
	"cooldown": Color.GRAY
}

var lasers: Array = []
var current_vault_state: String = ""

func _ready():
	_spawn_lasers()
	_update_visuals("locked")

func _spawn_lasers():
	var laser_scene = preload("res://scenes/security_laser.tscn")
	if not laser_scene: return
	
	# Spawn 3 rotating lasers around the vault
	for i in range(3):
		var laser = laser_scene.instantiate()
		add_child(laser)
		
		# Position them in a triangle around the vault door
		var angle = (i * 120.0) * (PI / 180.0)
		var radius = 6.0
		laser.position = Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		
		# Point lasers outward
		laser.rotation.y = angle
		laser.sweep_speed = 1.5 + (i * 0.2)
		lasers.append(laser)

func update_state(data: Dictionary):
	vault_id = data.id
	current_vault_state = data.state
	progress = data.progress
	alarm_active = data.alarm
	
	_update_visuals(current_vault_state)

func _update_visuals(state: String):
	if status_label:
		var txt = state.to_upper()
		if state == "hacking":
			txt += " (" + str(int(progress)) + "%)"
		if alarm_active:
			txt += " [ALARM]"
		status_label.text = txt
		status_label.modulate = state_colors.get(state, Color.WHITE)
	
	# Rotate door if breached
	if state == "breached":
		door_mesh.rotation.y = lerp_angle(door_mesh.rotation.y, deg_to_rad(90), 0.1)
	else:
		door_mesh.rotation.y = lerp_angle(door_mesh.rotation.y, 0, 0.1)
		
	# Toggle Lasers
	for laser in lasers:
		if is_instance_valid(laser):
			# Give each laser the vault_id so trips are reported correctly
			if laser.has_method("set_vault"):
				laser.set_vault(vault_id)
				
			# Disable lasers if breached or on cooldown
			if state == "locked" or state == "hacking":
				laser.visible = true
				laser.active = true
			else:
				laser.visible = false
				laser.active = false

func interact(player):
	if current_vault_state == "breached" or current_vault_state == "cooldown" or alarm_active:
		print("[Vault] Vault unavailable or alarm active.")
		return
		
	print("[Vault] Initiating hacking mini-game...")
	var mini_game_scene = preload("res://ui/hacking_mini_game.tscn")
	var inst = mini_game_scene.instantiate()
	get_tree().root.add_child(inst)
	
	inst.completed.connect(_on_hacking_completed)
	inst.failed.connect(_on_hacking_failed)

func _on_hacking_completed():
	print("[Vault] Hacking sequence complete. Notifying server.")
	var nm = get_node_or_null("/root/NetworkManager")
	if nm:
		nm.socket_client.send_event("start_heist", {"vaultId": vault_id})

func _on_hacking_failed():
	print("[Vault] Hacking sequence failed.")
	# Maybe trigger alarm early?
	var nm = get_node_or_null("/root/NetworkManager")
	if nm:
		nm.socket_client.send_event("detect_crime", {"offense": "hacking_failure", "vaultId": vault_id})
