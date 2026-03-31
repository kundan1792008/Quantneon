extends Control

@onready var line_edit: LineEdit = $Panel/LineEdit
@onready var send_button: Button = $Panel/SendButton

func _ready():
    visible = false
    send_button.pressed.connect(_on_send_pressed)
    line_edit.text_submitted.connect(_on_text_submitted)

func toggle_chat():
    visible = !visible
    if visible:
        line_edit.grab_focus()
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    else:
        line_edit.release_focus()
        Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_send_pressed():
    _send_message()

func _on_text_submitted(_new_text: String):
    _send_message()

func _send_message():
    var text = line_edit.text.strip_edges()
    if text.length() > 0:
        if NetworkManager.socket_client:
            NetworkManager.socket_client.send_event("drone_chat", {"message": text})
            
        line_edit.text = ""
        toggle_chat() # Auto-close after sending
