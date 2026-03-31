## Godot Bounty Board UI
## Displays active hits on players and NPCs.

extends Control

@onready var bounty_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/BountyList
@onready var close_button: Button = $Panel/VBoxContainer/Header/CloseButton

const BOUNTY_ITEM = preload("res://ui/bounty_item.tscn")

func _ready() -> void:
	close_button.pressed.connect(hide)
	NetworkManager.socket.on("bounty_board_data", _on_bounty_data)
	
	# Request data when shown
	visibility_changed.connect(_on_visibility_changed)

func _on_visibility_changed() -> void:
	if visible:
		NetworkManager.socket.emit("get_bounty_board")

func _on_bounty_data(data: Array) -> void:
	# Clear existing
	for child in bounty_list.get_children():
		child.queue_free()
	
	for entry in data:
		var item = BOUNTY_ITEM.instantiate()
		bounty_list.add_child(item)
		item.set_data(entry)
