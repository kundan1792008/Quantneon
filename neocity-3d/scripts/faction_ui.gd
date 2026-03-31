extends Control

@onready var nexus_btn = $Panel/VBoxContainer/btn_nexus_order
@onready var shadow_btn = $Panel/VBoxContainer/btn_shadow_syndicate
@onready var free_coders_btn = $Panel/VBoxContainer/btn_free_coders
@onready var quantum_btn = $Panel/VBoxContainer/btn_quantum_collective

func _ready():
	# Connect buttons to the faction selection handler
	nexus_btn.pressed.connect(_on_faction_selected.bind("NEXUS_ORDER"))
	shadow_btn.pressed.connect(_on_faction_selected.bind("SHADOW_SYNDICATE"))
	free_coders_btn.pressed.connect(_on_faction_selected.bind("FREE_CODERS"))
	quantum_btn.pressed.connect(_on_faction_selected.bind("QUANTUM_COLLECTIVE"))

func _on_faction_selected(faction_id: String):
	print("Joining Faction: ", faction_id)
	
	if NetworkManager.socket_client != null:
		# Send exactly what world.socket.ts expects: {"faction": faction_id}
		NetworkManager.socket_client.send_event("join_faction", {"faction": faction_id})
	else:
		push_warning("NetworkManager unavailable! Cannot join faction.")

	# Cleanup UI
	visible = false
	queue_free()
