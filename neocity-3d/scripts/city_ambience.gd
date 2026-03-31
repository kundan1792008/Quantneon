## CityAmbience — Dynamic ambient sound system for Neo City
## Plays environmental audio cues based on location and time
extends Node

var ambient_timer: float = 0.0
var ambient_interval: float = 15.0  # seconds between ambient events

# Ambient event types
var ambient_events: Array = [
	"distant_siren",
	"neon_buzz",
	"crowd_murmur",
	"hover_traffic",
	"subway_rumble",
	"rain_on_metal",
]

var current_zone: String = "downtown"

func _ready():
	print("[CityAmbience] Ambient system online.")

func _process(delta):
	ambient_timer += delta
	if ambient_timer >= ambient_interval:
		ambient_timer = 0.0
		_trigger_ambient_event()

func _trigger_ambient_event():
	var event = ambient_events[randi() % ambient_events.size()]
	# In a full implementation, this would play AudioStreamPlayer nodes
	# For now, we log and can hook into visual effects
	match event:
		"distant_siren":
			_flash_distant_light(Color(1, 0, 0, 1), Color(0, 0, 1, 1))
		"neon_buzz":
			pass  # Billboard flicker handled by neon_billboard.gd
		"hover_traffic":
			pass  # traffic handled by vehicle system
		"subway_rumble":
			_screen_shake(0.3, 0.5)
		_:
			pass

func _flash_distant_light(color1: Color, color2: Color):
	# Create a distant flashing light to simulate police/emergency
	var light = OmniLight3D.new()
	light.light_color = color1
	light.light_energy = 3.0
	light.omni_range = 30.0
	light.position = Vector3(
		randf_range(-80, 80),
		15,
		randf_range(-80, 80)
	)
	get_tree().root.add_child(light)
	
	var tween = get_tree().create_tween().set_loops(4)
	tween.tween_property(light, "light_color", color2, 0.3)
	tween.tween_property(light, "light_color", color1, 0.3)
	
	# Cleanup
	get_tree().create_timer(3.0).timeout.connect(light.queue_free)

func _screen_shake(intensity: float, duration: float):
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	
	var original_pos = cam.position
	var tween = get_tree().create_tween()
	
	for i in range(int(duration * 10)):
		var offset = Vector3(
			randf_range(-intensity, intensity),
			randf_range(-intensity * 0.5, intensity * 0.5),
			0
		)
		tween.tween_property(cam, "position", original_pos + offset, 0.05)
	
	tween.tween_property(cam, "position", original_pos, 0.1)
