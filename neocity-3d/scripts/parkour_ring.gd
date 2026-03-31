extends Area3D

@export var ring_index: int = -1

signal ring_collected(index)

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.name == "Player":
		emit_signal("ring_collected", ring_index)
		# Hide visually
		if has_node("RingMesh"):
			get_node("RingMesh").hide()
		# Disable collision
		set_deferred("monitoring", false)
		if has_node("CollisionShape3D"):
			get_node("CollisionShape3D").set_deferred("disabled", true)
		
		# Optional: Play sound or particle burst here
		# print("Ring %d collected!" % ring_index)
