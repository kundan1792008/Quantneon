## Weapon Pickup
## Allows players to gain new weapons or refill ammo.

extends Area3D

@export var weapon_type: String = "laser_pistol"
@export var ammo_amount: int = 50

func _ready():
	body_entered.connect(_on_body_entered)
	# Simple floating effect
	var tween = create_tween().set_loops()
	tween.tween_property($Mesh, "position:y", 0.5, 1.0).as_relative()
	tween.tween_property($Mesh, "position:y", -0.5, 1.0).as_relative()
	tween.parallel().tween_property($Mesh, "rotation:y", PI * 2, 2.0).as_relative()

func _on_body_entered(body):
	if body.name == "Player":
		print("[Pickup] Gained: ", weapon_type)
		if has_node("/root/WeaponSystem"):
			var ws = get_node("/root/WeaponSystem")
			ws.current_weapon = weapon_type
			ws.ammo_current = min(ws.ammo_max, ws.ammo_current + ammo_amount)
			# Notify HUD (Signal handles this)
		queue_free()
