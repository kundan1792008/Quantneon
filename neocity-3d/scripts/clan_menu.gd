## Godot Clan Management Menu
## Allows players to see clan members, invite players, and view clan bonuses.

extends Control

@onready var clan_name_label: Label = $Panel/VBoxContainer/Header/ClanName
@onready var clan_tag_label: Label = $Panel/VBoxContainer/Header/ClanTag
@onready var member_list: ItemList = $Panel/VBoxContainer/MemberList
@onready var invite_input: LineEdit = $Panel/VBoxContainer/Footer/InviteInput
@onready var invite_button: Button = $Panel/VBoxContainer/Footer/InviteButton

var network_manager: Node

func _ready():
	network_manager = get_node_or_null("/root/NetworkManager")
	if !network_manager:
		push_error("NetworkManager not found for ClanMenu")
		return
		
	# Connect signals from NetworkManager
	# (In a real app, you'd have specific signals for clan updates)
	
	hide()

func open():
	show()
	_refresh_data()

func _refresh_data():
	# Request clan data from server via NetworkManager
	if !network_manager: return
	
	# This would technically be a custom event we'd need to add to the socket
	# For now, we'll assume the player's current state has it
	pass

func _on_close_pressed():
	hide()

func _on_invite_pressed():
	var uid = invite_input.get_text()
	if uid == "": return
	
	if network_manager:
		network_manager.socket_client.send_event("clan_invite", {"userId": uid})
		invite_input.clear()
		print("[Clan] Invitation sent to ", uid)
