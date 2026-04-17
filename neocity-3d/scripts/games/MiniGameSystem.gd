## MiniGameSystem — Three war-point mini-games playable during active faction wars.
##
## Games available:
##   • RACE   — Drive or run through checkpoints in the war zone before time expires.
##   • BUILD  — Fastest player to construct a structure earns top points.
##   • DEFEND — Survive increasingly difficult NPC waves; score based on waves cleared.
##
## Rules:
##   • Mini-games can only be started when a war is active in the local zone.
##   • Each game awards WAR_POINTS_MIN to WAR_POINTS_MAX war points to the
##     winner's faction activity score.
##   • Points are reported to TerritoryWar which forwards them to the server.
##
## Autoloaded as /root/MiniGameSystem.

extends Node

# ── Constants ──────────────────────────────────────────────────────────────────

const WAR_POINTS_MIN: int = 100
const WAR_POINTS_MAX: int = 500

## Duration limits (seconds) for each game.
const RACE_TIME_LIMIT_SECS:    float = 180.0  # 3 minutes
const BUILD_TIME_LIMIT_SECS:   float = 120.0  # 2 minutes
const DEFEND_WAVE_DURATION_SECS: float = 60.0 # 1 minute per wave

const DEFEND_MAX_WAVES: int = 5

## NPC count per defend wave (scales up each wave).
const DEFEND_BASE_NPCS: int = 3
const DEFEND_NPC_SCALE:  int = 2  # additional NPCs per wave

## Race checkpoint reward (points per checkpoint hit before finish).
const RACE_POINTS_PER_CHECKPOINT: int = 10

## Build complexity tiers → points mapping.
const BUILD_TIER_POINTS: Dictionary = {
	1: 100,   # simple 1-block structure
	2: 200,   # medium 3-block structure
	3: 350,   # complex 6-block structure
	4: 500    # masterpiece 10+ block structure
}

# ── Game type constants ────────────────────────────────────────────────────────

const GAME_RACE:   String = "race"
const GAME_BUILD:  String = "build"
const GAME_DEFEND: String = "defend"

# ── Game state constants ───────────────────────────────────────────────────────

const STATE_IDLE:      String = "idle"
const STATE_COUNTDOWN: String = "countdown"
const STATE_RUNNING:   String = "running"
const STATE_FINISHED:  String = "finished"

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when a mini-game session starts.
signal game_started(game_type: String, war_id: String)

## Emitted each second of a running game with remaining time.
signal game_tick(game_type: String, seconds_remaining: float)

## Emitted when the local player hits a race checkpoint.
signal checkpoint_hit(checkpoint_index: int, total_checkpoints: int)

## Emitted when a build structure is completed.
signal build_completed(tier: int, time_taken: float)

## Emitted when a defend wave starts.
signal defend_wave_started(wave_number: int, npc_count: int)

## Emitted when a defend wave is cleared.
signal defend_wave_cleared(wave_number: int, survivors: int)

## Emitted when the local player is eliminated in defend mode.
signal defend_player_eliminated(wave_number: int)

## Emitted when a game session ends with the result.
## result: {game_type, war_id, faction_id, points_earned, rank, personal_best}
signal game_ended(result: Dictionary)

## Emitted when war points are awarded and forwarded to TerritoryWar.
signal war_points_awarded(war_id: String, faction_id: String, points: int, game_type: String)

# ── State ─────────────────────────────────────────────────────────────────────

## Current game session.
var current_game_type: String  = ""
var current_game_state: String = STATE_IDLE
var current_war_id: String     = ""
var current_faction_id: String = ""
var current_zone_id: String    = ""

## Race state.
var _race_checkpoints: Array   = []  # [{position: Vector3, hit: bool}]
var _race_checkpoints_hit: int = 0
var _race_time_elapsed: float  = 0.0
var _race_finished: bool       = false

