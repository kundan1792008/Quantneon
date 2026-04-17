## SeasonSystem — 30-day competitive season management with Hall of Fame.
##
## Features:
##   • Seasons last SEASON_DURATION_DAYS (30 days).  Server is authoritative on start/end.
##   • At season end: all territory is reset, badges awarded to top factions,
##     exclusive building skins and faction banner customisation unlocked.
##   • Hall of Fame: permanent per-season record of winners, persisted server-side and
##     cached locally.
##   • Faction leaderboard refreshed every LEADERBOARD_POLL_INTERVAL seconds and on demand.
##   • Season score = territory_count * 50 + war_wins * 200 + total_building_value / 100.
##
## Autoloaded as /root/SeasonSystem.

extends Node

# ── Constants ──────────────────────────────────────────────────────────────────

## Length of a full season in days.
const SEASON_DURATION_DAYS: int = 30

## How often (seconds) the faction leaderboard is refreshed from the server.
const LEADERBOARD_POLL_INTERVAL: float = 120.0

## Maximum number of Hall of Fame seasons stored locally.
const HOF_MAX_ENTRIES: int = 20

## Top N factions that receive season badges.
const BADGE_RECIPIENTS: int = 3

## Season score weighting factors.
const SCORE_WEIGHT_TERRITORY: int   = 50
const SCORE_WEIGHT_WAR_WINS:  int   = 200
const SCORE_WEIGHT_BLDG_VAL:  float = 0.01   # per QT of building value

## Exclusive reward type identifiers.
const REWARD_SKIN:   String = "building_skin"
const REWARD_BANNER: String = "faction_banner"
const REWARD_BADGE:  String = "season_badge"

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when the current season metadata updates (number, start/end dates).
signal season_updated(season_data: Dictionary)

## Emitted whenever the faction leaderboard refreshes.
signal leaderboard_updated(entries: Array)

## Emitted when a season ends and rewards are distributed.
signal season_ended(season_number: int, winners: Array)

## Emitted when a new season starts after the end-of-season reset.
signal season_started(season_number: int, start_unix: int)

## Emitted when a Hall of Fame entry is added.
signal hall_of_fame_updated(hof: Array)

## Emitted when the local player/faction earns a reward.
signal reward_earned(reward_type: String, reward_data: Dictionary)

# ── State ─────────────────────────────────────────────────────────────────────

## Current season number (1-indexed). 0 = not yet initialised.
var current_season_number: int = 0

## Unix timestamp of when the current season started.
var season_start_unix: int = 0

## Unix timestamp of when the current season ends.
var season_end_unix: int = 0

## Whether the season-end ceremony is currently in progress.
var is_season_ending: bool = false

## The faction leaderboard for the current season.
## Each entry: {faction_id, faction_name, season_score, territory_count, war_wins,
##              total_building_value, member_count, rank}
var faction_leaderboard: Array = []

## Hall of Fame: Array of season records.
## Each record: {season_number, start_date, end_date, winners: [{rank, faction_id, faction_name,
##   season_score, badge_color}], total_factions, total_wars}
var hall_of_fame: Array = []

## Rewards earned this session by the local faction.
## Each entry: {reward_type, season_number, faction_id, data}
var earned_rewards: Array = []

## Internal poll timer.
var _poll_timer: float = 0.0

## Socket reference.
var _socket: Node = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_resolve_socket()
	print("[SeasonSystem] Ready.")

func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= LEADERBOARD_POLL_INTERVAL:
		_poll_timer = 0.0
		request_leaderboard()
	_check_season_end()

# ── Socket helpers ─────────────────────────────────────────────────────────────

func _resolve_socket() -> void:
	_socket = get_node_or_null("/root/SocketIOClient")
	if _socket == null:
		get_tree().create_timer(1.0).timeout.connect(_resolve_socket)
		return
	_socket.on_event("season_state",       _on_season_state)
	_socket.on_event("season_leaderboard", _on_season_leaderboard)
	_socket.on_event("season_end",         _on_season_end)
	_socket.on_event("season_start",       _on_season_start)
	_socket.on_event("hall_of_fame",       _on_hall_of_fame)
	_socket.on_event("season_reward",      _on_season_reward)
	print("[SeasonSystem] Socket events registered.")
	# Request current state immediately.
	_emit("get_season_state", {})
	request_leaderboard()

