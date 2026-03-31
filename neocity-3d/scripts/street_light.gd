## StreetLight — Neon lamp post with warm/cool alternating glow
extends Node3D

@onready var light_source: OmniLight3D = $OmniLight3D
@onready var glow_bulb: CSGBox3D = $LightModel/GlowBulb

@export var light_color: Color = Color(1, 0.6, 0.2, 1)  # Warm neon
@export var flicker: bool = false
@export var flicker_speed: float = 8.0

var base_energy: float = 2.0

func _ready():
	if light_source:
		light_source.light_color = light_color
		light_source.light_energy = base_energy
		light_source.omni_range = 12.0
		light_source.shadow_enabled = false  # Performance
	
	if glow_bulb:
		var mat = glow_bulb.material as StandardMaterial3D
		if mat:
			mat.emission = light_color
			mat.albedo_color = light_color

func _process(delta):
	if flicker and light_source:
		var flick = base_energy + sin(Time.get_ticks_msec() * 0.001 * flicker_speed) * 0.5
		flick += randf_range(-0.1, 0.1)
		light_source.light_energy = flick