## Build state.
var _build_target_tier: int   = 1
var _build_blocks_placed: int = 0
var _build_time_elapsed: float = 0.0
var _build_required_blocks: int = 1

## Defend state.
var _defend_current_wave: int   = 0
var _defend_npcs_alive: int     = 0
var _defend_wave_timer: float   = 0.0
var _defend_player_alive: bool  = true
var _defend_waves_cleared: int  = 0

## Shared timer.
var _game_timer: float = 0.0
var _game_time_limit: float = 0.0

## Personal-best records. {game_type: {points, time}}
var personal_bests: Dictionary = {}

## Leaderboard for current session. [{player_id, player_name, points, finish_time}]
var session_leaderboard: Array = []

## Socket reference.
var _socket: Node = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_resolve_socket()
	print("[MiniGameSystem] Ready.")

func _process(delta: float) -> void:
	if current_game_state != STATE_RUNNING:
		return
	match current_game_type:
		GAME_RACE:   _process_race(delta)
		GAME_BUILD:  _process_build(delta)
		GAME_DEFEND: _process_defend(delta)

# ── Socket helpers ─────────────────────────────────────────────────────────────

func _resolve_socket() -> void:
	_socket = get_node_or_null("/root/SocketIOClient")
	if _socket == null:
		get_tree().create_timer(1.0).timeout.connect(_resolve_socket)
		return
	_socket.on_event("minigame_start",     _on_server_game_start)
	_socket.on_event("minigame_result",    _on_server_game_result)
	_socket.on_event("minigame_leaderboard", _on_server_leaderboard)
	_socket.on_event("defend_npc_spawn",   _on_defend_npc_spawn)
	print("[MiniGameSystem] Socket events registered.")

func _emit(event: String, payload: Dictionary) -> void:
	if _socket == null:
		push_warning("[MiniGameSystem] Cannot emit '%s' — socket unavailable." % event)
		return
	_socket.send_event(event, payload)

# ── Public API: Session management ────────────────────────────────────────────

## Attempt to start a mini-game.  Fails if no active war in the zone.
func start_game(game_type: String, war_id: String, faction_id: String, zone_id: String) -> bool:
	if current_game_state != STATE_IDLE:
		push_warning("[MiniGameSystem] A game is already in progress.")
		return false
	var tw: Node = get_node_or_null("/root/TerritoryWar")
	if tw == null:
		push_warning("[MiniGameSystem] TerritoryWar not found.")
		return false
	var war: Dictionary = tw.active_wars.get(war_id, {})
	if war.get("status", "") != "active":
		push_warning("[MiniGameSystem] No active war for war_id: %s" % war_id)
		return false

	current_game_type  = game_type
	current_war_id     = war_id
	current_faction_id = faction_id
	current_zone_id    = zone_id
	current_game_state = STATE_COUNTDOWN
	session_leaderboard.clear()

	_emit("minigame_join", {
		"game_type":  game_type,
		"war_id":     war_id,
		"faction_id": faction_id,
		"zone_id":    zone_id
	})
	# Server will echo back a "minigame_start" when all players are ready.
	return true

## Abort the current game (forfeits points).
func abort_game() -> void:
	if current_game_state == STATE_IDLE:
		return
	_emit("minigame_abort", {
		"game_type": current_game_type,
		"war_id":    current_war_id
	})
	_reset_state()

# ── Public API: Race ──────────────────────────────────────────────────────────

## Called by the player controller or trigger zone when a checkpoint is entered.
func hit_checkpoint(checkpoint_index: int) -> void:
	if current_game_type != GAME_RACE or current_game_state != STATE_RUNNING:
		return
	if checkpoint_index >= _race_checkpoints.size():
		return
	var cp: Dictionary = _race_checkpoints[checkpoint_index]
	if cp.get("hit", false):
		return  # Already counted.
	_race_checkpoints[checkpoint_index]["hit"] = true
	_race_checkpoints_hit += 1
	emit_signal("checkpoint_hit", _race_checkpoints_hit, _race_checkpoints.size())
	_emit("minigame_checkpoint", {
		"war_id":           current_war_id,
		"checkpoint_index": checkpoint_index
	})
	# Last checkpoint = finish line.
	if _race_checkpoints_hit >= _race_checkpoints.size():
		_finish_race()

