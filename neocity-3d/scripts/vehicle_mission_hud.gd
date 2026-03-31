extends Control

@onready var title_label = $Panel/MissionTitle
@onready var dest_label = $Panel/DestinationLabel
@onready var time_label = $Panel/TimeLabel
@onready var health_label = $Panel/HealthLabel
@onready var progress_bar = $Panel/ProgressBar

var is_active := false
var start_time := 0.0
var max_time := 120.0
var current_health := 100.0

func _ready() -> void:
	visible = false

func start_mission(mission_data: Dictionary) -> void:
	is_active = true
	visible = true
	
	if mission_data.has("type"):
		title_label.text = "CYBER TAXI" if mission_data.type == "taxi" else "DELIVERY"
		
	if mission_data.has("targetZoneId"):
		dest_label.text = "Destination: " + str(mission_data.targetZoneId).capitalize()
		
	if mission_data.has("maxTimerTicks"):
		# Backend sends ticks at 10Hz. 1200 ticks = 120 seconds.
		max_time = float(mission_data.maxTimerTicks) / 10.0
		
	if mission_data.has("timerTicks"):
		start_time = float(mission_data.timerTicks) / 10.0
		
	if mission_data.has("health"):
		current_health = float(mission_data.health)
		
	_update_display(start_time, current_health)

func update_mission_state(mission_data: Dictionary) -> void:
	if not is_active: return
	
	if mission_data.has("timerTicks"):
		var time_left = float(mission_data.timerTicks) / 10.0
		
		# If mission ended
		if time_left <= 0:
			end_mission()
			return
			
		if mission_data.has("health"):
			current_health = float(mission_data.health)
			
		_update_display(time_left, current_health)

func end_mission() -> void:
	is_active = false
	visible = false

func _update_display(time_left: float, health: float) -> void:
	time_label.text = "Time: " + str(int(time_left)) + "s"
	health_label.text = "Health: " + str(int(health)) + "%"
	progress_bar.value = health
	
	# Color warnings
	if time_left < 30.0:
		time_label.add_theme_color_override("font_color", Color.RED)
	else:
		time_label.add_theme_color_override("font_color", Color(1, 0.8, 0)) # Yellow
		
	if health < 40.0:
		health_label.add_theme_color_override("font_color", Color.RED)
		progress_bar.modulate = Color.RED
	elif health < 75.0:
		health_label.add_theme_color_override("font_color", Color.ORANGE)
		progress_bar.modulate = Color.ORANGE
	else:
		health_label.add_theme_color_override("font_color", Color(0.2, 1, 0.2)) # Green
		progress_bar.modulate = Color.GREEN
