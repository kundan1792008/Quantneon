extends CharacterBody3D

@export var owner_id: String = ""
@export var follow_distance: float = 1.5
@export var follow_height: float = 2.0
@export var follow_speed: float = 8.0
@export var bob_speed: float = 3.0
@export var bob_amount: float = 0.2

var owner_node: Node3D = null
var time_alive: float = 0.0
var _target_pos: Vector3 = Vector3.ZERO
var _is_remote: bool = false

@onready var chat_bubble: Label3D = $ChatBubble
var chat_timer: SceneTreeTimer

func _ready():
    # Rotate top and bottom prisms to form an octahedron
    $MeshInstance3D.position.y = 0.2
    $MeshInstance3D2.position.y = -0.2

func setup(owner: Node3D, remote: bool = false):
    owner_node = owner
    _is_remote = remote

func _physics_process(delta: float):
    time_alive += delta
    
    if owner_node and is_instance_valid(owner_node):
        # Calculate target position behind and above the owner
        var back_dir = -owner_node.global_transform.basis.z.normalized()
        # If owner is not rotating properly or is remote, fallback to simple back displacement
        if back_dir.length_squared() < 0.1: back_dir = Vector3(0,0,1)
        
        var base_target = owner_node.global_position + (back_dir * follow_distance)
        base_target.y = owner_node.global_position.y + follow_height
        
        # Add hovering bob effect
        var bob = sin(time_alive * bob_speed) * bob_amount
        base_target.y += bob
        
        _target_pos = base_target
        
        # Smooth follow
        global_position = global_position.lerp(_target_pos, follow_speed * delta)
        
        # Look at owner
        var look_target = owner_node.global_position
        look_target.y = global_position.y # Don't pitch down
        if global_position.distance_squared_to(look_target) > 0.1:
            look_at(look_target, Vector3.UP)
            
        # Spin drone locally
        $MeshInstance3D.rotate_y(delta * 2.0)
        $MeshInstance3D2.rotate_y(-delta * 2.0)

func show_message(text: String, duration: float = 5.0):
    chat_bubble.text = text
    chat_bubble.visible = true
    
    if chat_timer != null:
        chat_timer.disconnect("timeout", _hide_message)
        
    chat_timer = get_tree().create_timer(duration)
    chat_timer.timeout.connect(_hide_message)

func _hide_message():
    chat_bubble.visible = false
