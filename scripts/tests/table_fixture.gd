extends RefCounted
## Legacy regression fixture only. Production main starts with no sample cards.
static func create_main() -> Control:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	var card: Control = load("res://scenes/card.tscn").instantiate()
	card.name = "Card"
	main.add_child(card)
	main.ready.connect(func() -> void: initialize_coordinates.call_deferred(main))
	return main
static func initialize_coordinates(main: Control) -> void:
	# Legacy suites explicitly drive the original manual preparation API.
	main.ensure_network().preparation.auto_setup = false
	# Pointer regression fixtures use known world/screen coordinates.
	main.tabletop.deck_preferences = preload("res://scripts/usability/deck_preferences.gd").new(OS.get_cmdline_user_args()[0].path_join("recent_decks.cfg"))
	main.tabletop.view.zoom = 1.0
	main.tabletop.view.pan = Vector2.ZERO
	main.tabletop.view.apply_view()
