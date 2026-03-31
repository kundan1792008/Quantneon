extends Node3D

@export var start_pos: Vector3 = Vector3.ZERO
@export var target_pos: Vector3 = Vector3.ZERO
@export var speed: float = 60.0
@export var lifetime: float = 1.0

var direction: Vector3

func _ready():
    global_position = start_pos
    direction = (target_pos - start_pos).normalized()
    
    # Orient the tracer to face the target
    if direction.length_squared() > 0.001:
        look_at(target_pos, Vector3.UP)
        
    # Failsafe destruction
    get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _physics_process(delta: float):
    # Move projectile
    global_position += direction * speed * delta
    
    # Check if we passed the target
    var dist_to_start = global_position.distance_squared_to(start_pos)
    var dist_start_to_target = start_pos.distance_squared_to(target_pos)
    
    if dist_to_start >= dist_start_to_target:
        # We hit the target location
        _on_hit()

func _on_hit():
    # Could spawn a hit spark particle here
    queue_free()

func setup(p_start: Vector3, p_target: Vector3):
    start_pos = p_start
    target_pos = p_target