func _emit(event: String, payload: Dictionary) -> void:
	if _socket == null:
		push_warning("[SeasonSystem] Cannot emit '%s' — socket unavailable." % event)
		return
	_socket.send_event(event, payload)

# ── Public API ────────────────────────────────────────────────────────────────

## Request the latest faction leaderboard from the server.
func request_leaderboard() -> void:
	_emit("get_season_leaderboard", {"season_number": current_season_number})

## Request the full Hall of Fame from the server.
func request_hall_of_fame() -> void:
	_emit("get_hall_of_fame", {})

## Returns days remaining in the current season (0 if unknown or ended).
func days_remaining_in_season() -> int:
	if season_end_unix == 0:
		return 0
	var now: int  = int(Time.get_unix_time_from_system())
	var secs: int = max(0, season_end_unix - now)
	return secs / 86400

## Returns hours remaining in the current season.
func hours_remaining_in_season() -> int:
	if season_end_unix == 0:
		return 0
	var now: int  = int(Time.get_unix_time_from_system())
	var secs: int = max(0, season_end_unix - now)
	return secs / 3600

## Returns a human-readable countdown string "Xd Xh Xm".
func format_season_countdown() -> String:
	if season_end_unix == 0:
		return "Unknown"
	var now: int   = int(Time.get_unix_time_from_system())
	var secs: int  = max(0, season_end_unix - now)
	var days: int  = secs / 86400
	var hours: int = (secs % 86400) / 3600
	var mins: int  = (secs % 3600) / 60
	return "%dd %dh %dm" % [days, hours, mins]

## Calculate an aggregate season score for a faction stat snapshot.
## Returns integer score. Server score is authoritative; this is for preview.
func calculate_season_score(territory_count: int, war_wins: int, total_building_value: int) -> int:
	return (territory_count * SCORE_WEIGHT_TERRITORY) \
		 + (war_wins        * SCORE_WEIGHT_WAR_WINS) \
		 + int(float(total_building_value) * SCORE_WEIGHT_BLDG_VAL)

## Returns the rank (1-indexed) of a faction in the current leaderboard, or 0 if not present.
func get_faction_rank(faction_id: String) -> int:
	for entry in faction_leaderboard:
		if entry.get("faction_id", "") == faction_id:
			return int(entry.get("rank", 0))
	return 0

## Returns the Hall of Fame entry for a specific season number, or empty dict.
func get_hof_season(season_number: int) -> Dictionary:
	for record in hall_of_fame:
		if int(record.get("season_number", -1)) == season_number:
			return record
	return {}

## Returns the faction with the highest season score, or empty dict.
func get_current_leader() -> Dictionary:
	if faction_leaderboard.is_empty():
		return {}
	return faction_leaderboard[0]

# ── Internal: season-end check ────────────────────────────────────────────────

func _check_season_end() -> void:
	if season_end_unix == 0 or is_season_ending:
		return
	var now: int = int(Time.get_unix_time_from_system())
	if now >= season_end_unix:
		is_season_ending = true
		# The server is authoritative; this local flag prevents repeated triggers.
		# A "season_end" socket event will arrive shortly confirming the end.
		print("[SeasonSystem] Season %d end detected locally; awaiting server confirmation." % current_season_number)

# ── Socket event handlers ──────────────────────────────────────────────────────

func _on_season_state(data: Dictionary) -> void:
	current_season_number = int(data.get("season_number", 0))
	season_start_unix     = int(data.get("start_unix", 0))
	season_end_unix       = int(data.get("end_unix", 0))
	is_season_ending      = false
	emit_signal("season_updated", data)
	print("[SeasonSystem] Season %d  start=%d end=%d" % [
		current_season_number, season_start_unix, season_end_unix])

