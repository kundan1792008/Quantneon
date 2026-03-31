extends Control

@onready var banner: PanelContainer = $VBoxContainer/Banner
@onready var title: Label = $VBoxContainer/Banner/MarginContainer/VBoxContainer/Title
@onready var desc: Label = $VBoxContainer/Banner/MarginContainer/VBoxContainer/Description
@onready var progress_bar: ProgressBar = $VBoxContainer/ProgressBar

func _ready() -> void:
	hide()
	if NetworkManager.socket:
		NetworkManager.socket.on("active_events_update", _on_events_update)
		NetworkManager.socket.on("event_notification", _on_event_notification)

func _on_events_update(events: Array) -> void:
	if events.size() == 0:
		hide()
		return
		
	show()
	var ev = events[0]
	
	if ev.type == "faction_raid":
		title.text = "FACTION RAID: " + ev.attackingFaction.replace("_", " ")
		desc.text = "Defend " + ev.zoneId.capitalize() + " from attackers."
		title.modulate = Color.RED
	else:
		title.text = "GLOBAL EVENT"
		title.modulate = Color.YELLOW
		
	progress_bar.value = ev.progress

func _on_event_notification(data: Dictionary) -> void:
	# Show immediate big popup warning
	print("[EVENT ALERT] ", data.title, " - ", data.message)
	_flash_screen()
	
func _flash_screen():
	# Simple visual feedback for big events
	var rect = ColorRect.new()
	rect.color = Color(1, 0, 0, 0.3)
	rect.set_anchors_preset(PRESET_FULL_RECT)
	add_child(rect)
	
	var tween = create_tween()
	tween.tween_property(rect, "color:a", 0.0, 1.0)
	tween.tween_callback(rect.queue_free)
