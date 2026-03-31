## Combat HUD Controller
## Updates the UI based on weapon state.

extends CanvasLayer

@onready var ammo_label: Label = $WeaponPanel/VBox/AmmoContainer/AmmoCount
@onready var weapon_label: Label = $WeaponPanel/VBox/WeaponName

func _ready():
	# Connect to WeaponSystem if it's singleton
	if has_node("/root/WeaponSystem"):
		get_node("/root/WeaponSystem").weapon_fired.connect(_on_weapon_fired)
		get_node("/root/WeaponSystem").weapon_reloaded.connect(_on_weapon_reloaded)

func _on_weapon_fired(_name, ammo):
	ammo_label.text = str(ammo)
	# Subtle shake or flash effect
	var tween = create_tween()
	ammo_label.modulate = Color(1, 0, 0)
	tween.tween_property(ammo_label, "modulate", Color.WHITE, 0.1)

func _on_weapon_reloaded(_name):
	if has_node("/root/WeaponSystem"):
		var ws = get_node("/root/WeaponSystem")
		ammo_label.text = str(ws.ammo_current)
	ammo_label.modulate = Color(0, 1, 0)
	var tween = create_tween()
	tween.tween_property(ammo_label, "modulate", Color.WHITE, 0.5)
