## FactionManager — Faction creation, membership, roles, and chat system.
##
## Handles:
##   • Faction creation / disbanding (min 5 members, max 3 factions per district).
##   • Roles: Leader (1), Officer (max 3), Member.
##   • Membership: apply to join, invite by officer/leader, kick/ban.
##   • Faction statistics: territory_count, total_building_value, member_count, war_wins.
##   • Faction chat channel relayed via existing Socket.IO connection.
##   • Persistent state mirrored from server; client is read-only except for
##     actions the local player initiates (create, apply, invite, kick, etc.).
##
## Autoloaded as /root/FactionManager.

extends Node

# ── Constants ──────────────────────────────────────────────────────────────────

## Maximum number of active factions that may exist in a single city district.
const MAX_FACTIONS_PER_DISTRICT: int = 3

## Minimum member count required to found a faction.
const MIN_MEMBERS_TO_FORM: int = 5

## Maximum number of officers a faction may have at any one time.
const MAX_OFFICERS: int = 3

## Quant-token treasury fee charged when a faction is created.
const FACTION_CREATION_COST: int = 2500

## How often (seconds) the local faction state is re-requested from the server.
const STATE_POLL_INTERVAL: float = 30.0

# ── Role constants ─────────────────────────────────────────────────────────────

const ROLE_LEADER:  String = "leader"
const ROLE_OFFICER: String = "officer"
const ROLE_MEMBER:  String = "member"

# ── Chat channel ───────────────────────────────────────────────────────────────

## Socket.IO event name used for faction-scoped chat messages.
const FACTION_CHAT_EVENT: String = "faction_chat"

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when the local player's faction data changes (join, leave, kicked, etc.).
signal faction_updated(faction_data: Dictionary)

## Emitted when a new faction chat message arrives.
signal faction_message_received(sender_name: String, message: String, timestamp: int)

## Emitted when the faction member list changes (join, leave, kick, ban, role change).
signal members_updated(members: Array)

## Emitted when an application to the local player's faction is received (leader/officer only).
signal application_received(applicant_id: String, applicant_name: String)

## Emitted when an invite sent by the server is targeted at the local player.
signal invite_received(faction_id: String, faction_name: String, inviter_name: String)

## Emitted when a faction's aggregate stats change (territory, building value, etc.).
signal faction_stats_updated(faction_id: String, stats: Dictionary)

## Emitted when the district faction roster (which factions exist) changes.
signal district_factions_updated(district_id: String, factions: Array)

# ── State ─────────────────────────────────────────────────────────────────────

## The local player's current faction data. Empty dict = not in a faction.
## Keys: id, name, tag, color_hex, district_id, leader_id, officers[], members[],
##       territory_count, total_building_value, member_count, war_wins, treasury.
var local_faction: Dictionary = {}

## Local player's role within their faction ("leader" | "officer" | "member" | "").
var local_role: String = ""

## All known factions indexed by faction_id.
var all_factions: Dictionary = {}  # {faction_id: Dictionary}

## Pending applications to the local player's faction (leader/officer view).
var pending_applications: Array = []  # [{player_id, player_name, applied_unix}]

## Pending invites received by the local player.
var pending_invites: Array = []  # [{faction_id, faction_name, inviter_name, expires_unix}]

## Banned player IDs for the local faction (leader-only view).
var ban_list: Array = []  # [player_id, ...]

## Socket reference — resolved lazily.
var _socket: Node = null
var _poll_timer: float = 0.0

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_resolve_socket()
	print("[FactionManager] Ready.")

func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= STATE_POLL_INTERVAL:
		_poll_timer = 0.0
		_request_faction_state()

# ── Socket helpers ─────────────────────────────────────────────────────────────

func _resolve_socket() -> void:
	_socket = get_node_or_null("/root/SocketIOClient")
	if _socket == null:
		push_warning("[FactionManager] SocketIOClient not found; retrying in 1 s.")
		get_tree().create_timer(1.0).timeout.connect(_resolve_socket)
		return
	_socket.on_event("faction_state",        _on_faction_state)
	_socket.on_event("faction_member_update", _on_member_update)
	_socket.on_event(FACTION_CHAT_EVENT,     _on_faction_chat)
	_socket.on_event("faction_application",  _on_faction_application)
	_socket.on_event("faction_invite",       _on_faction_invite)
	_socket.on_event("faction_stats_update", _on_faction_stats_update)
	_socket.on_event("district_factions",    _on_district_factions)
	_socket.on_event("faction_kick",         _on_faction_kick)
	print("[FactionManager] Socket events registered.")

