## War Map UI for Neo City
## Displays real-time faction control of city zones.

extends Control

@onready var zones_container: GridContainer = $ZonesContainer
@onready var zone_item_scene = preload("res://ui/zone_control_item.tscn") # We'll create this or use simple labels

var zone_items: Dictionary = {} # {zoneId: Node}

func update_zone(data: Dictionary):
	var zone_id = data.zoneId
	if not zone_items.has(zone_id):
		_create_zone_item(zone_id, data.name)
	
	var item = zone_items[zone_id]
	item.update_status(data.faction, data.influence)

func _create_zone_item(id: String, display_name: String):
	var label = Label.new()
	label.text = display_name + ": Neutral"
	zones_container.add_child(label)
	
	# Add custom script/method to the label for ease
	label.set_script(load("res://scripts/zone_label_helper.gd"))
	zone_items[id] = label

func trigger_alarm(_vault_id: String):
	print("[UI] Alarm flashing for vault: ", _vault_id)
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.RED, 0.5)
	tween.tween_property(self, "modulate", Color.WHITE, 0.5)
	tween.set_loops(5)

# Inner script for the label or separate file
# For now, let's assume we use a simple script to handle color
