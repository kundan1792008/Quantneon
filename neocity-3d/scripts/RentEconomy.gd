## RentEconomy.gd
## ---------------------------------------------------------------------------
## Passive Quant-token rent engine layered on top of LandOwnershipService.
##
## Mechanics
##   • Tenants (other players, NPC shops, billboard brands) place contracts on
##     a landlord's block.  Each contract has a type (shop / billboard / ad /
##     kiosk), a per-hour rent rate in QNT, a term length and an auto-renew
##     flag.
##   • Rent accrues continuously in memory and is "collected" either:
##       – automatically every `auto_collect_interval` seconds, or
##       – manually when the player opens the real-estate panel and hits
##         "Collect rent".
##   • District taxes are deducted at collection time — the tax rate scales
##     with the leaderboard rank of the landlord (higher rank ⇒ lower tax).
##   • FOMO event zones apply a rent multiplier pulled from
##     LandOwnershipService.event_multipliers_for().
##   • Offers & counter-offers — tenants submit an offer, landlords accept,
##     reject or counter.  Fully driven by signals so the UI can be dumb.
##
## All state is authoritative client-side for offline mode and mirrored with
## the server through SocketIOClient events when available.  Registered as
## the `RentEconomy` autoload.
## ---------------------------------------------------------------------------
extends Node

# ── Tunables ────────────────────────────────────────────────────────────────

## Interval between passive collection passes.
@export var auto_collect_interval: float = 60.0

## Base rent rates per hour in QNT, per contract type.
@export var base_rates: Dictionary = {
	"billboard": 120,
	"shop": 300,
	"ad": 60,
	"kiosk": 80,
	"datacenter": 500,
}

## Max number of simultaneous contracts that may occupy a single block.
@export var max_contracts_per_block: int = 4

## How many hours rent can accrue before it caps (prevents whales who never
## log in from hoarding infinite passive yield).
@export var max_accrual_hours: float = 24.0 * 7.0 # one week

## Base district tax rate (0..1).  Higher leaderboard rank reduces it.
@export var base_tax_rate: float = 0.12

## Minimum hourly rate a contract can have (for validation).
@export var min_rate: int = 5

## Duration options (hours) players can pick for contracts.
@export var duration_options: Array[int] = [6, 24, 72, 168, 720]

# ── State ───────────────────────────────────────────────────────────────────

## {contract_id: Dictionary}  Full contract records.
##   {
##     "id": String,
##     "block_key": String,
##     "landlord_id": String,
##     "landlord_name": String,
##     "tenant_id": String,
##     "tenant_name": String,
##     "type": String,              # "billboard"|"shop"|...
##     "rate_per_hour": int,
##     "asset_ref": String,         # URL / prefab id of the billboard/shop
##     "slot_index": int,
##     "started_at": int,           # unix s
##     "expires_at": int,           # unix s — 0 means perpetual (auto-renew)
##     "auto_renew": bool,
##     "last_collection": int,
##     "accrued": float,            # QNT currently collectable for the LL
##     "lifetime_paid": int,
##     "status": String,            # "active" | "ended" | "paused"
##   }
var contracts: Dictionary = {}

## {block_key: Array[contract_id]} — index.
var _contracts_by_block: Dictionary = {}

## {landlord_id: Array[contract_id]} — index.
var _contracts_by_landlord: Dictionary = {}

## {tenant_id: Array[contract_id]} — index.
var _contracts_by_tenant: Dictionary = {}

## {offer_id: Dictionary} — pending offers waiting for the landlord's reply.
##   {id, block_key, tenant_id, tenant_name, type, rate_per_hour,
##    duration_hours, asset_ref, slot_index, submitted_at, status:"pending"}
var offers: Dictionary = {}

## Aggregate stats — lifetime QNT earned per landlord (useful for trophy UI).
var lifetime_income_by_landlord: Dictionary = {}

## Running total of QNT the *local* player has in uncollected rent.
var local_uncollected_qnt: float = 0.0

