extends RefCounted
## Frozen unique missing-work denominator, retained across interrupted resumes.
var started: bool = false
var finished: bool = false
var targets: Dictionary = {}
var done: Dictionary = {}
var remote_total: int = 0
var remote_done: int = 0
var high_water: float = 0
func reset() -> void:
    started = false; finished = false
    targets.clear(); done.clear()
    remote_total = 0; remote_done = 0; high_water = 0
func keys_for(need: Dictionary) -> Dictionary:
    var keys: Dictionary = {}
    for hash_value: String in need.images: keys["image:"+hash_value] = true
    for id: String in need.definitions: keys["definition:"+id] = true
    return keys
func begin(need: Dictionary, peer: Dictionary) -> void:
    if finished: reset()
    var missing: Dictionary = keys_for(need)
    var remote_missing: int = int(peer.get("images",0))+int(peer.get("definitions",0))
    if not started:
        targets = missing
        remote_total = remote_missing
        started = true
    else:
        for key: String in targets:
            if not missing.has(key): done[key] = true
        remote_done = maxi(remote_done,remote_total-remote_missing)
func complete(key: String) -> void:
    if targets.has(key): done[key] = true
func remote_finished(count: int) -> void:
    remote_done = mini(remote_total,remote_done+count)
func total() -> int: return targets.size()+remote_total
func completed() -> int: return done.size()+remote_done
func percent() -> float:
    var current: float = 100.0*completed()/total() if total()>0 else 100.0
    high_water = maxf(high_water,current)
    return high_water
