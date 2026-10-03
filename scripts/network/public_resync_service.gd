extends RefCounted
var router: Node
func _init(owner: Node) -> void:
	router = owner
func request() -> void:
	if not router.enabled: return
	if router.recovery.authenticated:
		router.recovery.manual_resync()
		return
	router.scan()
	if router.is_host(): router.send_frame("resync", router.state)
	else: router.send_frame("resync_request", {})
	router.log_safe("Public resync requested.")
func apply(value: Dictionary, sequence: int) -> void:
	var c: Node = router.table.match_controller
	router.applying = true
	for card: Control in router.table.cards.duplicate():
		if not value.cards.has(card.state.match_instance_id) and not card.state.current_zone in ["hand", "library", "custom_pile"]:
			if not router.state.cards.has(card.state.match_instance_id) and not card.state.is_token and not card.state.card_definition_id.is_empty():
				c.move_card(card,"hand",true,"local",true)
			elif card.state.is_token or router.state.cards.has(card.state.match_instance_id): c.remove_card(card)
	for item: Control in router.table.extras.counters.duplicate():
		if not value.counters.has(item.instance_id): router.remove_counter(item.instance_id)
	router.state = value.duplicate(true)
	router.committed = sequence
	router.serializer.apply_all()
	router.baseline = router.serializer.capture()
	router.applying = false
	router.log_safe("Public resync applied; private zones preserved.")
