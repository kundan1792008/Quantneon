extends Node3D

@export var terminal_id: String = ""

var defense: int = 1
var is_hacked: bool = false
var loot_available: int = 0
var cooldown_ticks: int = 0

@onready var status_label: Label3D = $StatusLabel
@onready var defense_label: Label3D = $DefenseLabel
@onready var mesh: MeshInstance3D = $TerminalMesh

func update_state(data: Dictionary):
	if data.has("defense"):
		defense = data.defense
		defense_label.text = "ICE: " + str(defense)
		
	if data.has("isHacked"):
		is_hacked = data.isHacked
		
	if data.has("lootAvailable"):
		loot_available = data.lootAvailable
		
	if data.has("cooldownTicks"):
		cooldown_ticks = data.cooldownTicks

	_refresh_visuals()

func _refresh_visuals():
	if is_hacked:
		status_label.text = "TERMINAL [LOCKED OUT]"
		status_label.modulate = Color(1, 0, 0) # Red
		var mat = mesh.get_surface_override_material(0)
		if mat:
			mat.emission = Color.RED
	else:
		if loot_available > 0:
			status_label.text = "TERMINAL [ONLINE]"
			status_label.modulate = Color(0, 1, 0) # Green
			var mat = mesh.get_surface_override_material(0)
			if mat:
				mat.emission = Color.GREEN
		else:
			status_label.text = "TERMINAL [EMPTY]"
			status_label.modulate = Color(0.5, 0.5, 0.5) # Gray
			var mat = mesh.get_surface_override_material(0)
			if mat:
				mat.emission = Color.GRAY

func interact(player):
	if is_hacked:
		print("Terminal is locked out.")
		return
		
	print("Interacting with Data Terminal...")
	# Open Cyberdeck UI
	if has_node("/root/CyberdeckUI"):
		get_node("/root/CyberdeckUI").open_deck(terminal_id, defense)
