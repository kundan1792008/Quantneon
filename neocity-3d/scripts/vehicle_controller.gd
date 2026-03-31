## NeoCar - Vehicle Controller (GTA-style Hover/Wheel physics)
## Handles acceleration, steering, braking, and player interaction.

extends VehicleBody3D

@export var max_engine_force: float = 300.0
@export var max_steering_angle: float = 0.6
@export var brake_force: float = 20.0
@export var vehicle_id: String = "neocar_prototype"

var driver: Node3D = null
var is_remote: bool = false
var target_pos: Vector3
var target_rot: float

var current_health: float = 100.0
var last_velocity: Vector3 = Vector3.ZERO

@export var is_police: bool = false
var sirens_on: bool = false
var siren_timer: float = 0.0

func set_remote_mode(value: bool):
	is_remote = value
	freeze = value

func _physics_process(delta):
	# Crash detection
	var speed_diff = (last_velocity - linear_velocity).length()
	if driver and not is_remote and speed_diff > 15.0:
		var damage = speed_diff * 0.5
		current_health = max(0.0, current_health - damage)
		print("[Vehicle] CRASH! Damage: ", damage, " Health: ", current_health)
		
		# If mission active, report damage to backend to reduce payout (to be wired if backend supports it later)
		# For now, visually simulate penalty
		var mission_hud = get_node_or_null("/root/VehicleMissionHUD")
		if mission_hud and mission_hud.is_active:
			# Pass the tracked start_time or whatever the internal timer is, rather than parsing a label
			mission_hud._update_display(mission_hud.start_time, current_health)
			
	last_velocity = linear_velocity

	if is_remote:
		# Ensure we stay frozen if remote
		if not freeze: freeze = true
		global_position = global_position.lerp(target_pos, 0.1)
		rotation.y = lerp_angle(rotation.y, target_rot, 0.1)
		_process_sirens(delta)
		return

	_process_sirens(delta)

	if driver:
		# Control inputs
		steering = Input.get_axis("move_right", "move_left") * max_steering_angle
		engine_force = Input.get_axis("move_backward", "move_forward") * max_engine_force
		
		if Input.is_action_pressed("jump"): # SPACE for handbrake
			brake = brake_force
		else:
			brake = 0.0
			
		# Exit vehicle
		if Input.is_action_just_pressed("interact"):
			_exit_vehicle()
			
		# Sync to Network at 10Hz
		if Engine.get_physics_frames() % 6 == 0:
			var nm = get_node_or_null("/root/NetworkManager")
			if nm:
				nm.socket_client.send_event("vehicle_move", {
					"vehicleId": vehicle_id,
					"pos": {"x": global_position.x * 10, "y": global_position.z * 10},
					"rot": rotation.y
				})
	else:
		# Parked
		engine_force = 0.0
		steering = 0.0
		brake = brake_force

func _process_sirens(delta):
	if not is_police or not sirens_on:
		return
		
	siren_timer += delta * 10.0
	var flash = int(siren_timer) % 2
	var mesh = $MeshInstance3D
	if flash == 0:
		mesh.modulate = Color(1, 0, 0) # Red
	else:
		mesh.modulate = Color(0, 0, 1) # Blue

func interact(player):
	if driver == null:
		_enter_vehicle(player)

func _enter_vehicle(player):
	print("[Vehicle] Player entered")
	driver = player
	
	var nm = get_node_or_null("/root/NetworkManager")
	if nm:
		nm.socket_client.send_event("vehicle_enter", {"vehicleId": vehicle_id})
	
	# Reparent player to vehicle or disable player physics
	player.get_parent().remove_child(player)
	add_child(player)
	player.position = Vector3(0, 1.0, 0) # Sit in the car
	player.rotation = Vector3.ZERO
	player.visible = false # Temporary until we have sitting anims
	
	# Transfer camera control? 
	# For simplicity, we can have a camera on the vehicle too.
	$VehicleCamera.make_current()

func _exit_vehicle():
	print("[Vehicle] Player exited")
	var player = driver
	driver = null
	
	var nm = get_node_or_null("/root/NetworkManager")
	if nm:
		nm.socket_client.send_event("vehicle_exit", {"vehicleId": vehicle_id})
	
	remove_child(player)
	get_parent().add_child(player)
	player.global_position = global_position + basis.x * 2.0 # Exit to the left
	player.visible = true
	
	# Give camera back to player
	player.get_node("CameraPivot/SpringArm3D/Camera3D").make_current()
