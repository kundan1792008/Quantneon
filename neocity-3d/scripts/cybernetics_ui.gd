## Godot Cybernetics UI
## Allows players to purchase and install permanent stat boosts from a Ripperdoc.

extends Control

@onready var item_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/ItemList
@onready var close_button: Button = $Panel/VBoxContainer/Header/CloseButton
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel

var current_npc_id: String = ""

const AVAILABLE_IMPLANTS = [
	{ "id": "neural_accelerator", "name": "Neural Accelerator (Speed Boost)", "price": 2000 },
	{ "id": "titanium_bones", "name": "Titanium Bones (+50 Max HP)", "price": 3000 },
	{ "id": "mantis_blades", "name": "Mantis Blades (Melee DMG)", "price": 5000 }
]

func _ready() -> void:
	close_button.pressed.connect(hide)
	NetworkManager.socket.on("cybernetic_install_result", _on_install_result)
	_populate_list()

func open_clinic(npc_id: String) -> void:
	current_npc_id = npc_id
	status_label.text = "Select an implant to install."
	status_label.set("theme_override_colors/font_color", Color.WHITE)
	show()

func _populate_list() -> void:
	for child in item_list.get_children():
		child.queue_free()
	
	for impl in AVAILABLE_IMPLANTS:
		var btn = Button.new()
		btn.text = impl.name + " - Ð " + str(impl.price)
		btn.custom_minimum_size.y = 50
		item_list.add_child(btn)
		btn.pressed.connect(_on_install_pressed.bind(impl.id, impl.price))

func _on_install_pressed(implant_id: String, price: int) -> void:
	print("Attempting to install: ", implant_id)
	NetworkManager.socket.emit("install_cybernetic", {"npcId": current_npc_id, "implantId": implant_id})
	status_label.text = "Installing " + implant_id + "..."
	status_label.set("theme_override_colors/font_color", Color.YELLOW)

func _on_install_result(data: Dictionary) -> void:
	if data.get("success", false):
		status_label.text = "INSTALLATION SUCCESSFUL"
		status_label.set("theme_override_colors/font_color", Color.GREEN)
	else:
		status_label.text = "ERROR: " + data.get("reason", "Unknown")
		status_label.set("theme_override_colors/font_color", Color.RED)
