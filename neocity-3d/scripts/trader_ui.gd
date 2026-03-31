## Godot Trader UI
## Displays items for sale based on player reputation.

extends Control

@onready var item_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/ItemList
@onready var current_coins: Label = $Panel/VBoxContainer/Header/Coins
@onready var close_button: Button = $Panel/VBoxContainer/Header/CloseButton

var current_npc_id: String = ""

func _ready() -> void:
	close_button.pressed.connect(hide)
	if NetworkManager.socket:
		NetworkManager.socket.on("trader_inventory_data", _on_inventory_data)
		NetworkManager.socket.on("purchase_result", _on_purchase_result)

func open_trader(npc_id: String) -> void:
	current_npc_id = npc_id
	show()
	NetworkManager.socket.emit("get_trader_inventory", {"npcId": npc_id})

func _on_inventory_data(data: Dictionary) -> void:
	if data.npcId != current_npc_id: return
	
	# Clear existing
	for child in item_list.get_children():
		child.queue_free()
	
	for entry in data.items:
		var btn = Button.new()
		btn.text = entry.name + " - Ð " + str(entry.price)
		btn.custom_minimum_size.y = 50
		item_list.add_child(btn)
		btn.pressed.connect(_on_buy_pressed.bind(entry.id, entry.price))

func _on_buy_pressed(item_id: String, price: int) -> void:
	# In a full impl, we'd emit a buy event
	print("Attempting to buy: ", item_id, " for ", price)
	NetworkManager.socket.emit("purchase_item", {"npcId": current_npc_id, "itemId": item_id})

func _on_purchase_result(data: Dictionary) -> void:
	if data.success:
		print("Purchase successful!")
		# Optionally play a ka-ching sound or show a checkmark
		hide()
	else:
		print("Purchase failed: ", data.message)
		# Optionally show an error label
