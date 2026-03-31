## Shop UI Controller
## Manages the display and user interaction for the Neo City Shop.

extends CanvasLayer

@onready var item_list: GridContainer = $ShopOverlay/MainPanel/VBox/ScrollArea/Margin/ItemList
@onready var balance_label: Label = $ShopOverlay/MainPanel/VBox/Footer/BalanceLabel
@onready var status_label: Label = $ShopOverlay/MainPanel/VBox/Footer/StatusLabel
@onready var close_button: Button = $ShopOverlay/MainPanel/VBox/Header/CloseButton
@onready var overlay: Control = $ShopOverlay

func _ready():
	overlay.visible = false
	close_button.pressed.connect(close_shop)

func display_items(items: Array):
	# Clear existing
	for child in item_list.get_children():
		child.queue_free()
	
	for item in items:
		var card = _create_item_card(item)
		item_list.add_child(card)
	
	overlay.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _create_item_card(item: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(250, 100)
	
	var vbox = VBoxContainer.new()
	card.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = item.name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)
	
	var price_lbl = Label.new()
	price_lbl.text = str(item.price) + " NC"
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(price_lbl)
	
	var buy_btn = Button.new()
	buy_btn.text = "BUY"
	buy_btn.pressed.connect(func(): _on_buy_pressed(item.id))
	vbox.add_child(buy_btn)
	
	return card

func _on_buy_pressed(item_id: String):
	status_label.text = "Processing..."
	if has_node("/root/ShopSystem"):
		get_node("/root/ShopSystem").buy_item(item_id)

func update_balance(balance: int):
	balance_label.text = "Balance: " + str(balance) + " NC"
	status_label.text = "Purchase successful!"

func show_error(msg: String):
	status_label.text = "Error: " + msg

func close_shop():
	overlay.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
func open_shop():
	overlay.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if has_node("/root/ShopSystem"):
		get_node("/root/ShopSystem").open_shop()
