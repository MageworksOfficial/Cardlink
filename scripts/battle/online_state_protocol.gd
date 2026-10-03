extends RefCounted
const A=preload("res://scripts/network/network_action.gd")
const D=preload("res://scripts/battle/online_state_data.gd")
const HOST_MESSAGES=["state_probe","state_capture","state_save_commit","state_save_done","state_load","state_commit","state_go","state_stable"]
const BOTH=["state_cancel","state_save_offer","state_save_accept","state_save_decline"]
static func sender_allowed(kind: String,host: bool) -> bool: return kind in BOTH or (kind in HOST_MESSAGES)==host
static func hex(value: Variant,length: int) -> bool: return value is String and value.length()==length and value.is_valid_hex_number(false)
static func valid(kind: String,d: Variant) -> bool:
	if not d is Dictionary or not hex(d.get("id"),32) or not d.get("epoch") is String or (not d.epoch.is_empty() and not hex(d.epoch,32)): return false
	d=d.duplicate(true);d.erase("epoch")
	match kind:
		"state_save_accept","state_save_decline","state_save_staged","state_save_commit","state_save_committed","state_save_done","state_accept","state_decline","state_commit","state_committed","state_go","state_ack","state_stable": return A.keys(d,["id"])
		"state_cancel": return A.keys(d,["id","reason"]) and d.reason in ["write_failed","missing_pair","pair_mismatch","invalid"]
		"state_save_offer": return A.keys(d,["id","name"]) and D.safe_text(d.name,80)
		"state_save_ready": return A.keys(d,["id","fingerprint","identity"]) and hex(d.fingerprint,64) and hex(d.identity,64)
		"state_probe","state_load": return A.keys(d,["id","save_state_id","shared_hash"]) and hex(d.save_state_id,32) and hex(d.shared_hash,64)
		"state_info": return A.keys(d,["id","fingerprint"]) and (d.fingerprint=="" or hex(d.fingerprint,64))
		"state_capture": return A.keys(d,["id","state","revision","shared"]) and A.snapshot(d.state) and A.number(d.revision,0,1000000000) and D.shared_valid(d.shared)
	return false
