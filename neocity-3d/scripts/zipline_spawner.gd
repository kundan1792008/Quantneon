## ZiplineSpawner — Instantiates zipline cables between rooftop anchor points
extends Node3D

const ZIPLINE_SCENE = preload("res://scenes/zipline.tscn")

# Each entry: [start_anchor_name, end_anchor_name]
@export var zipline_routes: Array[PackedStringArray] = []

var zipline_instances: Array[Node3D] = []


func _ready():
	# Default routes based on anchor nodes placed in the scene
	var routes := [
		["ZipAnchor_T2_T3", "ZipAnchor_T3_T2"],   # Tower 2 ↔ Tower 3
		["ZipAnchor_T1_T4", "ZipAnchor_T4_T1"],   # Tower 1 ↔ Tower 4
	]

	# Wait one frame so all sibling nodes are ready
	await get_tree().process_frame

	for route in routes:
		var start_node = get_parent().get_node_or_null(route[0])
		var end_node = get_parent().get_node_or_null(route[1])

		if start_node == null or end_node == null:
			push_warning("ZiplineSpawner: Missing anchor %s or %s — skipping" % [route[0], route[1]])
			continue

		var zipline = ZIPLINE_SCENE.instantiate()
		get_parent().add_child(zipline)
		zipline.setup(start_node.global_position, end_node.global_position)
		zipline_instances.append(zipline)

	print("[ZiplineSpawner] Spawned %d ziplines" % zipline_instances.size())
