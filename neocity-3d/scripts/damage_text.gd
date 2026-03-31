extends Node3D

@onready var label: Label3D = $Label3D

@export var text: String = "-15"
@export var float_speed: float = 3.0
@export var lifetime: float = 1.0
@export var is_heal: bool = false
@export var is_crit: bool = false

var time_alive: float = 0.0

func _ready():
    label.text = text
    if is_heal:
        label.modulate = Color(0.2, 1.0, 0.2, 1.0) # Green
    elif is_crit:
        label.modulate = Color(1.0, 0.8, 0.0, 1.0) # Gold
        label.font_size = 96
        
    # Add some random horizontal drift
    var drift_x = (randf() - 0.5) * 2.0
    var drift_z = (randf() - 0.5) * 2.0
    
    var tween = create_tween().set_parallel(true)
    tween.tween_property(self, "position:y", position.y + float_speed, lifetime).set_ease(Tween.EASE_OUT)
    tween.tween_property(self, "position:x", position.x + drift_x, lifetime)
    tween.tween_property(self, "position:z", position.z + drift_z, lifetime)
    
    tween.tween_property(label, "modulate:a", 0.0, lifetime * 0.5).set_delay(lifetime * 0.5)

    get_tree().create_timer(lifetime).timeout.connect(queue_free)

func setup(amount: int, is_critical: bool = false, is_healing: bool = false):
    is_crit = is_critical
    is_heal = is_healing
    if amount < 0 or is_heal:
        text = "+%d" % abs(amount)
        is_heal = true
    else:
        text = "-%d" % amount
