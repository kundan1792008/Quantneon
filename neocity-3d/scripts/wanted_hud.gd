## Wanted Level HUD Controller
## Displays stars (1-5) and "WANTED" status for the player.

extends CanvasLayer

@onready var stars_container: HBoxContainer = $MainContainer/StarsContainer
@onready var status_label: Label = $MainContainer/StatusLabel

var current_stars: int = 0
var flash_timer: float = 0.0

func _process(delta):
	if current_stars > 0:
		flash_timer += delta * 5.0
		var alpha = 0.5 + 0.5 * sin(flash_timer)
		status_label.modulate.a = alpha
		status_label.visible = true
	else:
		status_label.visible = false

func update_wanted_level(level: float):
	var stars = floor(level)
	current_stars = int(stars)
	
	var i = 1
	for star in stars_container.get_children():
		if i <= stars:
			star.theme_override_colors.font_color = Color(1, 0.9, 0, 1) # Golden Yellow
			# Pulsing effect for active stars
			var tween = create_tween()
			tween.tween_property(star, "scale", Vector3(1.2, 1.2, 1.2), 0.1)
			tween.tween_property(star, "scale", Vector3.ONE, 0.1)
		else:
			star.theme_override_colors.font_color = Color(0.2, 0.2, 0.2, 0.5) # Dark/Empty
		i += 1
