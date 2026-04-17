## TerritoryWar — Faction vs. Faction territory control warfare.
##
## Mechanics:
##   • Declare war on an adjacent territory (costs WAR_DECLARATION_COST tokens).
##   • War lasts WAR_DURATION_SECS (48 hours).  Resolved server-side.
##   • Activity score = buildings_built * 10 + player_time_minutes + mini_game_wins * 50.
##   • Winner captures the territory; loser's buildings enter a "damaged" visual state.
##   • After a war the zone enters a ceasefire for CEASEFIRE_DURATION_SECS (72 hours).
##   • Live scores are pushed by the server every SCORE_UPDATE_INTERVAL seconds.
##
## Autoloaded as /root/TerritoryWar.

extends Node

# ── Constants ──────────────────────────────────────────────────────────────────

## Quant-token cost to declare war on an adjacent zone.
const WAR_DECLARATION_COST: int = 1000

## War duration in seconds (48 hours).
const WAR_DURATION_SECS: int = 48 * 3600

## Ceasefire period in seconds after a war resolves (72 hours).
const CEASEFIRE_DURATION_SECS: int = 72 * 3600

## Maximum number of simultaneous active wars a single faction may participate in.
const MAX_ACTIVE_WARS_PER_FACTION: int = 2

## Activity score weights.
const SCORE_WEIGHT_BUILDING: int  = 10   # points per building constructed
const SCORE_WEIGHT_TIME_MIN: int  = 1    # points per player-minute in zone
const SCORE_WEIGHT_MINI_GAME: int = 50   # points per mini-game win in zone

## Server push interval (seconds) for live score updates.
const SCORE_UPDATE_INTERVAL: float = 60.0

# ── War status constants ───────────────────────────────────────────────────────

const WAR_STATUS_ACTIVE:    String = "active"
const WAR_STATUS_CEASEFIRE: String = "ceasefire"
const WAR_STATUS_RESOLVED:  String = "resolved"

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when a new war is declared (either our faction or another in the district).
signal war_declared(war_data: Dictionary)

## Emitted every score update for an active war.
signal war_scores_updated(war_id: String, attacker_score: int, defender_score: int)

## Emitted when a war concludes and a winner is determined.
signal war_resolved(war_id: String, winner_faction_id: String, loser_faction_id: String)

## Emitted when a ceasefire begins on a zone.
signal ceasefire_started(zone_id: String, expires_unix: int)

## Emitted when a ceasefire expires and the zone can be contested again.
signal ceasefire_ended(zone_id: String)

## Emitted when zone ownership changes (territory captured).
signal territory_captured(zone_id: String, new_owner_faction_id: String, prev_owner_faction_id: String)

## Emitted when loser buildings enter damaged visual state after a war.
signal buildings_damaged(zone_id: String, faction_id: String)

# ── State ─────────────────────────────────────────────────────────────────────

## All known active / recently resolved wars keyed by war_id.
## Each war dict has:
##   war_id, attacker_faction_id, defender_faction_id, zone_id,
##   declared_unix, expires_unix, status, attacker_score, defender_score.
var active_wars: Dictionary = {}  # {war_id: Dictionary}

## Zone ceasefire registry.  {zone_id: ceasefire_expires_unix}
var ceasefires: Dictionary = {}

## Zone ownership registry. {zone_id: faction_id | ""}
var zone_owners: Dictionary = {}

## Known adjacent zone relationships. {zone_id: [adjacent_zone_id, ...]}
var zone_adjacency: Dictionary = {}

## Local countdown timers for wars we are tracking (seconds remaining).
var _war_timers: Dictionary = {}  # {war_id: float}

## Socket reference.
var _socket: Node = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_resolve_socket()
	print("[TerritoryWar] Ready.")

func _process(delta: float) -> void:
	_tick_war_timers(delta)
	_tick_ceasefire_timers()

