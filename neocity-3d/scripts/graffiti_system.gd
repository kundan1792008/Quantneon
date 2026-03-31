## GraffitiSystem — Allows players to spray neon tags on designated walls
extends Node3D

@onready var prompt_label: Label3D = $PromptLabel
@onready var art_display: Label3D = $ArtDisplay
@onready var trigger_area: Area3D = $TriggerArea

@export var wall_id: String = "wall_default"

var player_in_range: bool = false
var current_art_index: int = -1

var graffiti_tags: Array[Dictionary] = [
	{"text": "", "color": Color(0, 0, 0, 0)}, # 0: Blank/Clear
	{"text": "SYNDICATE", "color": Color(1, 0, 0, 1)}, # 1: Red
	{"text": "NEON-GHOST", "color": Color(0, 1, 1, 1)}, # 2: Cyan
	{"text": "V3X", "color": Color(1, 0, 1, 1)}, # 3: Magenta
	{"text": "GLITCH", "color": Color(0, 1, 0, 1)}, # 4: Green
	{"text": "NULL", "color": Color(1, 1, 0, 1)}  # 5: Yellow
]

func _ready():
	prompt_label.visible = false
	
	# Connect Area3D signals
	trigger_area.body_entered.connect(_on_body_entered)
	trigger_area.body_exited.connect(_on_body_exited)
	
	# Listen to incoming socket updates from the server
	if NetworkManager.socket_client:
		NetworkManager.socket_client.on("zone_graffiti_update", Callable(self, "_on_network_graffiti_update"))
		
	# Initialize blank
	_update_display(0)

func _on_body_entered(body: Node3D):
	if body.name == "Player":
		player_in_range = true
		prompt_label.visible = true

func _on_body_exited(body: Node3D):
	if body.name == "Player":
		player_in_range = false
		prompt_label.visible = false

func _unhandled_input(event: InputEvent):
	if player_in_range and event.is_action_pressed("interact"):
		# Cycle to next art
		current_art_index = (current_art_index + 1) % graffiti_tags.size()
		# Skip blank (0) when spraying manually if we want to force art
		if current_art_index == 0:
			current_art_index = 1
		
		# Immediately show locally for responsiveness
		_update_display(current_art_index)
		
		# Send to server to broadcast to the zone
		if NetworkManager.socket_client and NetworkManager.socket_client.connected:
			NetworkManager.socket_client.send_event("spray_graffiti", {
				"wallId": wall_id,
				"artIndex": current_art_index
			})

func _on_network_graffiti_update(data: Dictionary):
	# Wait for network event:
	# { "wallId": "...", "artIndex": 2 }
	if data.has("wallId") and data["wallId"] == wall_id:
		if data.has("artIndex"):
			_update_display(int(data["artIndex"]))

func _update_display(index: int):
	current_art_index = index
	var tag = graffiti_tags[index]
	art_display.text = tag.text
	art_display.modulate = tag.color
	
	# Add some emission glow
	var material = art_display.material_override as StandardMaterial3D
	if not material:
		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		art_display.material_override = material
		
	material.albedo_color = tag.color
