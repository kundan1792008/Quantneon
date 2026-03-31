extends CanvasLayer

# real_estate_ui.gd

@onready var prop_list = find_child("PropList")
@onready var close_button = find_child("CloseButton")

func _ready():
	close_button.pressed.connect(hide_ui)
	var pm = get_node("/root/PropertyManager")
	pm.connect("property_list_updated", _refresh_list)
	_refresh_list()
	hide()

func show_ui():
	show()
	_refresh_list()

func hide_ui():
	hide()

func _refresh_list():
	# Clear existing
	for child in prop_list.get_children():
		child.queue_free()
	
	var pm = get_node("/root/PropertyManager")
	for prop_id in pm.properties:
		var prop = pm.properties[prop_id]
		if not prop.isForSale: continue
		
		var h_box = HBoxContainer.new()
		
		var name_label = Label.new()
		name_label.text = prop.name + " (" + str(prop.price) + " NC)"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h_box.add_child(name_label)
		
		var buy_btn = Button.new()
		buy_btn.text = "BUY"
		buy_btn.pressed.connect(func(): pm.purchase_property(prop.id))
		h_box.add_child(buy_btn)
		
		prop_list.add_child(h_box)