# ── Public API: Build ──────────────────────────────────────────────────────────

## Called by the building system when a block is placed during a build game.
func register_block_placed() -> void:
	if current_game_type != GAME_BUILD or current_game_state != STATE_RUNNING:
		return
	_build_blocks_placed += 1
	_emit("minigame_block_placed", {
		"war_id":        current_war_id,
		"blocks_placed": _build_blocks_placed
	})
	if _build_blocks_placed >= _build_required_blocks:
		_finish_build()

# ── Public API: Defend ────────────────────────────────────────────────────────

## Called by the NPC/combat system when the player takes lethal damage.
func notify_player_eliminated() -> void:
	if current_game_type != GAME_DEFEND or current_game_state != STATE_RUNNING:
		return
	_defend_player_alive = false
	emit_signal("defend_player_eliminated", _defend_current_wave)
	_finish_defend(false)

## Called by combat system when an NPC in the defend game is killed.
func notify_npc_killed() -> void:
	if current_game_type != GAME_DEFEND or current_game_state != STATE_RUNNING:
		return
	_defend_npcs_alive = max(0, _defend_npcs_alive - 1)
	if _defend_npcs_alive == 0:
		_clear_defend_wave()

# ── Public API: Queries ────────────────────────────────────────────────────────

## Returns true if a game is currently running.
func is_game_active() -> bool:
	return current_game_state == STATE_RUNNING or current_game_state == STATE_COUNTDOWN

## Returns seconds remaining in the current game (client estimate).
func time_remaining() -> float:
	return max(0.0, _game_time_limit - _game_timer)

## Returns the personal-best point total for a given game type.
func get_personal_best(game_type: String) -> int:
	return personal_bests.get(game_type, {}).get("points", 0)

# ── Game initialization ────────────────────────────────────────────────────────

func _init_race(data: Dictionary) -> void:
	_race_checkpoints.clear()
	_race_checkpoints_hit = 0
	_race_time_elapsed    = 0.0
	_race_finished        = false
	var raw_cps: Array = data.get("checkpoints", [])
	for cp_data in raw_cps:
		_race_checkpoints.append({
			"position": Vector3(
				float(cp_data.get("x", 0)),
				float(cp_data.get("y", 0)),
				float(cp_data.get("z", 0))
			),
			"hit": false
		})
	_game_time_limit = float(data.get("time_limit", RACE_TIME_LIMIT_SECS))

func _init_build(data: Dictionary) -> void:
	_build_time_elapsed     = 0.0
	_build_blocks_placed    = 0
	_build_target_tier      = int(data.get("tier", 1))
	_build_required_blocks  = _blocks_for_tier(_build_target_tier)
	_game_time_limit        = float(data.get("time_limit", BUILD_TIME_LIMIT_SECS))

func _init_defend(data: Dictionary) -> void:
	_defend_current_wave  = 0
	_defend_waves_cleared = 0
	_defend_player_alive  = true
	_defend_npcs_alive    = 0
	_defend_wave_timer    = 0.0
	_game_time_limit      = DEFEND_MAX_WAVES * DEFEND_WAVE_DURATION_SECS
	_start_defend_wave()

# ── Race processing ────────────────────────────────────────────────────────────

func _process_race(delta: float) -> void:
	_game_timer        += delta
	_race_time_elapsed += delta
	var remaining: float = max(0.0, _game_time_limit - _game_timer)
	emit_signal("game_tick", GAME_RACE, remaining)
	if remaining <= 0.0 and not _race_finished:
		_finish_race()

