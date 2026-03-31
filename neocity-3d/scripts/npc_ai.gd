## NPC AI Controller for Neo City
## Handles idle movement, target tracking, and interaction interface.

extends CharacterBody3D

@export var npc_id: String = ""
@export var role: String = "civilian"
@export var behavior: String = "idle"
@export var movement_speed: float = 2.0
@export var rotation_speed: float = 5.0
@export var interaction_distance: float = 3.0

var target_position: Vector3
var last_position: Vector3
var is_moving: bool = false
var wait_timer: float = 0.0
var is_remote: bool = false # Managed by NetworkManager
var behavior_type: String = "idle"
var current_activity: String = "work"

@onready var anim_player: AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null

# ── Combat ───────────────────────────────────────────
@export var max_health: float = 100.0
var current_health: float = max_health
var is_dead: bool = false

var hp_bar_viewport: SubViewport
var hp_bar: ProgressBar
var hp_sprite: Sprite3D
var damage_text_scene = preload("res://scenes/damage_text.tscn")

func _ready():
	randomize()
	_setup_health_bar()
	_pick_new_target()

func _setup_health_bar():
	hp_bar_viewport = SubViewport.new()
	hp_bar_viewport.transparent_bg = true
	hp_bar_viewport.size = Vector2(200, 20)
	
	hp_bar = ProgressBar.new()
	hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_bar.show_percentage = false
	hp_bar.max_value = max_health
	hp_bar.value = current_health
	
	# Style the bar
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	var style_fg = StyleBoxFlat.new()
	style_fg.bg_color = Color(1.0, 0.2, 0.2, 1.0)
	hp_bar.add_theme_stylebox_override("background", style_bg)
	hp_bar.add_theme_stylebox_override("fill", style_fg)
	
	hp_bar_viewport.add_child(hp_bar)
	add_child(hp_bar_viewport)
	
	hp_sprite = Sprite3D.new()
	hp_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_sprite.texture = hp_bar_viewport.get_texture()
	hp_sprite.position = Vector3(0, 2.5, 0) # Hover above head
	hp_sprite.visible = false # Only show when damaged
	add_child(hp_sprite)

func set_remote_mode(remote: bool):
	is_remote = remote
	behavior = "remote" if remote else "idle"

func take_damage(amount: float):
	if is_dead: return
	
	current_health -= amount
	print("[NPC] Vital signs: ", current_health)
	
	if hp_bar:
		hp_bar.value = current_health
		hp_sprite.visible = true
		
	# Spawn Floating Damage Text
	if damage_text_scene:
		var dtext = damage_text_scene.instantiate()
		get_tree().root.add_child(dtext)
		dtext.global_position = global_position + Vector3(0, 2.0, 0)
		dtext.setup(amount)
	
	# Visual Feedback (Flash red)
	var tween = create_tween()
	var mesh = $MeshInstance3D
	tween.tween_property(mesh, "surface_material_override/0:albedo_color", Color.RED, 0.1)
	tween.tween_property(mesh, "surface_material_override/0:albedo_color", Color.YELLOW, 0.1)
	
	if current_health <= 0:
		die()

func die():
	is_dead = true
	print("[NPC] Connection lost...")
	collision_layer = 0
	collision_mask = 0
	if hp_sprite: hp_sprite.visible = false
	
	var tween = create_tween()
	# Rotate 90 degrees backwards to simulate falling
	tween.tween_property(self, "rotation_degrees:x", -90, 0.3)
	tween.tween_property(self, "position:y", position.y - 0.5, 0.3)
	tween.tween_property($MeshInstance3D, "transparency", 1.0, 1.0).set_delay(0.5)
	
	await tween.finished
	queue_free()

func update_state(data: Dictionary):
	if data.has("activity"):
		current_activity = data.activity
	
	if data.has("health") and not is_dead:
		var old_hp = current_health
		current_health = data.health
		if hp_bar: hp_bar.value = current_health
		
		# If health dropped and it wasn't a local prediction, show damage
		if current_health < old_hp:
			hp_sprite.visible = true

func _physics_process(delta):
	if is_remote:
		_process_remote_animations(delta)
		return
		
	if behavior == "idle":
		_process_idle_behavior(delta)
	
	move_and_slide()

func _process_remote_animations(delta):
	var velocity_vec = (global_position - last_position) / delta
	last_position = global_position
	
	var horizontal_speed = Vector2(velocity_vec.x, velocity_vec.z).length()
	
	if anim_player:
		if horizontal_speed > 3.5:
			anim_player.play("run")
		elif horizontal_speed > 0.1:
			anim_player.play("walk")
		else:
			if current_activity == "sleep":
				if anim_player.has_animation("sleep"): anim_player.play("sleep")
				else: anim_player.play("idle")
			elif current_activity == "leisure":
				if anim_player.has_animation("cheer"): anim_player.play("cheer")
				else: anim_player.play("idle")
			else:
				anim_player.play("idle")
			
	# Handle Behavior Visuals
	if behavior_type == "flee":
		$MeshInstance3D.modulate = Color(1, 0.5, 0.5) # Slight red tint
	elif behavior_type == "pursue":
		$MeshInstance3D.modulate = Color.RED # Aggressive red
	elif horizontal_speed <= 0.1:
		# Activity Visuals
		if current_activity == "sleep":
			$MeshInstance3D.modulate = Color(0.2, 0.2, 0.8) # Sleepy Blue
		elif current_activity == "leisure":
			$MeshInstance3D.modulate = Color(0.8, 0.2, 0.8) # Leisure Purple
		else:
			$MeshInstance3D.modulate = Color.WHITE
	else:
		$MeshInstance3D.modulate = Color.WHITE

func _process_idle_behavior(delta):
	if is_moving:
		var direction = (target_position - global_position).normalized()
		direction.y = 0
		
		velocity.x = direction.x * movement_speed
		velocity.z = direction.z * movement_speed
		
		# Rotate to face direction
		var target_basis = Basis.looking_at(direction)
		basis = basis.slerp(target_basis, rotation_speed * delta)
		
		if global_position.distance_to(target_position) < 0.5:
			is_moving = false
			velocity = Vector3.ZERO
			wait_timer = randf_range(2.0, 5.0)
	else:
		wait_timer -= delta
		if wait_timer <= 0:
			_pick_new_target()

func _pick_new_target():
	var angle = randf() * PI * 2
	var radius = randf_range(5.0, 15.0)
	target_position = global_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
	is_moving = true

func interact(player):
	print("Interacted with NPC: ", role)
	look_at(player.global_position)
	rotation.x = 0
	rotation.z = 0
	
	if role == "quest_giver":
		var nm = get_node_or_null("/root/NetworkManager")
		if nm:
			print("[NPC] Offering quest...")
			nm.socket_client.send_event("quest_accept", {"questId": "q_welcome"})
	
	if role == "merchant" or role == "shopkeeper" or role == "shadow_trader" or role == "smuggler":
		if has_node("/root/TraderUI"):
			get_node("/root/TraderUI").open_trader(npc_id)
	elif role == "ripperdoc":
		if has_node("/root/CyberneticsUI"):
			get_node("/root/CyberneticsUI").open_clinic(npc_id)
	else:
		# Default dialogue interaction
		behavior = "busy"
		_resume_behavior_after(3.0)

func _resume_behavior_after(delay):
	await get_tree().create_timer(delay).timeout
	behavior = "idle"