func _emit(event: String, payload: Dictionary) -> void:
	if _socket == null:
		push_warning("[FactionManager] Cannot emit '%s' — socket unavailable." % event)
		return
	_socket.send_event(event, payload)

func _request_faction_state() -> void:
	_emit("get_faction_state", {})

# ── Public API: Faction creation / disbanding ──────────────────────────────────

## Create a new faction in the given district. Costs FACTION_CREATION_COST tokens.
## The caller must have ≥ MIN_MEMBERS_TO_FORM confirmed members (validated server-side).
func create_faction(name: String, tag: String, color_hex: String, district_id: String) -> void:
	if not local_faction.is_empty():
		push_warning("[FactionManager] Already in a faction; cannot create another.")
		return
	_emit("faction_create", {
		"name":        name,
		"tag":         tag,
		"color_hex":   color_hex,
		"district_id": district_id
	})

## Disband the local player's faction. Leader-only action.
func disband_faction() -> void:
	if local_role != ROLE_LEADER:
		push_warning("[FactionManager] Only the leader can disband a faction.")
		return
	_emit("faction_disband", {"faction_id": local_faction.get("id", "")})

# ── Public API: Membership ─────────────────────────────────────────────────────

## Submit an application to join the given faction.
func apply_to_faction(faction_id: String, message: String = "") -> void:
	if not local_faction.is_empty():
		push_warning("[FactionManager] Already in a faction.")
		return
	_emit("faction_apply", {"faction_id": faction_id, "message": message})

## Accept a received invite to join the specified faction.
func accept_invite(faction_id: String) -> void:
	_emit("faction_accept_invite", {"faction_id": faction_id})
	pending_invites = pending_invites.filter(func(i): return i.get("faction_id", "") != faction_id)

## Decline a received invite.
func decline_invite(faction_id: String) -> void:
	_emit("faction_decline_invite", {"faction_id": faction_id})
	pending_invites = pending_invites.filter(func(i): return i.get("faction_id", "") != faction_id)

## Send an invite to a player. Requires officer or leader role.
func invite_player(target_player_id: String, target_player_name: String) -> void:
	if local_role != ROLE_LEADER and local_role != ROLE_OFFICER:
		push_warning("[FactionManager] Must be officer or leader to invite.")
		return
	_emit("faction_invite_player", {
		"faction_id":         local_faction.get("id", ""),
		"target_player_id":   target_player_id,
		"target_player_name": target_player_name
	})

## Accept a pending application. Requires officer or leader role.
func accept_application(applicant_id: String) -> void:
	if local_role != ROLE_LEADER and local_role != ROLE_OFFICER:
		push_warning("[FactionManager] Must be officer or leader to accept applications.")
		return
	_emit("faction_accept_application", {
		"faction_id":    local_faction.get("id", ""),
		"applicant_id":  applicant_id
	})
	pending_applications = pending_applications.filter(func(a): return a.get("player_id", "") != applicant_id)

## Reject a pending application. Requires officer or leader role.
func reject_application(applicant_id: String) -> void:
	if local_role != ROLE_LEADER and local_role != ROLE_OFFICER:
		push_warning("[FactionManager] Must be officer or leader to reject applications.")
		return
	_emit("faction_reject_application", {
		"faction_id":   local_faction.get("id", ""),
		"applicant_id": applicant_id
	})
	pending_applications = pending_applications.filter(func(a): return a.get("player_id", "") != applicant_id)

## Leave the local player's current faction voluntarily.
func leave_faction() -> void:
	if local_faction.is_empty():
		return
	_emit("faction_leave", {"faction_id": local_faction.get("id", "")})

# ── Public API: Member management (leader / officer) ───────────────────────────

## Kick a member from the faction. Officers can kick members; only leader can kick officers.
func kick_member(target_player_id: String) -> void:
	if local_role != ROLE_LEADER and local_role != ROLE_OFFICER:
		push_warning("[FactionManager] Must be officer or leader to kick members.")
		return
	_emit("faction_kick_member", {
		"faction_id":      local_faction.get("id", ""),
		"target_player_id": target_player_id
	})

## Ban a player from the faction. Leader-only.
func ban_member(target_player_id: String, reason: String = "") -> void:
	if local_role != ROLE_LEADER:
		push_warning("[FactionManager] Only the leader can ban members.")
		return
	_emit("faction_ban_member", {
		"faction_id":       local_faction.get("id", ""),
		"target_player_id": target_player_id,
		"reason":           reason
	})

## Unban a previously banned player. Leader-only.
func unban_member(target_player_id: String) -> void:
	if local_role != ROLE_LEADER:
		push_warning("[FactionManager] Only the leader can unban members.")
		return
	_emit("faction_unban_member", {
		"faction_id":       local_faction.get("id", ""),
		"target_player_id": target_player_id
	})