func _on_season_leaderboard(data: Dictionary) -> void:
	var raw_entries: Array = data.get("entries", [])
	faction_leaderboard.clear()
	for i in range(raw_entries.size()):
		var entry: Dictionary = raw_entries[i]
		entry["rank"] = i + 1
		# Compute local score if server didn't provide one.
		if not entry.has("season_score"):
			entry["season_score"] = calculate_season_score(
				int(entry.get("territory_count", 0)),
				int(entry.get("war_wins", 0)),
				int(entry.get("total_building_value", 0))
			)
		faction_leaderboard.append(entry)
	emit_signal("leaderboard_updated", faction_leaderboard)

func _on_season_end(data: Dictionary) -> void:
	is_season_ending = true
	var season_num: int = int(data.get("season_number", current_season_number))
	var winners: Array  = data.get("winners", [])

	# Build HOF record.
	var hof_record: Dictionary = {
		"season_number":  season_num,
		"start_date":     _unix_to_date(season_start_unix),
		"end_date":       _unix_to_date(int(Time.get_unix_time_from_system())),
		"winners":        _build_hof_winners(winners),
		"total_factions": int(data.get("total_factions", faction_leaderboard.size())),
		"total_wars":     int(data.get("total_wars", 0))
	}
	_add_hof_record(hof_record)
	emit_signal("season_ended", season_num, winners)
	print("[SeasonSystem] Season %d ended. HOF record saved." % season_num)

func _on_season_start(data: Dictionary) -> void:
	current_season_number = int(data.get("season_number", current_season_number + 1))
	season_start_unix     = int(data.get("start_unix", int(Time.get_unix_time_from_system())))
	season_end_unix       = season_start_unix + SEASON_DURATION_DAYS * 86400
	is_season_ending      = false
	faction_leaderboard.clear()
	emit_signal("season_started", current_season_number, season_start_unix)
	emit_signal("season_updated", {
		"season_number": current_season_number,
		"start_unix":    season_start_unix,
		"end_unix":      season_end_unix
	})
	print("[SeasonSystem] Season %d started." % current_season_number)

func _on_hall_of_fame(data: Dictionary) -> void:
	var records: Array = data.get("records", [])
	hall_of_fame.clear()
	for r in records:
		hall_of_fame.append(r)
	# Keep only the most recent HOF_MAX_ENTRIES.
	if hall_of_fame.size() > HOF_MAX_ENTRIES:
		hall_of_fame = hall_of_fame.slice(hall_of_fame.size() - HOF_MAX_ENTRIES)
	emit_signal("hall_of_fame_updated", hall_of_fame)

func _on_season_reward(data: Dictionary) -> void:
	var reward_type: String = data.get("reward_type", "")
	var reward_data: Dictionary = data.get("data", {})
	var entry: Dictionary = {
		"reward_type":    reward_type,
		"season_number":  current_season_number,
		"faction_id":     data.get("faction_id", ""),
		"data":           reward_data
	}
	earned_rewards.append(entry)
	emit_signal("reward_earned", reward_type, reward_data)
	print("[SeasonSystem] Reward earned: %s — %s" % [reward_type, str(reward_data)])

# ── Internal helpers ───────────────────────────────────────────────────────────

func _add_hof_record(record: Dictionary) -> void:
	hall_of_fame.append(record)
	if hall_of_fame.size() > HOF_MAX_ENTRIES:
		hall_of_fame = hall_of_fame.slice(1)
	emit_signal("hall_of_fame_updated", hall_of_fame)

func _build_hof_winners(raw_winners: Array) -> Array:
	var result: Array = []
	var badge_colors: Array = [
		Color(1.0, 0.85, 0.0),  # Gold   (rank 1)
		Color(0.8, 0.8, 0.8),  # Silver (rank 2)
		Color(0.8, 0.5, 0.2)   # Bronze (rank 3)
	]
	for i in range(min(raw_winners.size(), BADGE_RECIPIENTS)):
		var w: Dictionary = raw_winners[i]
		result.append({
			"rank":          i + 1,
			"faction_id":    w.get("faction_id", ""),
			"faction_name":  w.get("faction_name", "?"),
			"season_score":  int(w.get("season_score", 0)),
			"territory_count": int(w.get("territory_count", 0)),
			"war_wins":      int(w.get("war_wins", 0)),
			"badge_color":   badge_colors[i]
		})
	return result

func _unix_to_date(unix: int) -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [dt["year"], dt["month"], dt["day"]]