func _finish_race() -> void:
	if _race_finished:
		return
	_race_finished = true
	var completion_ratio: float = float(_race_checkpoints_hit) / max(1, _race_checkpoints.size())
	var time_bonus: float       = max(0.0, 1.0 - (_race_time_elapsed / _game_time_limit))
	var raw_points: float       = (float(WAR_POINTS_MAX) * completion_ratio) * (0.5 + 0.5 * time_bonus)
	raw_points += float(_race_checkpoints_hit * RACE_POINTS_PER_CHECKPOINT)
	var points: int = clamp(int(raw_points), WAR_POINTS_MIN if completion_ratio > 0.0 else 0, WAR_POINTS_MAX)
	_submit_result(points, _race_time_elapsed)

# ── Build processing ───────────────────────────────────────────────────────────

func _process_build(delta: float) -> void:
	_game_timer         += delta
	_build_time_elapsed += delta
	var remaining: float = max(0.0, _game_time_limit - _game_timer)
	emit_signal("game_tick", GAME_BUILD, remaining)
	if remaining <= 0.0:
		_finish_build()

func _finish_build() -> void:
	current_game_state = STATE_FINISHED
	var completion: bool   = _build_blocks_placed >= _build_required_blocks
	var base_pts: int      = BUILD_TIER_POINTS.get(_build_target_tier, WAR_POINTS_MIN)
	var time_ratio: float  = max(0.0, 1.0 - (_build_time_elapsed / _game_time_limit))
	var points: int        = int(float(base_pts) * (0.6 + 0.4 * time_ratio)) if completion else WAR_POINTS_MIN / 2
	emit_signal("build_completed", _build_target_tier, _build_time_elapsed)
	_submit_result(points, _build_time_elapsed)

# ── Defend processing ──────────────────────────────────────────────────────────

func _process_defend(delta: float) -> void:
	_game_timer       += delta
	_defend_wave_timer += delta
	var remaining: float = max(0.0, DEFEND_WAVE_DURATION_SECS - _defend_wave_timer)
	emit_signal("game_tick", GAME_DEFEND, remaining)
	if _defend_wave_timer >= DEFEND_WAVE_DURATION_SECS and _defend_npcs_alive > 0:
		# Time ran out on this wave — wave failed.
		_finish_defend(false)

func _start_defend_wave() -> void:
	_defend_current_wave += 1
	if _defend_current_wave > DEFEND_MAX_WAVES:
		_finish_defend(true)
		return
	_defend_wave_timer = 0.0
	var npc_count: int = DEFEND_BASE_NPCS + (_defend_current_wave - 1) * DEFEND_NPC_SCALE
	_defend_npcs_alive = npc_count
	emit_signal("defend_wave_started", _defend_current_wave, npc_count)
	_emit("minigame_wave_start", {
		"war_id":     current_war_id,
		"wave":       _defend_current_wave,
		"npc_count":  npc_count
	})

func _clear_defend_wave() -> void:
	_defend_waves_cleared += 1
	emit_signal("defend_wave_cleared", _defend_current_wave, 1)
	_emit("minigame_wave_cleared", {
		"war_id": current_war_id,
		"wave":   _defend_current_wave
	})
	if _defend_current_wave < DEFEND_MAX_WAVES:
		_start_defend_wave()
	else:
		_finish_defend(true)

func _finish_defend(survived: bool) -> void:
	current_game_state = STATE_FINISHED
	var wave_ratio: float = float(_defend_waves_cleared) / float(DEFEND_MAX_WAVES)
	var points: int = clamp(
		int(float(WAR_POINTS_MAX) * wave_ratio),
		WAR_POINTS_MIN if _defend_waves_cleared > 0 else 0,
		WAR_POINTS_MAX
	)
	if survived:
		points = WAR_POINTS_MAX
	_submit_result(points, _game_timer)

# ── Result submission ──────────────────────────────────────────────────────────