## Local player id, cached from NetworkManager.
var local_player_id: String = ""

## Tick accumulator.
var _tick_accum: float = 0.0

# ── Signals ─────────────────────────────────────────────────────────────────

signal contract_created(contract_id, contract)
signal contract_ended(contract_id, reason)
signal contract_renewed(contract_id, new_expires_at)
signal contract_paused(contract_id, reason)
signal contract_updated(contract_id, contract)

signal offer_submitted(offer_id, offer)
signal offer_accepted(offer_id, contract_id)
signal offer_rejected(offer_id, reason)
signal offer_counter(offer_id, counter_offer)

signal rent_accrued(block_key, amount, total_uncollected)
signal rent_collected(landlord_id, amount, tax_paid, contract_count)
signal passive_payout(landlord_id, amount)  # auto-collect pulse
signal toast(message, severity)

# ── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	var net := get_node_or_null("/root/NetworkManager")
	if net:
		net.connect("world_entered", Callable(self, "_on_world_entered"))
	var socket := get_node_or_null("/root/SocketIOClient")
	if socket:
		socket.on_event("rent_snapshot", Callable(self, "_on_rent_snapshot"))
		socket.on_event("rent_offer", Callable(self, "_on_remote_offer"))
		socket.on_event("rent_contract_update", Callable(self, "_on_remote_contract_update"))
		socket.on_event("rent_collection_result", Callable(self, "_on_collection_result"))
	# Demo NPC tenant seeder for offline play — issues a handful of NPC
	# contracts against the player's owned blocks so the economy is visible
	# immediately.
	call_deferred("_seed_npc_tenants_if_offline")