# ── Socket helpers ─────────────────────────────────────────────────────────────

func _resolve_socket() -> void:
	_socket = get_node_or_null("/root/SocketIOClient")
	if _socket == null:
		get_tree().create_timer(1.0).timeout.connect(_resolve_socket)
		return
	_socket.on_event("war_declared",      _on_war_declared)
	_socket.on_event("war_score_update",  _on_war_score_update)
	_socket.on_event("war_resolved",      _on_war_resolved)
	_socket.on_event("ceasefire_update",  _on_ceasefire_update)
	_socket.on_event("zone_ownership",    _on_zone_ownership)
	_socket.on_event("territory_update",  _on_territory_update_compat)
	_socket.on_event("war_state_sync",    _on_war_state_sync)
	print("[TerritoryWar] Socket events registered.")

func _emit(event: String, payload: Dictionary) -> void:
	if _socket == null:
		push_warning("[TerritoryWar] Cannot emit '%s' — socket unavailable." % event)
		return
	_socket.send_event(event, payload)

# ── Public API: War declaration ────────────────────────────────────────────────

## Attempt to declare war on the given zone from the attacker faction.
## Requires the zone to be adjacent to a zone already owned by the attacker.
## Costs WAR_DECLARATION_COST Quant tokens (validated server-side).
func declare_war(attacker_faction_id: String, target_zone_id: String) -> void:
	if _is_zone_in_ceasefire(target_zone_id):
		push_warning("[TerritoryWar] Zone '%s' is in ceasefire." % target_zone_id)
		return
	if _count_active_wars_for_faction(attacker_faction_id) >= MAX_ACTIVE_WARS_PER_FACTION:
		push_warning("[TerritoryWar] Faction already at max active wars (%d)." % MAX_ACTIVE_WARS_PER_FACTION)
		return
	_emit("declare_war", {
		"attacker_faction_id": attacker_faction_id,
		"zone_id":             target_zone_id
	})

## Forfeit an active war. The declaring faction loses the zone and forfeits the fee.
func forfeit_war(war_id: String, faction_id: String) -> void:
	if not active_wars.has(war_id):
		push_warning("[TerritoryWar] Unknown war_id: %s" % war_id)
		return
	_emit("war_forfeit", {"war_id": war_id, "faction_id": faction_id})

# ── Public API: Queries ────────────────────────────────────────────────────────

## Returns the active war dict for a zone, or empty dict if no active war.
func get_war_for_zone(zone_id: String) -> Dictionary:
	for war in active_wars.values():
		if war.get("zone_id", "") == zone_id and war.get("status", "") == WAR_STATUS_ACTIVE:
			return war
	return {}

## Returns all wars (active + ceasefire phase) involving a given faction.
func get_wars_for_faction(faction_id: String) -> Array:
	var result: Array = []
	for war in active_wars.values():
		if war.get("attacker_faction_id", "") == faction_id \
		or war.get("defender_faction_id", "") == faction_id:
			result.append(war)
	return result

## Returns true if the given zone is currently under ceasefire.
func is_zone_in_ceasefire(zone_id: String) -> bool:
	return _is_zone_in_ceasefire(zone_id)

## Returns seconds until the ceasefire for zone_id expires, or 0 if no ceasefire.
func ceasefire_seconds_remaining(zone_id: String) -> int:
	if not ceasefires.has(zone_id):
		return 0
	var now: int = int(Time.get_unix_time_from_system())
	return max(0, ceasefires[zone_id] - now)

## Returns seconds until the war expires (client-side estimate), or 0 if not active.
func war_seconds_remaining(war_id: String) -> int:
	if not active_wars.has(war_id):
		return 0
	var war: Dictionary = active_wars[war_id]
	var now: int = int(Time.get_unix_time_from_system())
	return max(0, int(war.get("expires_unix", 0)) - now)

