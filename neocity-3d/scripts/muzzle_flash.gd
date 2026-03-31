## Muzzle Flash Effect
## Triggers a brief light and mesh visibility toggle.

extends Node3D

@onready var light: OmniLight3D = $Light3D
@onready var timer: Timer = Timer.new()

func _ready():
	add_child(timer)
	timer.one_shot = true
	timer.timeout.connect(_on_timeout)
	visible = false

func flash():
	visible = true
	light.visible = true
	timer.start(0.05)

func _on_timeout():
	visible = false
	light.visible = false
