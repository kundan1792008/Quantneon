extends Node3D

var rings: Array = []
var current_ring_index: int = 0
var start_time: int = 0
var is_running: bool = false
var best_time: float = -1.0

func _ready() -> void:
	# Find all child rings and connect their signals
	for child in get_children():
		if child.name.begins_with("Ring") and child.has_signal("ring_collected"):
			rings.append(child)
			child.connect("ring_collected", _on_ring_collected)
			child.hide() # Hide all rings initially
			
			if child.has_node("CollisionShape3D"):
				child.get_node("CollisionShape3D").set_deferred("disabled", true)
			
	# Sort rings by index just in case the scene order is wrong
	rings.sort_custom(func(a, b): return a.ring_index < b.ring_index)
	
	print("[TimeTrial] Found %d rings." % rings.size())
	if rings.size() > 0:
		_setup_start_ring()

func _setup_start_ring() -> void:
	is_running = false
	current_ring_index = 0
	
	# Only show Ring 0
	for r in rings:
		r.hide()
		if r.has_node("RingMesh"):
			r.get_node("RingMesh").show()
		
		if r.has_node("CollisionShape3D"):
			r.get_node("CollisionShape3D").set_deferred("disabled", true)
			
	var start_ring = rings[0]
	start_ring.show()
	start_ring.set_deferred("monitoring", true)
	if start_ring.has_node("CollisionShape3D"):
		start_ring.get_node("CollisionShape3D").set_deferred("disabled", false)
		
	# Make start ring green
	if start_ring.has_node("RingMesh"):
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.GREEN
		mat.emission_enabled = true
		mat.emission = Color.GREEN
		start_ring.get_node("RingMesh").material_override = mat

func _start_trial() -> void:
	is_running = true
	start_time = Time.get_ticks_msec()
	print("[TimeTrial] Run started!")
	
	# Network broadcast
	if has_node("/root/NetworkManager"):
		var nm = get_node("/root/NetworkManager")
		if nm.socket_client:
			nm.socket_client.send_event("drone_chat", { "message": "Time Trial initiated. Tracking telemetry." })

func _on_ring_collected(index: int) -> void:
	if index != current_ring_index: return
	
	if current_ring_index == 0:
		_start_trial()
	
	# Move to next ring
	current_ring_index += 1
	
	if current_ring_index < rings.size():
		var next_ring = rings[current_ring_index]
		next_ring.show()
		next_ring.set_deferred("monitoring", true)
		if next_ring.has_node("CollisionShape3D"):
			next_ring.get_node("CollisionShape3D").set_deferred("disabled", false)
			
		# Make it orange to indicate it's the active one
		if next_ring.has_node("RingMesh"):
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.5, 0.0) # Orange
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.5, 0.0)
			next_ring.get_node("RingMesh").material_override = mat
	else:
		_finish_trial()

func _finish_trial() -> void:
	var end_time = Time.get_ticks_msec()
	var elapsed_secs: float = (end_time - start_time) / 1000.0
	is_running = false
	
	var pb_text = ""
	if best_time < 0 or elapsed_secs < best_time:
		best_time = elapsed_secs
		pb_text = " (NEW PERSONAL BEST!)"
		
	var final_msg = "Course complete! Time: %.2fs%s" % [elapsed_secs, pb_text]
	print("[TimeTrial] ", final_msg)
	
	# Drone Announcement
	if len(get_tree().get_nodes_in_group("drone_companion")) > 0:
		var drone = get_tree().get_nodes_in_group("drone_companion")[0]
		if drone.has_method("show_message"):
			drone.show_message(final_msg, 5.0)
	
	# Broadcast to Network
	if has_node("/root/NetworkManager"):
		var nm = get_node("/root/NetworkManager")
		if nm.socket_client:
			nm.socket_client.send_event("drone_chat", { "message": final_msg })
			
	# Reset after 5 seconds
	await get_tree().create_timer(5.0).timeout
	_setup_start_ring()