## Returns the current activity score for a faction in the given war.
func get_score(war_id: String, faction_id: String) -> int:
	if not active_wars.has(war_id):
		return 0
	var war: Dictionary = active_wars[war_id]
	if faction_id == war.get("attacker_faction_id", ""):
		return int(war.get("attacker_score", 0))
	if faction_id == war.get("defender_faction_id", ""):
		return int(war.get("defender_score", 0))
	return 0

## Returns the faction ID currently owning the given zone, or "" if neutral.
func get_zone_owner(zone_id: String) -> String:
	return zone_owners.get(zone_id, "")

## Returns a formatted human-readable time string (HH:MM:SS) for remaining seconds.
func format_time_remaining(total_secs: int) -> String:
	var h: int = total_secs / 3600
	var m: int = (total_secs % 3600) / 60
	var s: int = total_secs % 60
	return "%02d:%02d:%02d" % [h, m, s]

# ── Public API: Score contribution ────────────────────────────────────────────

## Notify the server about a new activity contribution for a war zone.
## activity_type: "building_built" | "player_time" | "mini_game_win"
## value: number of buildings, minutes, or wins.
func report_activity(war_id: String, faction_id: String, activity_type: String, value: int) -> void:
	_emit("war_activity", {
		"war_id":        war_id,
		"faction_id":    faction_id,
		"activity_type": activity_type,
		"value":         value
	})

## Calculate an activity score contribution locally (for display purposes only).
## Server is authoritative.
func calculate_score_contribution(buildings_built: int, player_minutes: int, mini_game_wins: int) -> int:
	return (buildings_built * SCORE_WEIGHT_BUILDING) \
		 + (player_minutes  * SCORE_WEIGHT_TIME_MIN) \
		 + (mini_game_wins  * SCORE_WEIGHT_MINI_GAME)

# ── Socket event handlers ──────────────────────────────────────────────────────

func _on_war_declared(data: Dictionary) -> void:
	var war_id: String = data.get("war_id", "")
	if war_id == "":
		return
	var war: Dictionary = {
		"war_id":               war_id,
		"attacker_faction_id":  data.get("attacker_faction_id", ""),
		"defender_faction_id":  data.get("defender_faction_id", ""),
		"zone_id":              data.get("zone_id", ""),
		"declared_unix":        int(data.get("declared_unix", 0)),
		"expires_unix":         int(data.get("expires_unix", 0)),
		"status":               WAR_STATUS_ACTIVE,
		"attacker_score":       0,
		"defender_score":       0
	}
	active_wars[war_id] = war
	_war_timers[war_id] = float(war_seconds_remaining(war_id))
	emit_signal("war_declared", war)
	print("[TerritoryWar] War declared: zone=%s att=%s def=%s" % [
		war["zone_id"], war["attacker_faction_id"], war["defender_faction_id"]])

func _on_war_score_update(data: Dictionary) -> void:
	var war_id: String = data.get("war_id", "")
	if not active_wars.has(war_id):
		return
	var war: Dictionary = active_wars[war_id]
	war["attacker_score"] = int(data.get("attacker_score", 0))
	war["defender_score"] = int(data.get("defender_score", 0))
	active_wars[war_id] = war
	emit_signal("war_scores_updated", war_id, war["attacker_score"], war["defender_score"])

func _on_war_resolved(data: Dictionary) -> void:
	var war_id: String          = data.get("war_id", "")
	var winner_id: String       = data.get("winner_faction_id", "")
	var loser_id: String        = data.get("loser_faction_id", "")
	var zone_id: String         = data.get("zone_id", "")
	var ceasefire_exp: int      = int(data.get("ceasefire_expires_unix", 0))

	if active_wars.has(war_id):
		active_wars[war_id]["status"] = WAR_STATUS_RESOLVED

	# Update ownership
	if zone_id != "" and winner_id != "":
		var prev_owner: String = zone_owners.get(zone_id, "")
		zone_owners[zone_id] = winner_id
		emit_signal("territory_captured", zone_id, winner_id, prev_owner)
		emit_signal("buildings_damaged", zone_id, loser_id)

	# Register ceasefire
	if ceasefire_exp > 0 and zone_id != "":
		ceasefires[zone_id] = ceasefire_exp
		emit_signal("ceasefire_started", zone_id, ceasefire_exp)

	emit_signal("war_resolved", war_id, winner_id, loser_id)
	_war_timers.erase(war_id)
	print("[TerritoryWar] War resolved: winner=%s loser=%s zone=%s" % [winner_id, loser_id, zone_id])

