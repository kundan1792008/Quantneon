## Vending Machine — Dispenses consumables for bits
extends StaticBody3D

@onready var interact_area: Area3D = $InteractArea
@onready var price_label: Label3D = $PriceLabel
@onready var can_mesh: MeshInstance3D = $CanMesh

var is_processing: bool = false
@export var item_name: String = "NeonCola"
@export var item_cost: int = 10


func _ready():
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)
	price_label.visible = false
	can_mesh.visible = false

	# Listen for server purchase response
	if NetworkManager.socket_client:
		NetworkManager.socket_client.on("purchase_result", _on_purchase_result)


func _unhandled_input(event):
	if event.is_action_pressed("interact") and price_label.visible and !is_processing:
		_attempt_purchase()


func _attempt_purchase():
	is_processing = true
	price_label.text = "Processing..."
	
	if NetworkManager.socket_client:
		NetworkManager.socket_client.send_event("buy_consumable", {
			"machineId": name,
			"item": item_name,
			"cost": item_cost
		})


func _on_purchase_result(data: Dictionary):
	# If we sent a request but are far away, just exit early gracefully
	if !is_processing:
		return

	if data.get("success", false) and data.get("machineId") == name:
		_dispense_item()
	else:
		_show_error(data.get("reason", "Denied"))


func _dispense_item():
	price_label.text = "Dispensing..."
	
	# Start can inside machine
	can_mesh.position = Vector3(0, 1.0, 0.4)
	can_mesh.visible = true
	
	# Drop animation to slot
	var tween = create_tween()
	tween.tween_property(can_mesh, "position:y", 0.45, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_finish_dispense)


func _finish_dispense():
	can_mesh.visible = false
	price_label.text = "Enjoy!"
	await get_tree().create_timer(1.5).timeout
	
	is_processing = false
	if interact_area.get_overlapping_bodies().has(get_tree().root.find_child("Player", true, false)):
		price_label.text = "%s: %d Bits\n[E] Buy" % [item_name, item_cost]
	else:
		price_label.visible = false


func _show_error(msg: String):
	price_label.text = "ERR: " + msg
	await get_tree().create_timer(2.0).timeout
	
	is_processing = false
	if interact_area.get_overlapping_bodies().has(get_tree().root.find_child("Player", true, false)):
		price_label.text = "%s: %d Bits\n[E] Buy" % [item_name, item_cost]
	else:
		price_label.visible = false


func _on_body_entered(body):
	if body.name == "Player" and !is_processing:
		price_label.text = "%s: %d Bits\n[E] Buy" % [item_name, item_cost]
		price_label.visible = true


func _on_body_exited(body):
	if body.name == "Player":
		if !is_processing:
			price_label.visible = false
