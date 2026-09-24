extends RefCounted
## Produce one result object per action; UI and future transport consume that same result.
var controller: Node
var rng := RandomNumberGenerator.new()
func _init(owner: Node) -> void:
	controller = owner
	rng.randomize()
func roll(count: int, sides: int) -> Dictionary:
	if count < 1 or count > 100 or sides < 2 or sides > 1000:
		return {"error": "Use 1-100 dice with 2-1000 sides."}
	var values: Array[int] = []
	var total: int = 0
	for i: int in count:
		var value: int = rng.randi_range(1, sides)
		values.append(value)
		total += value
	var notation: String = "D%d" % sides if count == 1 else "%dD%d" % [count, sides]
	return controller.record_event("dice", "%s rolled %s → %d" % [controller.actor_name(), notation, total], {"count": count, "sides": sides, "values": values, "total": total})
func roll_text(value: String) -> Dictionary:
	var pattern := RegEx.new()
	pattern.compile("^\\s*([0-9]{1,3})[dD]([0-9]{1,4})\\s*$")
	var found: RegExMatch = pattern.search(value)
	if found == null:
		return {"error": "Enter dice as XdY, for example 3d6."}
	return roll(int(found.get_string(1)), int(found.get_string(2)))
func flip() -> Dictionary:
	var side: String = "Heads" if rng.randi_range(0, 1) == 0 else "Tails"
	return controller.record_event("coin", "%s flipped a coin → %s" % [controller.actor_name(), side], {"side": side})
func calculate(value: String) -> Dictionary:
	if value.is_empty() or value.length() > 200:
		return {"error": "Enter a short arithmetic expression."}
	var allowed := RegEx.new()
	allowed.compile("^[0-9. +*/%()\\-\\t]+$")
	if allowed.search(value) == null or value.contains("**"):
		return {"error": "Use numbers, parentheses, +, -, *, / or %."}
	var expression := Expression.new()
	# Calculator division should be real division even when inputs are integers.
	var numbers := RegEx.new()
	numbers.compile("[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+")
	var matches: Array[RegExMatch] = numbers.search_all(value)
	for i: int in range(matches.size() - 1, -1, -1):
		var number: RegExMatch = matches[i]
		if not number.get_string().contains("."):
			value = value.insert(number.get_end(), ".0")
	if expression.parse(value) != OK:
		return {"error": "Check the arithmetic expression."}
	var result: Variant = expression.execute([], null, false)
	if expression.has_execute_failed() or not (result is float or result is int) or not is_finite(float(result)):
		return {"error": "This expression has no finite result."}
	return {"value": result}