func _submit_result(points: int, time_taken: float) -> void:
	current_game_state = STATE_FINISHED
	_update_personal_best(current_game_type, points, time_taken)
	var result: Dictionary = {
		"game_type":    current_game_type,
		"war_id":       current_war_id,
		"faction_id":   current_faction_id,
		"zone_id":      current_zone_id,
		"points_earned": points,
		"time_taken":   time_taken,
		"personal_best": get_personal_best(current_game_type)
	}
	emit_signal("game_ended", result)
	# Report to TerritoryWar for activity score.
	if points > 0:
		var tw: Node = get_node_or_null("/root/TerritoryWar")
		if tw != null and tw.has_method("report_activity"):
			tw.report_activity(current_war_id, current_faction_id, "mini_game_win", 1)
		emit_signal("war_points_awarded", current_war_id, current_faction_id, points, current_game_type)
	_emit("minigame_result_submit", result)
	# Defer state reset so UI can read the result.
	get_tree().create_timer(1.0).timeout.connect(_reset_state)

func _update_personal_best(game_type: String, points: int, time_taken: float) -> void:
	var pb: Dictionary = personal_bests.get(game_type, {})
	if points > pb.get("points", 0):
		personal_bests[game_type] = {"points": points, "time": time_taken}

func _reset_state() -> void:
	current_game_type   = ""
	current_game_state  = STATE_IDLE
	current_war_id      = ""
	current_faction_id  = ""
	current_zone_id     = ""
	_game_timer         = 0.0
	_game_time_limit    = 0.0
	_race_checkpoints.clear()
	_race_checkpoints_hit  = 0
	_race_finished         = false
	_build_blocks_placed   = 0
	_build_target_tier     = 1
	_defend_current_wave   = 0
	_defend_waves_cleared  = 0
	_defend_npcs_alive     = 0
	_defend_player_alive   = true

# ── Socket event handlers ──────────────────────────────────────────────────────

func _on_server_game_start(data: Dictionary) -> void:
	var game_type: String = data.get("game_type", "")
	var war_id: String    = data.get("war_id", "")
	if game_type == "" or war_id != current_war_id:
		return
	current_game_state = STATE_RUNNING
	_game_timer        = 0.0
	match game_type:
		GAME_RACE:   _init_race(data)
		GAME_BUILD:  _init_build(data)
		GAME_DEFEND: _init_defend(data)
		_:
			push_warning("[MiniGameSystem] Unknown game type: %s" % game_type)
			return
	emit_signal("game_started", game_type, war_id)
	print("[MiniGameSystem] Game started: %s (war %s)" % [game_type, war_id])

func _on_server_game_result(data: Dictionary) -> void:
	## Server may push authoritative results that override local calculation.
	var war_id: String = data.get("war_id", "")
	if war_id != current_war_id:
		return
	var points: int = int(data.get("points_earned", 0))
	var result: Dictionary = {
		"game_type":     data.get("game_type", current_game_type),
		"war_id":        war_id,
		"faction_id":    current_faction_id,
		"points_earned": points,
		"time_taken":    float(data.get("time_taken", 0.0)),
		"rank":          int(data.get("rank", 0)),
		"personal_best": get_personal_best(current_game_type)
	}
	emit_signal("game_ended", result)
	if points > 0:
		emit_signal("war_points_awarded", war_id, current_faction_id, points, result["game_type"])

func _on_server_leaderboard(data: Dictionary) -> void:
	var war_id: String = data.get("war_id", "")
	if war_id != current_war_id:
		return
	session_leaderboard = data.get("entries", [])

func _on_defend_npc_spawn(data: Dictionary) -> void:
	var war_id: String = data.get("war_id", "")
	if war_id != current_war_id or current_game_type != GAME_DEFEND:
		return
	_defend_npcs_alive += int(data.get("count", 1))

# ── Utility ────────────────────────────────────────────────────────────────────

func _blocks_for_tier(tier: int) -> int:
	match tier:
		1: return 1
		2: return 3
		3: return 6
		4: return 10
		_: return 1
