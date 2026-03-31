## SubwaySystem — Underground fast-travel between city stations
extends Node3D

@export var station_id: String = "downtown_central"
@export var station_name: String = "Downtown Central"

@onready var trigger_zone: Area3D = $TriggerZone
@onready var station_label: Label3D = $StationLabel
@onready var dest_label: Label3D = $DestinationLabel

var player_in_range: bool = false
var destinations: Array = [
	{"id": "downtown_central", "name": "Downtown Central", "pos": Vector3(0, 2, 10)},
	{"id": "industrial_north", "name": "Industrial North", "pos": Vector3(-25, 2, -30)},
	{"id": "tower_district", "name": "Tower District", "pos": Vector3(50, 2, -10)},
	{"id": "shadow_alley", "name": "Shadow Alley", "pos": Vector3(-35, 2, 35)},
]
var selected_dest_index: int = 0
var is_traveling: bool = false


func _ready():
	trigger_zone.body_entered.connect(_on_body_entered)
	trigger_zone.body_exited.connect(_on_body_exited)
	station_label.text = station_name
	dest_label.visible = false


func _unhandled_input(event):
	if !player_in_range or is_traveling:
		return
	
	# Cycle destinations with Tab
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		selected_dest_index = (selected_dest_index + 1) % destinations.size()
		# Skip self
		if destinations[selected_dest_index].id == station_id:
			selected_dest_index = (selected_dest_index + 1) % destinations.size()
		_update_dest_label()
	
	# Travel with E (interact)
	if event.is_action_pressed("interact") and player_in_range:
		_start_travel()


func _update_dest_label():
	var dest = destinations[selected_dest_index]
	dest_label.text = "[E] Travel to: " + dest.name + "\n[Tab] Next"
	dest_label.visible = true


func _start_travel():
	var dest = destinations[selected_dest_index]
	if dest.id == station_id:
		return  # Can't travel to current station
	
	is_traveling = true
	var player = get_tree().root.find_child("Player", true, false)
	if player == null:
		is_traveling = false
		return
	
	# Fade to black effect
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 100
	get_tree().root.add_child(overlay)
	
	var tween = create_tween()
	# Fade to black
	tween.tween_property(overlay, "color:a", 1.0, 0.5)
	# Teleport player
	tween.tween_callback(func():
		player.global_position = dest.pos
		player.velocity = Vector3.ZERO
		
		# Tell server
		if NetworkManager.socket_client:
			NetworkManager.socket_client.send_event("use_subway", {
				"from": station_id,
				"to": dest.id,
				"pos": {"x": dest.pos.x, "y": dest.pos.y, "z": dest.pos.z}
			})
	)
	# Fade back in
	tween.tween_property(overlay, "color:a", 0.0, 0.5)
	tween.tween_callback(func():
		overlay.queue_free()
		is_traveling = false
	)


func _on_body_entered(body):
	if body.name == "Player":
		player_in_range = true
		# Auto-select first non-self destination
		for i in destinations.size():
			if destinations[i].id != station_id:
				selected_dest_index = i
				break
		_update_dest_label()


func _on_body_exited(body):
	if body.name == "Player":
		player_in_range = false
		dest_label.visible = false
