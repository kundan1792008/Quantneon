extends CanvasLayer

@onready var main_panel = $MainPanel
@onready var item_list = $MainPanel/MarginContainer/HBoxContainer/BackpackSection/ScrollContainer/ItemList
@onready var lbl_primary = $MainPanel/MarginContainer/HBoxContainer/EquipSection/PrimarySlot/Label
@onready var lbl_secondary = $MainPanel/MarginContainer/HBoxContainer/EquipSection/SecondarySlot/Label
@onready var lbl_melee = $MainPanel/MarginContainer/HBoxContainer/EquipSection/MeleeSlot/Label

var is_open = false
var inventory_data = {}

func _ready():
	visible = false

func toggle():
	is_open = !is_open
	visible = is_open
	
	if is_open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event.is_action_pressed("inventory"):
		toggle()
	# Hotkeys for equipping if inventory is open
	if is_open:
		if event.is_action_pressed("ui_cancel"):
			toggle()

func sync_inventory(data: Dictionary):
	inventory_data = data
	_refresh_ui()

func _refresh_ui():
	# Update Equipped Labels
	var equipped = inventory_data.get("equipped", {"primary": null, "secondary": null, "melee": null})
	lbl_primary.text = "[1] Primary: " + (equipped.primary.to_upper() if equipped.primary else "NONE")
	lbl_secondary.text = "[2] Secondary: " + (equipped.secondary.to_upper() if equipped.secondary else "NONE")
	lbl_melee.text = "[3] Melee: " + (equipped.melee.to_upper() if equipped.melee else "NONE")

	# Clear previous items
	for child in item_list.get_children():
		child.queue_free()

	# Add Backpack Items
	var items = inventory_data.get("items", {})
	for item_id in items.keys():
		var qty = items[item_id]
		if qty > 0:
			var btn = Button.new()
			btn.text = "%s (x%d)" % [item_id.to_upper(), qty]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(func(): _on_item_clicked(item_id))
			item_list.add_child(btn)

func _on_item_clicked(item_id: String):
	# Very basic logic: decide slot based on item string
	var slot = "primary"
	if item_id == "cyber_pistol":
		slot = "secondary"
	elif item_id == "plasma_rifle":
		slot = "primary"
	elif item_id == "neon_blade":
		slot = "melee"
	elif item_id == "medkit":
		print("[Inventory] Consumed Medkit (Not yet sent to server)")
		return
		
	var nm = get_node_or_null("/root/NetworkManager")
	if nm:
		nm.socket_client.send_event("inventory_equip", {"slot": slot, "itemId": item_id})
