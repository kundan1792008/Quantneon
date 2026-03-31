extends Node3D

@onready var pivot: Node3D = $Pivot
@onready var vision_cone: SpotLight3D = $Pivot/VisionCone
@onready var detection_area: Area3D = $Pivot/DetectionArea

@export var sweep_speed: float = 0.001
@export var sweep_angle: float = deg_to_rad(45.0)

var is_locked_on: bool = false
var detection_timer: float = 0.0
var target_player: Node3D = null

func _ready() -> void:
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)

func _process(delta: float) -> void:
	if not is_locked_on:
		pivot.rotation.y = sin(Time.get_ticks_msec() * sweep_speed) * sweep_angle
	elif target_player:
		# Smoothly track the player
		var target_pos = target_player.global_position
		target_pos.y += 1.0 # Look at chest level, not feet
		pivot.look_at(target_pos, Vector3.UP)
		# Keep it physically realistic (don't rotate barrel on z/x unless modeled)
		pivot.rotation.x = clamp(pivot.rotation.x, deg_to_rad(-60), deg_to_rad(30))
		pivot.rotation.z = 0

func _physics_process(delta: float) -> void:
	if target_player and not is_locked_on:
		detection_timer += delta
		if detection_timer > 1.5:
			is_locked_on = true
			vision_cone.light_color = Color.RED
			vision_cone.light_energy = 5.0
			
			if has_node("/root/NetworkManager"):
				var manager = get_node("/root/NetworkManager")
				if manager.socket_client:
					manager.socket_client.send_event("camera_detected", {})

func _on_body_entered(body: Node3D) -> void:
	if not is_locked_on and body.name == "Player":
		target_player = body
		detection_timer = 0.0
		vision_cone.light_color = Color.ORANGE

func _on_body_exited(body: Node3D) -> void:
	if body == target_player and not is_locked_on:
		target_player = null
		detection_timer = 0.0
		vision_cone.light_color = Color.RED
