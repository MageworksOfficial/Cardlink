extends RefCounted
## Geometry only: input is visible bounds, never card identities or game rules.
const MODES = ["Stack", "Fan", "Line Up Horizontally", "Line Up Vertically", "Distribute Evenly", "Spread Out"]
const GAP: float = 18.0
static func union_rect(rects: Array) -> Rect2:
	var result: Rect2 = rects[0]
	for rect: Rect2 in rects: result = result.merge(rect)
	return result
static func positions(rects: Array, mode: int, table: Rect2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if rects.size() < 2 or mode < 0 or mode >= MODES.size(): return result
	var original: Rect2 = union_rect(rects)
	for rect: Rect2 in rects: result.append(rect.position)
	if mode == 4:
		# Distribute centers on the dominant axis; keep the other axis untouched.
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for rect: Rect2 in rects:
			low = low.min(rect.get_center()); high = high.max(rect.get_center())
		var axis: int = 0 if high.x-low.x >= high.y-low.y else 1
		var order: Array = range(rects.size())
		order.sort_custom(func(a: int, b: int) -> bool:
			var av: float = rects[a].get_center()[axis]; var bv: float = rects[b].get_center()[axis]
			return a < b if is_equal_approx(av,bv) else av < bv)
		for i: int in order.size():
			var index: int = order[i]
			result[index][axis] = lerpf(low[axis],high[axis],float(i)/(order.size()-1))-rects[index].size[axis]/2
	else:
		var smallest: float = INF
		for rect: Rect2 in rects: smallest = minf(smallest,rect.size.x)
		var offset: float = clampf(smallest*0.3,12,40) if mode == 1 else clampf(smallest*0.05,2,6)
		var cursor: float = 0.0
		for i: int in rects.size():
			var size: Vector2 = rects[i].size
			match mode:
				0: result[i] = Vector2.ONE * offset * i
				1: result[i] = Vector2(offset*i,-size.y/2)
				2,5: result[i] = Vector2(cursor,-size.y/2); cursor += size.x+GAP
				3: result[i] = Vector2(-size.x/2,cursor); cursor += size.y+GAP
		var planned: Array = []
		for i: int in rects.size(): planned.append(Rect2(result[i],rects[i].size))
		var shift: Vector2 = original.get_center()-union_rect(planned).get_center()
		for i: int in result.size(): result[i] += shift
	var target_rects: Array = []
	for i: int in rects.size(): target_rects.append(Rect2(result[i],rects[i].size))
	var group: Rect2 = union_rect(target_rects)
	# Shift the entire formation, never shrink cards or independently clamp them.
	var adjustment := Vector2.ZERO
	for axis: int in 2:
		if group.size[axis] > table.size[axis]: adjustment[axis] = table.position[axis]-group.position[axis]
		elif group.position[axis] < table.position[axis]: adjustment[axis] = table.position[axis]-group.position[axis]
		elif group.end[axis] > table.end[axis]: adjustment[axis] = table.end[axis]-group.end[axis]
	for i: int in result.size(): result[i] += adjustment
	return result
