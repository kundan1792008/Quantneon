## HoverBike — Fast flying vehicle for Neo City
## Players press E near it to mount, then WASD + Space/Ctrl to fly
extends CharacterBody3D

@export var hover_height: float = 3.0
@export var max_speed: float = 25.0
@export var acceleration: float = 12.0
@export var turn_speed: float = 3.0
@export var vertical_speed: float = 8.0
@export var gravity: float = 15.0
@export var hover_force: float = 20.0

@onready var bike_model: Node3D = $BikeModel
@onready var mount_area: Area3D = $MountArea
@onready var mount_label: Label3D = $MountLabel
@onready var engine_particles: GPUParticles3D = $EngineParticles if has_node("EngineParticles") else null

var driver: CharacterBody3D = null
var is_mounted: bool = false
var current_speed: float = 0.0
var player_nearby: bool = false
var bike_id: String = ""

func _ready():
	mount_area.body_entered.connect(_on_body_entered)
	mount_area.body_exited.connect(_on_body_exited)
	mount_label.visible = false

func _unhandled_input(event):
	if event.is_action_pressed("interact"):
		if player_nearby and !is_mounted:
			_mount_player()
		elif is_mounted:
			_dismount_player()

func _physics_process(delta):
	if !is_mounted:
		# Idle hover bob
		var bob = sin(Time.get_ticks_msec() * 0.002) * 0.15
		if bike_model:
			bike_model.position.y = bob
		return

	# Flying controls
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	# Forward/backward thrust
	var forward = -global_basis.z
	var right_vec = global_basis.x
	
	if input_dir.y != 0:
		current_speed = lerp(current_speed, max_speed * (-input_dir.y), acceleration * delta)
	else:
		current_speed = lerp(current_speed, 0.0, acceleration * 0.5 * delta)
	
	velocity.x = forward.x * current_speed + right_vec.x * input_dir.x * max_speed * 0.5
	velocity.z = forward.z * current_speed + right_vec.z * input_dir.x * max_speed * 0.5
	
	# Vertical control
	if Input.is_action_pressed("jump"):
		velocity.y = vertical_speed
	elif Input.is_action_pressed("sprint"):
		velocity.y = -vertical_speed
	else:
		# Hover at current height (gentle gravity resist)
		if global_position.y > hover_height:
			velocity.y = lerp(velocity.y, 0.0, 3.0 * delta)
		else:
			velocity.y = hover_force * delta
	
	# Turning with mouse (yaw)
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		pass  # Camera handles rotation
	
	# Tilt bike model based on speed
	if bike_model:
		var tilt_angle = clamp(current_speed * 0.02, -0.3, 0.3)
		bike_model.rotation.x = lerp(bike_model.rotation.x, -tilt_angle, 5.0 * delta)
		var roll = clamp(input_dir.x * 0.4, -0.4, 0.4)
		bike_model.rotation.z = lerp(bike_model.rotation.z, -roll, 5.0 * delta)
	
	move_and_slide()
	
	# Sync to server
	if Engine.get_physics_frames() % 6 == 0:
		if NetworkManager.socket_client:
			NetworkManager.socket_client.send_event("vehicle_move", {
				"vehicleId": bike_id,
				"x": global_position.x * 10,
				"y": global_position.z * 10,
				"altitude": global_position.y,
				"r": rotation.y
			})


func _mount_player():
	var player = get_tree().root.find_child("Player", true, false)
	if player == null:
		return
	
	driver = player
	is_mounted = true
	
	# Hide player and take control
	driver.visible = false
	driver.set_physics_process(false)
	mount_label.visible = false
	
	# Parent camera to bike
	var cam_pivot = driver.get_node_or_null("CameraPivot")
	if cam_pivot:
		driver.remove_child(cam_pivot)
		add_child(cam_pivot)
		cam_pivot.position = Vector3(0, 2, 0)
	
	if engine_particles:
		engine_particles.emitting = true
	
	# Tell server
	if NetworkManager.socket_client:
		NetworkManager.socket_client.send_event("hover_bike_enter", {
			"vehicleId": bike_id
		})


func _dismount_player():
	if driver == null:
		return
	
	is_mounted = false
	
	# Return camera to player
	var cam_pivot = get_node_or_null("CameraPivot")
	if cam_pivot:
		remove_child(cam_pivot)
		driver.add_child(cam_pivot)
		cam_pivot.position = Vector3(0, 0, 0)
	
	# Restore player
	driver.visible = true
	driver.set_physics_process(true)
	driver.global_position = global_position + Vector3(2, 0, 0)
	driver.velocity = Vector3.ZERO
	driver = null
	
	if engine_particles:
		engine_particles.emitting = false
	
	# Tell server
	if NetworkManager.socket_client:
		NetworkManager.socket_client.send_event("hover_bike_exit", {
			"vehicleId": bike_id
		})


func _on_body_entered(body):
	if body.name == "Player" and !is_mounted:
		player_nearby = true
		mount_label.visible = true

func _on_body_exited(body):
	if body.name == "Player":
		player_nearby = false
		mount_label.visible = false
