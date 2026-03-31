## NeonBillboard — Cycles through holographic ad messages with neon glow animations
extends Node3D

@onready var ad_text: Label3D = $AdText
@onready var sub_text: Label3D = $SubText
@onready var glow_border: CSGBox3D = $GlowBorder

@export var cycle_interval: float = 5.0
@export var billboard_id: String = "default"

var ad_messages: Array = [
	{"title": "QUANTNEON", "sub": "The Future is AI", "color": Color(0, 1, 1, 1)},
	{"title": "NEO CITY", "sub": "Home for AI Beings", "color": Color(1, 0, 1, 1)},
	{"title": "NEON COLA", "sub": "Taste the Electric Dream", "color": Color(1, 0.3, 0, 1)},
	{"title": "CYBER IMPLANTS", "sub": "Upgrade Your Reality", "color": Color(0, 1, 0.5, 1)},
	{"title": "SHADOW NET", "sub": "Privacy is Power", "color": Color(0.8, 0, 1, 1)},
	{"title": "NEXUS BANK", "sub": "Your NeonCoins. Secured.", "color": Color(1, 0.8, 0, 1)},
]

var current_ad_index: int = 0
var timer: float = 0.0

func _ready():
	current_ad_index = randi() % ad_messages.size()
	_show_ad(current_ad_index)

func _process(delta):
	timer += delta
	if timer >= cycle_interval:
		timer = 0.0
		current_ad_index = (current_ad_index + 1) % ad_messages.size()
		_transition_ad(current_ad_index)

	# Subtle glow pulse animation
	var pulse = 2.5 + sin(Time.get_ticks_msec() * 0.003) * 0.5
	var mat = glow_border.material as StandardMaterial3D
	if mat:
		mat.emission_energy_multiplier = pulse

func _show_ad(index: int):
	var ad = ad_messages[index]
	ad_text.text = ad.title
	sub_text.text = ad.sub
	ad_text.modulate = ad.color
	# Glow border matches ad color
	var mat = glow_border.material as StandardMaterial3D
	if mat:
		mat.emission = ad.color
		mat.albedo_color = ad.color

func _transition_ad(index: int):
	# Fade out effect
	var tween = create_tween()
	tween.tween_property(ad_text, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_show_ad.bind(index))
	tween.tween_property(ad_text, "modulate:a", 1.0, 0.3)

func set_custom_ads(ads: Array):
	ad_messages = ads
	current_ad_index = 0
	_show_ad(0)
