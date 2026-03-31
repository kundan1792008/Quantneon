## Objective Marker Controller
## Shows a 3D beam at the target location of the active quest.

extends Node3D

var active_marker = null
var marker_scene = preload("res://scenes/objective_marker.tscn")

func _process(_delta):
	var mission_hud = get_node_or_null("/root/MissionHUD")
	if not mission_hud or not mission_hud.current_quest_data:
		hide_marker()
		return
	
	var q = mission_hud.current_quest_data
	if q.has("targetPos") and q.targetPos != null:
		# Convert backend (x,y) to Godot (x,z)
		# Backend uses 10x scale for precision, but world units are 1:1 here if we divided by 10
		# Wait, earlier we were multiplying local pos by 10 for server. 
		# So server units match world units.
		var pos = Vector3(q.targetPos.x, 0, q.targetPos.y)
		update_marker(pos)
	else:
		hide_marker()

func update_marker(target_pos: Vector3):
	if active_marker == null:
		active_marker = marker_scene.instantiate()
		get_tree().root.add_child(active_marker)
	
	active_marker.global_position = target_pos

func hide_marker():
	if active_marker:
		active_marker.queue_free()
		active_marker = null
