## Zipline — Lets players ride a neon cable between two rooftops
extends Node3D

@export var start_pos: Vector3 = Vector3.ZERO
@export var end_pos: Vector3 = Vector3.ZERO
@export var ride_speed: float = 15.0

@onready var cable_mesh: MeshInstance3D = $CableMesh
@onready var start_area: Area3D = $StartPoint
@onready var end_area: Area3D = $EndPoint
@onready var start_label: Label3D = $StartLabel
@onready var end_label: Label3D = $EndLabel

var player_riding: CharacterBody3D = null
var ride_progress: float = 0.0
var ride_direction: int = 1  # 1 = start->end, -1 = end->start
var is_active: bool = false
var cable_length: float = 0.0


func _ready():
	start_area.body_entered.connect(_on_start_entered)
	start_area.body_exited.connect(_on_start_exited)
	end_area.body_entered.connect(_on_end_entered)
	end_area.body_exited.connect(_on_end_exited)
	start_label.visible = false
	end_label.visible = false


func setup(s: Vector3, e: Vector3):
	start_pos = s
	end_pos = e

	# Position the areas at start and end
	start_area.global_position = start_pos
	end_area.global_position = end_pos
	start_label.global_position = start_pos + Vector3(0, 1.5, 0)
	end_label.global_position = end_pos + Vector3(0, 1.5, 0)

	# Stretch the cable mesh between points
	var midpoint = (start_pos + end_pos) / 2.0
	cable_mesh.global_position = midpoint
	cable_length = start_pos.distance_to(end_pos)

	# Scale the cylinder to match length
	cable_mesh.mesh = CylinderMesh.new()
	cable_mesh.mesh.top_radius = 0.05
	cable_mesh.mesh.bottom_radius = 0.05
	cable_mesh.mesh.height = cable_length

	# Rotate cable to point from start to end
	cable_mesh.look_at(end_pos, Vector3.UP)
	cable_mesh.rotate_object_local(Vector3(1, 0, 0), PI / 2.0)


func _process(delta):
	if !is_active or player_riding == null:
		return

	ride_progress += (ride_speed * delta) / cable_length
	ride_progress = clamp(ride_progress, 0.0, 1.0)

	var current_pos: Vector3
	if ride_direction == 1:
		current_pos = start_pos.lerp(end_pos, ride_progress)
	else:
		current_pos = end_pos.lerp(start_pos, ride_progress)

	# Keep player slightly below the cable
	current_pos.y -= 1.0
	player_riding.global_position = current_pos
	player_riding.velocity = Vector3.ZERO

	# Arrived at destination
	if ride_progress >= 1.0:
		_finish_ride()


func _unhandled_input(event):
	if event.is_action_pressed("interact") and !is_active:
		if _player_near_start():
			_begin_ride(1)
		elif _player_near_end():
			_begin_ride(-1)


func _player_near_start() -> bool:
	return start_label.visible


func _player_near_end() -> bool:
	return end_label.visible


func _begin_ride(direction: int):
	var player = get_tree().root.find_child("Player", true, false)
	if player == null:
		return

	player_riding = player
	ride_direction = direction
	ride_progress = 0.0
	is_active = true

	# Disable player gravity during ride
	if player_riding.has_method("set_physics_process"):
		player_riding.set_physics_process(false)

	start_label.visible = false
	end_label.visible = false

	# Tell server we're riding
	if NetworkManager.socket_client:
		NetworkManager.socket_client.send_event("zipline_ride", {
			"direction": direction,
			"startPos": {"x": start_pos.x, "y": start_pos.y, "z": start_pos.z},
			"endPos": {"x": end_pos.x, "y": end_pos.y, "z": end_pos.z}
		})


func _finish_ride():
	is_active = false
	if player_riding and is_instance_valid(player_riding):
		player_riding.set_physics_process(true)
		player_riding.velocity = Vector3.ZERO
	player_riding = null
	ride_progress = 0.0


func _on_start_entered(body):
	if body.name == "Player":
		start_label.visible = true


func _on_start_exited(body):
	if body.name == "Player":
		start_label.visible = false


func _on_end_entered(body):
	if body.name == "Player":
		end_label.visible = true


func _on_end_exited(body):
	if body.name == "Player":
		end_label.visible = false