# ── Public API: Role management ────────────────────────────────────────────────

## Promote a member to officer. Leader-only, max MAX_OFFICERS officers enforced server-side.
func promote_to_officer(target_player_id: String) -> void:
	if local_role != ROLE_LEADER:
		push_warning("[FactionManager] Only the leader can promote to officer.")
		return
	var current_officers: Array = local_faction.get("officers", [])
	if current_officers.size() >= MAX_OFFICERS:
		push_warning("[FactionManager] Officer limit (%d) already reached." % MAX_OFFICERS)
		return
	_emit("faction_promote_officer", {
		"faction_id":       local_faction.get("id", ""),
		"target_player_id": target_player_id
	})

## Demote an officer back to member. Leader-only.
func demote_officer(target_player_id: String) -> void:
	if local_role != ROLE_LEADER:
		push_warning("[FactionManager] Only the leader can demote officers.")
		return
	_emit("faction_demote_officer", {
		"faction_id":       local_faction.get("id", ""),
		"target_player_id": target_player_id
	})

## Transfer leadership to another member. Leader-only. Leader becomes an officer.
func transfer_leadership(target_player_id: String) -> void:
	if local_role != ROLE_LEADER:
		push_warning("[FactionManager] Only the current leader can transfer leadership.")
		return
	_emit("faction_transfer_leadership", {
		"faction_id":       local_faction.get("id", ""),
		"target_player_id": target_player_id
	})

# ── Public API: Faction chat ───────────────────────────────────────────────────

## Send a message to the faction-scoped chat channel.
func send_faction_chat(message: String) -> void:
	if local_faction.is_empty():
		push_warning("[FactionManager] Not in a faction; cannot send faction chat.")
		return
	_emit(FACTION_CHAT_EVENT, {
		"faction_id": local_faction.get("id", ""),
		"message":    message
	})

# ── Public API: Queries ────────────────────────────────────────────────────────

## Returns true if the local player is currently in a faction.
func is_in_faction() -> bool:
	return not local_faction.is_empty()

## Returns the local player's role string, or "" if not in a faction.
func get_local_role() -> String:
	return local_role

## Returns the faction dict for the given id, or an empty dict if unknown.
func get_faction(faction_id: String) -> Dictionary:
	return all_factions.get(faction_id, {})

## Returns all members of the local faction as an Array of member dicts.
## Each entry has keys: player_id, player_name, role, joined_unix, online.
func get_local_faction_members() -> Array:
	if local_faction.is_empty():
		return []
	var members: Array = local_faction.get("members", [])
	var officers: Array = local_faction.get("officers", [])
	var leader_id: String = local_faction.get("leader_id", "")
	# Enrich each member dict with their computed role.
	var result: Array = []
	for m in members:
		var entry: Dictionary = m.duplicate()
		var pid: String = m.get("player_id", "")
		if pid == leader_id:
			entry["role"] = ROLE_LEADER
		elif officers.has(pid):
			entry["role"] = ROLE_OFFICER
		else:
			entry["role"] = ROLE_MEMBER
		result.append(entry)
	return result

## Returns a human-readable label for a role constant.
func role_label(role: String) -> String:
	match role:
		ROLE_LEADER:  return "Leader"
		ROLE_OFFICER: return "Officer"
		_:            return "Member"

# ── Socket event handlers ──────────────────────────────────────────────────────

func _on_faction_state(data: Dictionary) -> void:
	var fid: String = data.get("id", data.get("faction_id", ""))
	if fid == "":
		# Local player has no faction.
		if not local_faction.is_empty():
			local_faction = {}
			local_role = ""
			emit_signal("faction_updated", {})
		return

	local_faction = data
	local_role = _compute_local_role()
	all_factions[fid] = data
	emit_signal("faction_updated", data)
	emit_signal("members_updated", get_local_faction_members())

