extends Node

# property_manager.gd - Manages owned properties and browsing

var properties = {} # id -> PropertyState
var owned_property_ids = []

signal property_list_updated
signal property_purchased(success, reason)
signal stash_updated(property_id, stash)

func _ready():
	var network = get_node("/root/NetworkManager")
	network.connect("world_entered", _on_world_entered)
	
	# Connect to specific property update events
	var socket = get_node("/root/SocketIOClient")
	socket.on_event("property_updated", _on_property_updated)
	socket.on_event("purchase_result", _on_purchase_result)
	socket.on_event("stash_updated", _on_stash_updated)

func _on_world_entered(data):
	if data.has("properties"):
		for p in data.properties:
			properties[p.id] = p
	
	if data.has("player") and data.player.has("ownedPropertyIds"):
		owned_property_ids = data.player.ownedPropertyIds
	
	emit_signal("property_list_updated")

func _on_property_updated(prop):
	properties[prop.id] = prop
	emit_signal("property_list_updated")

func _on_purchase_result(result):
	if result.success:
		# The update will come via property_updated usually, 
		# but we can proactively update owned_property_ids if we want.
		pass
	emit_signal("property_purchased", result.success, result.get("reason", ""))

func _on_stash_updated(data):
	if properties.has(data.propertyId):
		properties[data.propertyId].stash = data.stash
	emit_signal("stash_updated", data.propertyId, data.stash)

func purchase_property(property_id):
	var socket = get_node("/root/SocketIOClient")
	socket.emit_event("purchase_property", {"propertyId": property_id})

func update_stash(property_id, stash):
	var socket = get_node("/root/SocketIOClient")
	socket.emit_event("update_property_stash", {"propertyId": property_id, "stash": stash})

func is_owner(property_id):
	return owned_property_ids.has(property_id)

func get_property(property_id):
	return properties.get(property_id)
