## Weapon System Manager
## Handles firing logic, ammo, and effects for ranged and melee weapons.

extends Node

signal weapon_fired(weapon_name, ammo_left)
signal weapon_reloaded(weapon_name)
signal hit_detected(target_id, damage)

@export var current_weapon: String = "laser_pistol"
@export var ammo_max: int = 20
@export var ammo_current: int = 20
@export var fire_rate: float = 0.2
@export var damage: float = 15.0

var can_fire: bool = true
@onready var fire_timer: Timer = Timer.new()

func _ready():
	add_child(fire_timer)
	fire_timer.one_shot = true
	fire_timer.timeout.connect(func(): can_fire = true)

func fire(ray: RayCast3D):
	if !can_fire or ammo_current <= 0:
		return
	
	can_fire = false
	ammo_current -= 1
	fire_timer.start(fire_rate)
	
	# Visual/Sound Feedback (Piped to Player Controller for anims)
	weapon_fired.emit(current_weapon, ammo_current)
	
	# Raycast hit detection
	if ray.is_colliding():
		var target = ray.get_collider()
		if target.has_method("take_damage"):
			# In a real networked game, we'd wait for server verification
			# For now, we predict the hit for responsiveness
			var target_id = ""
			if "npc_id" in target: target_id = target.npc_id
			elif "userId" in target: target_id = target.userId
			
			hit_detected.emit(target_id, damage)
			target.take_damage(damage)

func reload():
	if ammo_current == ammo_max:
		return
	
	print("[Weapon] Reloading...")
	# Simulate reload time
	can_fire = false
	await get_tree().create_timer(1.5).timeout
	ammo_current = ammo_max
	can_fire = true
	weapon_reloaded.emit(current_weapon)