func _on_member_update(data: Dictionary) -> void:
	## Server pushes incremental member changes (join, leave, kick, role change).
	var fid: String = data.get("faction_id", "")
	if fid == "" or not all_factions.has(fid):
		return

	var action: String   = data.get("action", "")
	var player_id: String = data.get("player_id", "")
	var faction: Dictionary = all_factions[fid]

	match action:
		"join":
			var new_member: Dictionary = {
				"player_id":   player_id,
				"player_name": data.get("player_name", ""),
				"joined_unix": int(data.get("joined_unix", 0)),
				"online":      true
			}
			var members: Array = faction.get("members", [])
			members.append(new_member)
			faction["members"] = members
			faction["member_count"] = members.size()
		"leave", "kick":
			var members: Array = faction.get("members", [])
			members = members.filter(func(m): return m.get("player_id", "") != player_id)
			faction["members"] = members
			faction["member_count"] = members.size()
			if action == "kick":
				var officers: Array = faction.get("officers", [])
				if officers.has(player_id):
					officers.erase(player_id)
					faction["officers"] = officers
		"promote_officer":
			var officers: Array = faction.get("officers", [])
			if not officers.has(player_id):
				officers.append(player_id)
				faction["officers"] = officers
		"demote_officer":
			var officers: Array = faction.get("officers", [])
			officers.erase(player_id)
			faction["officers"] = officers
		"new_leader":
			faction["leader_id"] = player_id
			var old_leader: String = data.get("old_leader_id", "")
			if old_leader != "":
				var officers: Array = faction.get("officers", [])
				if not officers.has(old_leader):
					officers.append(old_leader)
					faction["officers"] = officers
			var officers: Array = faction.get("officers", [])
			officers.erase(player_id)
			faction["officers"] = officers

	all_factions[fid] = faction
	if fid == local_faction.get("id", ""):
		local_faction = faction
		local_role = _compute_local_role()
		emit_signal("faction_updated", faction)
		emit_signal("members_updated", get_local_faction_members())

func _on_faction_chat(data: Dictionary) -> void:
	var fid: String = data.get("faction_id", "")
	if fid != local_faction.get("id", ""):
		return  # Not our faction's channel.
	emit_signal("faction_message_received",
		data.get("sender_name", "Unknown"),
		data.get("message", ""),
		int(data.get("timestamp", 0))
	)

func _on_faction_application(data: Dictionary) -> void:
	if local_role != ROLE_LEADER and local_role != ROLE_OFFICER:
		return
	var entry: Dictionary = {
		"player_id":    data.get("player_id", ""),
		"player_name":  data.get("player_name", ""),
		"applied_unix": int(data.get("applied_unix", 0)),
		"message":      data.get("message", "")
	}
	pending_applications.append(entry)
	emit_signal("application_received", entry["player_id"], entry["player_name"])

func _on_faction_invite(data: Dictionary) -> void:
	var entry: Dictionary = {
		"faction_id":    data.get("faction_id", ""),
		"faction_name":  data.get("faction_name", ""),
		"inviter_name":  data.get("inviter_name", ""),
		"expires_unix":  int(data.get("expires_unix", 0))
	}
	pending_invites.append(entry)
	emit_signal("invite_received", entry["faction_id"], entry["faction_name"], entry["inviter_name"])

func _on_faction_stats_update(data: Dictionary) -> void:
	var fid: String = data.get("faction_id", "")
	if fid == "":
		return
	var stats: Dictionary = {
		"territory_count":       int(data.get("territory_count", 0)),
		"total_building_value":  int(data.get("total_building_value", 0)),
		"member_count":          int(data.get("member_count", 0)),
		"war_wins":              int(data.get("war_wins", 0)),
		"treasury":              int(data.get("treasury", 0))
	}
	if all_factions.has(fid):
		all_factions[fid].merge(stats, true)
	if fid == local_faction.get("id", ""):
		local_faction.merge(stats, true)
		emit_signal("faction_updated", local_faction)
	emit_signal("faction_stats_updated", fid, stats)

func _on_district_factions(data: Dictionary) -> void:
	var district_id: String = data.get("district_id", "")
	var factions: Array    = data.get("factions", [])
	for f in factions:
		var fid: String = f.get("id", "")
		if fid != "":
			all_factions[fid] = f
	emit_signal("district_factions_updated", district_id, factions)

func _on_faction_kick(data: Dictionary) -> void:
	## Server notifies the local player they have been kicked or banned.
	var socket_node: Node = get_node_or_null("/root/SocketIOClient")
	var local_sid: String = socket_node.sid if socket_node != null else ""
	if data.get("player_id", "") != local_sid:
		return
	local_faction = {}
	local_role    = ""
	emit_signal("faction_updated", {})
	emit_signal("members_updated", [])

# ── Internal helpers ───────────────────────────────────────────────────────────

## Determines the local player's role from the current local_faction state.
func _compute_local_role() -> String:
	if local_faction.is_empty():
		return ""
	var socket_node: Node = get_node_or_null("/root/SocketIOClient")
	if socket_node == null:
		return ROLE_MEMBER
	var sid: String = socket_node.sid
	if sid == local_faction.get("leader_id", ""):
		return ROLE_LEADER
	var officers: Array = local_faction.get("officers", [])
	if officers.has(sid):
		return ROLE_OFFICER
	return ROLE_MEMBER
