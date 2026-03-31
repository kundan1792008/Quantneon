extends Control

@onready var close_button: Button = $Panel/VBoxContainer/Header/CloseButton
@onready var news_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/NewsList

func _ready() -> void:
	hide()
	close_button.pressed.connect(_on_close_pressed)

	if NetworkManager.socket:
		NetworkManager.socket.on("news_history", _on_news_history)

func show_ui() -> void:
	show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_close_pressed() -> void:
	hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_news_history(history: Array) -> void:
	# Clear old
	for child in news_list.get_children():
		child.queue_free()
		
	if history.size() == 0:
		var empty_lbl = Label.new()
		empty_lbl.text = "No recent broadcasts."
		news_list.add_child(empty_lbl)
		show_ui()
		return
		
	for broadcast in history:
		var container = VBoxContainer.new()
		
		# Headline
		var hl = Label.new()
		hl.text = "> " + broadcast.headline
		hl.add_theme_font_size_override("font_size", 20)
		hl.add_theme_color_override("font_color", Color.YELLOW if broadcast.urgency != "critical" else Color.RED)
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		
		# Body
		var body = Label.new()
		body.text = broadcast.body
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_color_override("font_color", Color.LIGHT_GRAY)
		
		# Time / Source
		var meta = Label.new()
		var t = Time.get_datetime_dict_from_unix_time(broadcast.timestamp / 1000)
		meta.text = broadcast.source + " | " + str(t.hour) + ":" + str(t.minute)
		meta.add_theme_font_size_override("font_size", 12)
		meta.add_theme_color_override("font_color", Color.DARK_GRAY)
		
		container.add_child(hl)
		container.add_child(meta)
		container.add_child(body)
		
		var sep = HSeparator.new()
		container.add_child(sep)
		
		news_list.add_child(container)
		
	show_ui()
