extends CanvasLayer

@onready var container: Control = $Control
@onready var label: Label = $Control/Label
@onready var bg: ColorRect = $Control/ColorRect

func _ready() -> void:
	# Start off-screen (above the top)
	container.position.y = -100

func show_announcement(text: String, duration: float = 3.0) -> void:
	label.text = text
	
	# Reset position just in case
	container.position.y = -100
	
	var tween = create_tween()
	# Slide in
	tween.tween_property(container, "position:y", 20, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Wait
	tween.tween_interval(duration)
	
	# Slide out
	tween.tween_property(container, "position:y", -100, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