func _process(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum < auto_collect_interval:
		_accrue_between_ticks(delta)
		return
	_accrue_between_ticks(_tick_accum)
	_tick_accum = 0.0
	_expire_offers()
	_expire_contracts()
	_auto_collect_local()

func _on_world_entered(data) -> void:
	if data is Dictionary and data.has("player"):
		local_player_id = str(data.player.get("id", ""))
	if data is Dictionary and data.has("rent_contracts"):
		for c in data.rent_contracts:
			_store_contract(c)

# ── Network handlers ────────────────────────────────────────────────────────

func _on_rent_snapshot(payload) -> void:
	if not (payload is Dictionary): return
	if payload.has("contracts"):
		for c in payload.contracts:
			_store_contract(c)
	if payload.has("offers"):
		for o in payload.offers:
			_store_offer(o)
	_rebuild_indices()

func _on_remote_offer(payload) -> void:
	if payload is Dictionary:
		_store_offer(payload)
		emit_signal("offer_submitted", str(payload.get("id", "")), payload)
		if str(payload.get("landlord_id", "")) == local_player_id:
			emit_signal("toast", "New offer: %d QNT/h %s on %s" % [
				int(payload.rate_per_hour),
				str(payload.type),
				str(payload.block_key)], "info")

func _on_remote_contract_update(payload) -> void:
	if payload is Dictionary:
		_store_contract(payload)
		emit_signal("contract_updated", str(payload.get("id", "")), payload)

func _on_collection_result(payload) -> void:
	if not (payload is Dictionary): return
	var ll: String = str(payload.get("landlord_id", ""))
	var gross := float(payload.get("gross", 0.0))
	var tax := float(payload.get("tax", 0.0))
	var count := int(payload.get("contract_count", 0))
	emit_signal("rent_collected", ll, gross - tax, tax, count)
	if ll == local_player_id:
		local_uncollected_qnt = 0.0
		emit_signal("toast", "Collected %d QNT rent (tax %d)" % [
			int(gross - tax), int(tax)], "reward")

# ── Public API — contracts ─────────────────────────────────────────────────

## Create a new contract on a block.  Fails if the block is not owned, if the
## block already has `max_contracts_per_block`, or the rate is too low.
## Returns the new contract id or "" on failure.
func create_contract(block_key: String, tenant_id: String, tenant_name: String,
		type: String, rate_per_hour: int, duration_hours: int,
		asset_ref: String = "", auto_renew: bool = false) -> String:
	var los := _los()
	if los == null:
		push_error("LandOwnershipService not available")
		return ""
	var block: Dictionary = los.get_block(block_key)
	if block.is_empty() or block.owner_id == "":
		emit_signal("toast", "Cannot place contract — block is unowned.", "warn")
		return ""
	var existing: Array = _contracts_by_block.get(block_key, [])
	if existing.size() >= max_contracts_per_block:
		emit_signal("toast", "Block is full (%d contracts)." % max_contracts_per_block, "warn")
		return ""
	if rate_per_hour < min_rate:
		emit_signal("toast", "Rate too low (min %d QNT/h)." % min_rate, "warn")
		return ""
	var now: int = int(Time.get_unix_time_from_system())
	var expires := 0
	if duration_hours > 0:
		expires = now + duration_hours * 3600
	var contract := {
		"id": _new_id("c"),
		"block_key": block_key,
		"landlord_id": block.owner_id,
		"landlord_name": block.owner_name,
		"tenant_id": tenant_id,
		"tenant_name": tenant_name,
		"type": type,
		"rate_per_hour": rate_per_hour,
		"asset_ref": asset_ref,
		"slot_index": existing.size(),
		"started_at": now,
		"expires_at": expires,
		"auto_renew": auto_renew,
		"last_collection": now,
		"accrued": 0.0,
		"lifetime_paid": 0,
		"status": "active",
	}
	_store_contract(contract)
	emit_signal("contract_created", contract.id, contract)
	_send_to_server("create_contract", contract)
	return contract.id

## End a contract early.  Anyone on either side of the contract may do this;
## the landlord forfeits future rent, the tenant forfeits the deposit (if any).
func end_contract(contract_id: String, actor_id: String,
		reason: String = "cancelled") -> bool:
	if not contracts.has(contract_id): return false
	var c: Dictionary = contracts[contract_id]
	if actor_id != c.landlord_id and actor_id != c.tenant_id and actor_id != "system":
		return false
	# Collect any outstanding rent first.
	_accrue_contract(c, int(Time.get_unix_time_from_system()))
	c.status = "ended"
	contracts[contract_id] = c
	emit_signal("contract_ended", contract_id, reason)
	_send_to_server("end_contract", {"id": contract_id, "reason": reason})
	return true

## Renew / extend an active contract by `hours` additional hours.
func renew_contract(contract_id: String, hours: int) -> bool:
	if not contracts.has(contract_id): return false
	var c: Dictionary = contracts[contract_id]
	if c.status != "active": return false
	var now: int = int(Time.get_unix_time_from_system())
	var base: int = c.expires_at if c.expires_at > now else now
	c.expires_at = base + hours * 3600
	contracts[contract_id] = c
	emit_signal("contract_renewed", contract_id, c.expires_at)
	_send_to_server("renew_contract", {"id": contract_id, "hours": hours})
	return true

func pause_contract(contract_id: String, reason: String = "paused") -> bool:
	if not contracts.has(contract_id): return false
	var c: Dictionary = contracts[contract_id]
	if c.status != "active": return false
	_accrue_contract(c, int(Time.get_unix_time_from_system()))
	c.status = "paused"
	contracts[contract_id] = c
	emit_signal("contract_paused", contract_id, reason)
	return true

func resume_contract(contract_id: String) -> bool:
	if not contracts.has(contract_id): return false
	var c: Dictionary = contracts[contract_id]
	if c.status != "paused": return false
	c.status = "active"
	c.last_collection = int(Time.get_unix_time_from_system())
	contracts[contract_id] = c
	emit_signal("contract_updated", contract_id, c)
	return true

# ── Public API — offers (market) ────────────────────────────────────────────

func submit_offer(block_key: String, tenant_id: String, tenant_name: String,
		type: String, rate_per_hour: int, duration_hours: int,
		asset_ref: String = "", slot_index: int = -1) -> String:
	var los := _los()
	if los == null: return ""
	var block: Dictionary = los.get_block(block_key)
	if block.is_empty() or block.owner_id == "":
		emit_signal("toast", "Block is unowned — no landlord to accept.", "warn")
		return ""
	if rate_per_hour < min_rate:
		emit_signal("toast", "Offer too low (min %d)." % min_rate, "warn")
		return ""
	var offer := {
		"id": _new_id("o"),
		"block_key": block_key,
		"landlord_id": block.owner_id,
		"landlord_name": block.owner_name,
		"tenant_id": tenant_id,
		"tenant_name": tenant_name,
		"type": type,
		"rate_per_hour": rate_per_hour,
		"duration_hours": duration_hours,
		"asset_ref": asset_ref,
		"slot_index": slot_index,
		"submitted_at": int(Time.get_unix_time_from_system()),
		"status": "pending",
	}
	_store_offer(offer)
	emit_signal("offer_submitted", offer.id, offer)
	_send_to_server("submit_offer", offer)
	return offer.id

func accept_offer(offer_id: String, actor_id: String) -> String:
	if not offers.has(offer_id): return ""
	var offer: Dictionary = offers[offer_id]
	if offer.status != "pending": return ""
	if actor_id != offer.landlord_id:
		return ""
	offer.status = "accepted"
	offers[offer_id] = offer
	var cid := create_contract(offer.block_key, offer.tenant_id, offer.tenant_name,
		offer.type, int(offer.rate_per_hour), int(offer.duration_hours),
		str(offer.asset_ref), false)
	if cid != "":
		emit_signal("offer_accepted", offer_id, cid)
		_send_to_server("accept_offer", {"id": offer_id, "contract_id": cid})
	return cid

func reject_offer(offer_id: String, actor_id: String, reason: String = "rejected") -> bool:
	if not offers.has(offer_id): return false
	var offer: Dictionary = offers[offer_id]
	if offer.status != "pending": return false
	if actor_id != offer.landlord_id: return false
	offer.status = "rejected"
	offers[offer_id] = offer
	emit_signal("offer_rejected", offer_id, reason)
	_send_to_server("reject_offer", {"id": offer_id, "reason": reason})
	return true

func counter_offer(offer_id: String, actor_id: String,
		new_rate: int, new_duration_hours: int) -> bool:
	if not offers.has(offer_id): return false
	var offer: Dictionary = offers[offer_id]
	if offer.status != "pending": return false
	if actor_id != offer.landlord_id: return false
	var counter: Dictionary = offer.duplicate(true)
	counter.id = _new_id("o")
	counter.rate_per_hour = new_rate
	counter.duration_hours = new_duration_hours
	counter.status = "pending"
	counter.submitted_at = int(Time.get_unix_time_from_system())
	counter.landlord_id = offer.tenant_id
	counter.tenant_id = offer.landlord_id
	counter.landlord_name = offer.tenant_name
	counter.tenant_name = offer.landlord_name
	_store_offer(counter)
	offer.status = "countered"
	offers[offer_id] = offer
	emit_signal("offer_counter", offer_id, counter)
	_send_to_server("counter_offer", counter)
	return true

func _expire_offers() -> void:
	var cutoff: int = int(Time.get_unix_time_from_system()) - 24 * 3600
	for id in offers.keys():
		var o: Dictionary = offers[id]
		if o.status == "pending" and int(o.submitted_at) < cutoff:
			o.status = "expired"
			offers[id] = o
			emit_signal("offer_rejected", id, "expired")

# ── Passive accrual & collection ────────────────────────────────────────────

func _accrue_between_ticks(delta_sec: float) -> void:
	if delta_sec <= 0.0: return
	for cid in contracts.keys():
		var c: Dictionary = contracts[cid]
		if c.status != "active": continue
		_accrue_contract(c, int(Time.get_unix_time_from_system()))

func _accrue_contract(c: Dictionary, now: int) -> void:
	var elapsed: int = max(0, now - int(c.last_collection))
	if elapsed <= 0: return
	# Cap accrual window.
	var hours := min(float(elapsed) / 3600.0, max_accrual_hours)
	var mult := 1.0
	var los := _los()
	if los:
		mult = float(los.event_multipliers_for(c.block_key).get("rent_mult", 1.0))
	# Decay penalty — decayed buildings earn less because tenants flee.
	var decay_factor := 1.0
	if los:
		var block: Dictionary = los.get_block(c.block_key)
		if block:
			decay_factor = 1.0 - 0.15 * float(block.get("decay_level", 0))
			decay_factor = clamp(decay_factor, 0.1, 1.0)
	var gained := float(c.rate_per_hour) * hours * mult * decay_factor
	c.accrued = float(c.accrued) + gained
	c.last_collection = now
	contracts[c.id] = c
	if gained > 0.01:
		emit_signal("rent_accrued", c.block_key, gained, c.accrued)
		if c.landlord_id == local_player_id:
			local_uncollected_qnt += gained

## Collect all rent owed to a particular landlord.  Returns the net amount
## received (after district tax).
func collect_rent_for(landlord_id: String) -> float:
	var now: int = int(Time.get_unix_time_from_system())
	var gross := 0.0
	var collected_ids: Array = []
	for cid in _contracts_by_landlord.get(landlord_id, []):
		var c: Dictionary = contracts[cid]
		if c.status != "active" and c.status != "ended": continue
		_accrue_contract(c, now)
		gross += float(c.accrued)
		c.lifetime_paid += int(c.accrued)
		c.accrued = 0.0
		contracts[cid] = c
		collected_ids.append(cid)
	if gross <= 0.0:
		emit_signal("toast", "No rent to collect yet.", "info")
		return 0.0
	var tax_rate := tax_rate_for(landlord_id)
	var tax := gross * tax_rate
	var net := gross - tax
	lifetime_income_by_landlord[landlord_id] = \
		int(lifetime_income_by_landlord.get(landlord_id, 0)) + int(net)
	if landlord_id == local_player_id:
		local_uncollected_qnt = 0.0
	emit_signal("rent_collected", landlord_id, net, tax, collected_ids.size())
	_send_to_server("collect_rent", {
		"landlord_id": landlord_id,
		"net": net, "tax": tax,
		"contract_ids": collected_ids,
	})
	return net

## Returns the uncollected (but accrued) QNT for a landlord.
func uncollected_for(landlord_id: String) -> float:
	var total := 0.0
	var now: int = int(Time.get_unix_time_from_system())
	for cid in _contracts_by_landlord.get(landlord_id, []):
		var c: Dictionary = contracts[cid]
		if c.status != "active": continue
		_accrue_contract(c, now)
		total += float(c.accrued)
	return total

## Tax rate scales down from base to 40% of base as the landlord's city
## leaderboard rank improves.  Ranks >50 pay the full base rate.
func tax_rate_for(landlord_id: String) -> float:
	var los := _los()
	if los == null: return base_tax_rate
	var rank := -1
	for entry in los.get_leaderboard(100):
		if entry.owner_id == landlord_id:
			rank = int(entry.rank)
			break
	if rank <= 0:
		return base_tax_rate
	var discount: float = clamp(1.0 - (51.0 - rank) / 85.0, 0.4, 1.0)
	return base_tax_rate * discount

## Suggest a starting rate for a given block+type based on district, decay
## and whether the block is inside an active FOMO event zone.
func suggest_rate(block_key: String, type: String) -> int:
	var base: int = int(base_rates.get(type, 100))
	var los := _los()
	if los == null: return base
	var block: Dictionary = los.get_block(block_key)
	if block.is_empty(): return base
	var district_mult: float = float(los.district_multipliers.get(block.district, 1.0))
	var event_mult: float = float(los.event_multipliers_for(block_key).get("rent_mult", 1.0))
	var decay_penalty: float = 1.0 - 0.15 * float(block.get("decay_level", 0))
	return int(round(base * district_mult * event_mult * decay_penalty))

# ── Expiry & auto-renew ─────────────────────────────────────────────────────

func _expire_contracts() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var to_end: Array = []
	for cid in contracts.keys():
		var c: Dictionary = contracts[cid]
		if c.status != "active": continue
		if int(c.expires_at) == 0: continue
		if now < int(c.expires_at): continue
		if c.auto_renew:
			c.expires_at = now + 24 * 3600
			contracts[cid] = c
			emit_signal("contract_renewed", cid, c.expires_at)
		else:
			to_end.append(cid)
	for cid in to_end:
		end_contract(cid, "system", "expired")

func _auto_collect_local() -> void:
	if local_player_id == "": return
	var owed := uncollected_for(local_player_id)
	if owed < 25.0: return  # save for meaningful payouts
	# Do not charge tax on silent trickle payouts — this is a mini-dopamine
	# pulse.  The big "collect" button still applies the tax.
	# We only notify; we do NOT zero the accrual (player can still press
	# Collect to pocket the sum explicitly).
	emit_signal("passive_payout", local_player_id, owed)

# ── Queries ─────────────────────────────────────────────────────────────────

func contracts_on(block_key: String) -> Array:
	var out: Array = []
	for cid in _contracts_by_block.get(block_key, []):
		if contracts.has(cid):
			out.append(contracts[cid].duplicate(true))
	return out

func contracts_where_landlord_is(owner_id: String) -> Array:
	var out: Array = []
	for cid in _contracts_by_landlord.get(owner_id, []):
		if contracts.has(cid):
			out.append(contracts[cid].duplicate(true))
	return out

func contracts_where_tenant_is(tenant_id: String) -> Array:
	var out: Array = []
	for cid in _contracts_by_tenant.get(tenant_id, []):
		if contracts.has(cid):
			out.append(contracts[cid].duplicate(true))
	return out

func available_slots_on(block_key: String) -> int:
	var used: int = _contracts_by_block.get(block_key, []).size()
	return max(0, max_contracts_per_block - used)

func offer_count_for_landlord(landlord_id: String) -> int:
	var n := 0
	for id in offers.keys():
		var o: Dictionary = offers[id]
		if o.status == "pending" and o.landlord_id == landlord_id:
			n += 1
	return n

func pending_offers_for(landlord_id: String) -> Array:
	var out: Array = []
	for id in offers.keys():
		var o: Dictionary = offers[id]
		if o.status == "pending" and o.landlord_id == landlord_id:
			out.append(o.duplicate(true))
	return out

## Returns a human-readable summary line for UI.
func describe_contract(contract_id: String) -> String:
	if not contracts.has(contract_id): return "Unknown contract"
	var c: Dictionary = contracts[contract_id]
	var parts := PackedStringArray()
	parts.append("%s @ %d QNT/h" % [str(c.type).capitalize(), int(c.rate_per_hour)])
	parts.append("Tenant %s" % str(c.tenant_name))
	if int(c.expires_at) > 0:
		var hours_left: int = max(0, (int(c.expires_at) - int(Time.get_unix_time_from_system())) / 3600)
		parts.append("%d h left" % hours_left)
	else:
		parts.append("perpetual")
	if float(c.accrued) > 0.01:
		parts.append("%d QNT pending" % int(c.accrued))
	return " — ".join(parts)

# ── Internal storage ────────────────────────────────────────────────────────

func _store_contract(raw: Dictionary) -> void:
	var c := _normalize_contract(raw)
	contracts[c.id] = c
	_rebuild_indices()

func _store_offer(raw: Dictionary) -> void:
	var o: Dictionary = {
		"id": str(raw.get("id", _new_id("o"))),
		"block_key": str(raw.get("block_key", "")),
		"landlord_id": str(raw.get("landlord_id", "")),
		"landlord_name": str(raw.get("landlord_name", "")),
		"tenant_id": str(raw.get("tenant_id", "")),
		"tenant_name": str(raw.get("tenant_name", "")),
		"type": str(raw.get("type", "billboard")),
		"rate_per_hour": int(raw.get("rate_per_hour", 0)),
		"duration_hours": int(raw.get("duration_hours", 24)),
		"asset_ref": str(raw.get("asset_ref", "")),
		"slot_index": int(raw.get("slot_index", -1)),
		"submitted_at": int(raw.get("submitted_at", Time.get_unix_time_from_system())),
		"status": str(raw.get("status", "pending")),
	}
	offers[o.id] = o

func _normalize_contract(raw: Dictionary) -> Dictionary:
	return {
		"id": str(raw.get("id", _new_id("c"))),
		"block_key": str(raw.get("block_key", "")),
		"landlord_id": str(raw.get("landlord_id", "")),
		"landlord_name": str(raw.get("landlord_name", "")),
		"tenant_id": str(raw.get("tenant_id", "")),
		"tenant_name": str(raw.get("tenant_name", "")),
		"type": str(raw.get("type", "billboard")),
		"rate_per_hour": int(raw.get("rate_per_hour", 0)),
		"asset_ref": str(raw.get("asset_ref", "")),
		"slot_index": int(raw.get("slot_index", 0)),
		"started_at": int(raw.get("started_at", Time.get_unix_time_from_system())),
		"expires_at": int(raw.get("expires_at", 0)),
		"auto_renew": bool(raw.get("auto_renew", false)),
		"last_collection": int(raw.get("last_collection", Time.get_unix_time_from_system())),
		"accrued": float(raw.get("accrued", 0.0)),
		"lifetime_paid": int(raw.get("lifetime_paid", 0)),
		"status": str(raw.get("status", "active")),
	}

func _rebuild_indices() -> void:
	_contracts_by_block.clear()
	_contracts_by_landlord.clear()
	_contracts_by_tenant.clear()
	for cid in contracts.keys():
		var c: Dictionary = contracts[cid]
		_push(_contracts_by_block, c.block_key, cid)
		_push(_contracts_by_landlord, c.landlord_id, cid)
		_push(_contracts_by_tenant, c.tenant_id, cid)

func _push(dict: Dictionary, key: String, value) -> void:
	if key == "": return
	if not dict.has(key):
		dict[key] = []
	if not dict[key].has(value):
		dict[key].append(value)

func _new_id(prefix: String) -> String:
	return "%s_%d_%d" % [prefix,
		int(Time.get_unix_time_from_system()),
		randi() % 100000]

func _los() -> Node:
	return get_node_or_null("/root/LandOwnershipService")

func _send_to_server(event_name: String, payload: Dictionary) -> void:
	var socket := get_node_or_null("/root/SocketIOClient")
	if socket and socket.has_method("send_event"):
		socket.send_event(event_name, payload)

# ── Offline seeding ─────────────────────────────────────────────────────────

func _seed_npc_tenants_if_offline() -> void:
	var net := get_node_or_null("/root/NetworkManager")
	if net: return
	var los := _los()
	if los == null: return
	var brands: Array = [
		"ChromaCola", "SynthBank", "NeonNoodle", "RazerCyber",
		"QuantBurger", "HoloHabit", "SkyCab",
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var keys: Array = los.blocks.keys()
	if keys.is_empty(): return
	for i in range(min(30, keys.size())):
		var k: String = keys[rng.randi_range(0, keys.size() - 1)]
		var block: Dictionary = los.get_block(k)
		if block.is_empty() or block.owner_id == "": continue
		var brand: String = brands[rng.randi_range(0, brands.size() - 1)]
		var type: String = ["billboard", "shop", "ad", "kiosk"][rng.randi_range(0, 3)]
		create_contract(k, "npc_%s" % brand.to_lower(), brand, type,
			suggest_rate(k, type), 24 * rng.randi_range(1, 7),
			"res://ads/%s.png" % brand.to_lower(), true)
