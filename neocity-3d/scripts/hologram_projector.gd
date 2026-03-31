## HologramProjector — Glowing rotating glitchy hologram for city polish
extends Node3D

@export var holo_color: Color = Color(0, 1, 1, 1) # Cyan default
@onready var holo_mesh: MeshInstance3D = $HoloMesh

var base_y: float = 2.5
var time_offset: float = 0.0

func _ready():
	# Randomize bobbing start time so they aren't synced perfectly
	time_offset = randf() * 1000.0
	
	# Apply unique color to this instance's material
	if holo_mesh:
		var mat = holo_mesh.get_surface_override_material(0)
		if mat == null:
			mat = holo_mesh.mesh.surface_get_material(0)
			
		if mat is StandardMaterial3D:
			# Duplicate so we don't change ALL holograms globally
			mat = mat.duplicate()
			mat.albedo_color = Color(holo_color.r, holo_color.g, holo_color.b, 0.6)
			mat.emission = holo_color
			holo_mesh.set_surface_override_material(0, mat)
		
		# Record starting Y position relative to parent
		base_y = holo_mesh.position.y


func _process(delta: float):
	if holo_mesh == null: return
	
	# Rotate continuously
	holo_mesh.rotation.y += 1.5 * delta
	
	# Bob up and down based on time
	var t = (Time.get_ticks_msec() * 0.002) + time_offset
	holo_mesh.position.y = base_y + sin(t) * 0.3
	
	# Glitch effect (1% chance per frame)
	if randf() < 0.01:
		_apply_glitch()


func _apply_glitch():
	var original_scale = Vector3.ONE
	var is_visible_glitch = randf() > 0.5
	
	if is_visible_glitch:
		# Visibility flicker
		holo_mesh.visible = false
		get_tree().create_timer(0.05 + randf() * 0.1).timeout.connect(func(): holo_mesh.visible = true)
	else:
		# Scale skew glitch
		holo_mesh.scale = Vector3(1.0 + randf() * 0.5, 0.2 + randf() * 0.5, 1.0 + randf() * 0.5)
		get_tree().create_timer(0.1).timeout.connect(func(): holo_mesh.scale = original_scale)