func _on_ceasefire_update(data: Dictionary) -> void:
	var zone_id: String   = data.get("zone_id", "")
	var expires_unix: int = int(data.get("expires_unix", 0))
	if zone_id == "":
		return
	if expires_unix == 0:
		ceasefires.erase(zone_id)
		emit_signal("ceasefire_ended", zone_id)
	else:
		ceasefires[zone_id] = expires_unix
		emit_signal("ceasefire_started", zone_id, expires_unix)

func _on_zone_ownership(data: Dictionary) -> void:
	var zone_id: String   = data.get("zone_id", "")
	var faction_id: String = data.get("faction_id", "")
	if zone_id == "":
		return
	var prev: String = zone_owners.get(zone_id, "")
	zone_owners[zone_id] = faction_id
	if prev != faction_id:
		emit_signal("territory_captured", zone_id, faction_id, prev)

func _on_territory_update_compat(data: Dictionary) -> void:
	## Compatibility shim for the legacy "territory_update" event already handled
	## by NetworkManager.  We just keep our local ownership table in sync.
	var zone_id: String   = data.get("zoneId", data.get("zone_id", ""))
	var faction_id: String = data.get("faction", data.get("faction_id", ""))
	if zone_id != "":
		zone_owners[zone_id] = faction_id

func _on_war_state_sync(data: Dictionary) -> void:
	## Full war-state bulk sync from server (e.g., after reconnect).
	var wars: Array      = data.get("wars", [])
	var cf_list: Array   = data.get("ceasefires", [])
	var owners: Array    = data.get("zone_owners", [])
	active_wars.clear()
	for w in wars:
		var wid: String = w.get("war_id", "")
		if wid != "":
			active_wars[wid] = w
			if w.get("status", "") == WAR_STATUS_ACTIVE:
				_war_timers[wid] = float(war_seconds_remaining(wid))
	for cf in cf_list:
		var zid: String = cf.get("zone_id", "")
		if zid != "":
			ceasefires[zid] = int(cf.get("expires_unix", 0))
	for o in owners:
		var zid: String = o.get("zone_id", "")
		if zid != "":
			zone_owners[zid] = o.get("faction_id", "")

# ── Internal helpers ───────────────────────────────────────────────────────────

func _is_zone_in_ceasefire(zone_id: String) -> bool:
	if not ceasefires.has(zone_id):
		return false
	var now: int = int(Time.get_unix_time_from_system())
	return ceasefires[zone_id] > now

func _count_active_wars_for_faction(faction_id: String) -> int:
	var count: int = 0
	for war in active_wars.values():
		if war.get("status", "") == WAR_STATUS_ACTIVE:
			if war.get("attacker_faction_id", "") == faction_id \
			or war.get("defender_faction_id", "") == faction_id:
				count += 1
	return count

func _tick_war_timers(delta: float) -> void:
	for war_id in _war_timers.keys():
		_war_timers[war_id] = max(0.0, _war_timers[war_id] - delta)

func _tick_ceasefire_timers() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var expired: Array = []
	for zone_id in ceasefires:
		if ceasefires[zone_id] <= now:
			expired.append(zone_id)
	for zone_id in expired:
		ceasefires.erase(zone_id)
		emit_signal("ceasefire_ended", zone_id)
