## NPC Dialogue System
## Manages the UI overlay and streaming responses from the AI backend.

extends CanvasLayer

@onready var dialog_box: Control = $DialogueBox
@onready var text_label: RichTextLabel = $DialogueBox/MarginContainer/HBoxContainer/VBoxContainer/DialogueText
@onready var name_label: Label = $DialogueBox/MarginContainer/HBoxContainer/VBoxContainer/NPCName
@onready var input_line: LineEdit = $DialogueBox/MarginContainer/HBoxContainer/VBoxContainer/InputArea/InputLine
@onready var send_button: Button = $DialogueBox/MarginContainer/HBoxContainer/VBoxContainer/InputArea/SendButton
var taxi_button: Button = null
@onready var portrait_rect: TextureRect = $DialogueBox/MarginContainer/HBoxContainer/PortraitFrame/Portrait
@onready var anim_player: AnimationPlayer = $AnimationPlayer

var is_active: bool = false
var current_npc_id: String = ""
var message_history: Array = []
var is_typing: bool = false

func _ready():
	dialog_box.visible = false
	input_line.text_submitted.connect(_on_input_submitted)
	send_button.pressed.connect(func(): _on_input_submitted(input_line.text))
	
	# Dynamically create the Taxi Button
	taxi_button = Button.new()
	taxi_button.text = "START TAXI MISSION"
	taxi_button.add_theme_color_override("font_color", Color(1, 0.8, 0))
	$DialogueBox/MarginContainer/HBoxContainer/VBoxContainer/InputArea.add_child(taxi_button)
	taxi_button.pressed.connect(_start_taxi_mission)
	taxi_button.visible = false
		
	text_label.bbcode_enabled = true

func start_dialogue(data: Dictionary):
	is_active = true
	current_npc_id = data.npcId
	name_label.text = "[ " + data.npcName.to_upper() + " ]"
	message_history = []
	text_label.text = ""
	input_line.clear()
	
	# Load Portrait
	var p_path = "res://ui/npc_portraits/generic_npc.png"
	var role_lower = data.get("role", "civilian").to_lower()
	
	if "guard" in role_lower or "nexus" in role_lower:
		p_path = "res://ui/npc_portraits/nexus_guard.png"
	elif "shadow" in role_lower or "informant" in role_lower or "syndicate" in role_lower:
		p_path = "res://ui/npc_portraits/shadow_informant.png"
	
	if ResourceLoader.exists(p_path):
		portrait_rect.texture = load(p_path)
		
	# Mission hook
	if taxi_button:
		taxi_button.visible = ("dispatcher" in role_lower or "driver" in role_lower)
	
	dialog_box.visible = true
	input_line.grab_focus()
	
	if anim_player:
		anim_player.play("fade_in")
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_add_log("SYSTEM", "Connection established. Secure link active.")

func _add_log(sender: String, message: String):
	var color = "#00ffff" if sender == "NPC" else "#ff00ff"
	if sender == "SYSTEM": color = "#555555"
	
	var log_entry = "[color=%s][b]%s:[/b][/color] %s" % [color, sender, message]
	message_history.append(log_entry)
	_refresh_display()

func _refresh_display():
	var full_text = ""
	for i in range(message_history.size()):
		full_text += message_history[i] + "\n\n"
	text_label.text = full_text

func update_text(message: String):
	is_typing = true
	input_line.editable = false
	
	var base_history = ""
	for i in range(message_history.size()):
		base_history += message_history[i] + "\n\n"
	
	var current_text = "[color=#00ffff][b]NPC:[/b][/color] "
	message_history.append(current_text + message) # Add to history for persistence
	
	# Typing animation
	text_label.text = base_history + current_text
	for i in range(message.length()):
		if not is_active: break
		text_label.text += message[i]
		# Small random delay for "glitchy" typing feel
		await get_tree().create_timer(randf_range(0.01, 0.03)).timeout
	
	is_typing = false
	input_line.editable = true
	input_line.grab_focus()

func _on_input_submitted(text: String):
	if text.strip_edges() == "" or not is_active or is_typing:
		return
	
	_add_log("YOU", text)
	input_line.clear()
	input_line.editable = false
	
	var nm = get_node_or_null("/root/NetworkManager")
	if nm:
		nm.socket_client.send_event("npc_chat", {"npcId": current_npc_id, "message": text})

func end_dialogue():
	is_active = false
	current_npc_id = ""
	if anim_player:
		anim_player.play("fade_out")
		await anim_player.animation_finished
	
	dialog_box.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _start_taxi_mission():
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and current_npc_id != "":
		nm.socket_client.send_event("start_vehicle_mission", {"type": "taxi"})
		end_dialogue()

func _input(event):
	if is_active and event.is_action_pressed("ui_cancel"):
		end_dialogue()
		var nm = get_node_or_null("/root/NetworkManager")
		if nm:
			nm.socket_client.send_event("end_npc_interaction", {"npcId": current_npc_id})
