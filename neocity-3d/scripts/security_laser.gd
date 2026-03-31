extends Node3D

@export var vault_id: String = ""
@export var sweep_speed: float = 2.0
@export var sweep_angle: float = 45.0 # Degrees

@onready var pivot: Node3D = $Pivot
@onready var area: Area3D = $Pivot/Area3D

var time_passed: float = 0.0
var active: bool = true

func _ready() -> void:
    # Randomize start offset so multiple lasers aren't perfectly synced
    time_passed = randf() * PI 
    
    # Listen for player intersection
    area.body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
    if not active: return
    
    time_passed += delta * sweep_speed
    # Sine wave ping-pong rotation
    pivot.rotation_degrees.y = sin(time_passed) * sweep_angle

func _on_body_entered(body: Node3D) -> void:
    if not active: return
    
    if body.name == "Player":
        print("[Security] INTRUDER DETECTED at Vault ", vault_id)
        active = false # Prevent spamming
        
        # Flash the laser intensely
        var mat: StandardMaterial3D = $Pivot/Area3D/MeshInstance3D.get_active_material(0)
        if mat:
            mat.emission_energy_multiplier = 20.0
        
        # Tell the server we tripped the alarm
        if NetworkManager.socket_client:
            NetworkManager.socket_client.send_event("trigger_alarm", {"vaultId": vault_id})
        
        # Wait a bit, then disappear or reset
        await get_tree().create_timer(3.0).timeout
        queue_free()

func set_vault(id: String) -> void:
    vault_id = id
