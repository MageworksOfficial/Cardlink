extends RefCounted
## Index zero is the top. Stores match IDs, never definition IDs.
var order: Array[String] = []
var random := RandomNumberGenerator.new()
func _init() -> void:
	random.randomize()
func put(id: String, on_top: bool) -> void:
	insert_nth(id, 1, not on_top)
func insert_at(id: String, index: int) -> void:
	order.erase(id)
	order.insert(clampi(index, 0, order.size()), id)
func insert_nth(id: String, n: int, from_bottom: bool = false) -> void:
	# N is one-based; compute after removal so existing members are unambiguous.
	order.erase(id)
	var offset: int = clampi(n - 1, 0, order.size())
	insert_at(id, order.size() - offset if from_bottom else offset)
func peek(count: int) -> Array[String]:
	var result: Array[String] = []
	result.assign(order.slice(0, clampi(count, 0, order.size())))
	return result
func commit_top(expected_order: Array[String], top: Array[String], bottom: Array[String]) -> bool:
	# Atomic review: reject stale library state or missing/duplicated reviewed IDs.
	if order != expected_order:
		return false
	var original: Array[String] = peek(top.size() + bottom.size())
	var proposed: Array[String] = top.duplicate()
	proposed.append_array(bottom)
	original.sort()
	proposed.sort()
	if original != proposed:
		return false
	var remaining: Array[String] = []
	remaining.assign(order.slice(proposed.size()))
	order = top.duplicate()
	order.append_array(remaining)
	order.append_array(bottom)
	return true
func draw() -> String:
	return "" if order.is_empty() else order.pop_front()
func shuffle() -> void:
	for i: int in range(order.size() - 1, 0, -1):
		var j: int = random.randi_range(0, i)
		var previous: String = order[i]
		order[i] = order[j]
		order[j] = previous
