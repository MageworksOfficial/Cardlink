extends VBoxContainer
var host: Window
var input: TextEdit
var deck_name: LineEdit
var review: ItemList
var summary: Label
var plan: Array = []
var issues: Array = []
var ignore_bad: CheckBox
func _ready() -> void:
	name="Import Decklist"
	deck_name=LineEdit.new(); deck_name.placeholder_text="Deck name"; deck_name.max_length=160; add_child(deck_name)
	input=TextEdit.new(); input.custom_minimum_size.y=130; input.placeholder_text="Deck\n4 Lightning Bolt\n1 Sol Ring (CMM) 396\n\nCommander\n1 Your leader name"; add_child(input)
	input.text_changed.connect(func() -> void:
		if not host.busy: plan.clear(); review.clear(); summary.text="Text changed. Resolve again before import.")
	var actions := HBoxContainer.new(); add_child(actions)
	host.button(actions,"Parse / Resolve",resolve)
	host.button(actions,"Review Selected",review_selected)
	host.button(actions,"Skip / Restore Entry",skip_selected)
	host.button(actions,"Import Chosen Cards + Deck",commit)
	summary=host.label(self,"Names reuse an existing local printing first; otherwise use the cached Oracle representative, then exact-name lookup. Explicit set/collector entries request that printing. No fuzzy auto-matching.")
	review=ItemList.new(); review.size_flags_vertical=Control.SIZE_EXPAND_FILL; add_child(review)
	ignore_bad=CheckBox.new(); ignore_bad.text="Skip unparsed lines listed below"; ignore_bad.visible=false; add_child(ignore_bad)
	host.label(self,"Commander/Leader entries join the main deck as leaders. Sideboard, Companion and Maybeboard are retained in deck metadata and the collection, outside the playable library. Each import creates a new saved deck; existing decks are never overwritten.")
func resolve() -> void:
	if host.busy: return
	host.busy=true; input.editable=false
	var parsed: Dictionary = preload("res://scripts/integrations/decklist_parser.gd").parse(input.text)
	issues=parsed.issues; ignore_bad.visible=not issues.is_empty(); ignore_bad.button_pressed=false
	plan=await host.hub.importer.resolve(parsed.entries)
	input.editable=true; host.busy=false; redraw()
	host.status.text="Resolution cancelled. No deck saved." if host.hub.importer.cancelled else "Review the matches, choose replacements or skip entries, then Import."
func redraw() -> void:
	review.clear()
	var total: int=0; var matched: int=0; var existing: int=0; var attention: int=issues.size(); var need: int=0
	for row: Dictionary in plan:
		var label: String = "Skipped" if row.skip else "Needs attention: "+row.error if not row.error.is_empty() else "Already in Library" if not row.local.is_empty() else "Download chosen printing"
		review.add_item("%d × %s [%s] — %s" % [row.quantity,row.name,row.section,label])
		if row.skip: continue
		total+=int(row.quantity)
		if not row.error.is_empty(): attention+=1
		else:
			matched+=1
			if not row.local.is_empty(): existing+=1
			else: need+=1
	for item: Dictionary in issues: review.add_item("Unparsed line %d: %s" % [item.line,item.text])
	summary.text="Total copies: %d · Unique entries: %d · Matched: %d · Already local: %d · Need download: %d · Needs attention: %d" % [total,plan.size(),matched,existing,need,attention]
func index() -> int:
	var selected: PackedInt32Array = review.get_selected_items()
	return selected[0] if not selected.is_empty() and selected[0]<plan.size() else -1
func review_selected() -> void:
	if host.busy or index()<0: return
	host.query.text=plan[index()].name; host.exact.button_pressed=false; host.tabs.current_tab=0
	host.status.text="Search and select a result, then Use for Selected Deck Entry. Choose Printing if needed."
func choose(card: Dictionary) -> void:
	var i: int = index()
	if i<0: host.status.text="Select a deck entry first."; return
	plan[i].card=card; plan[i].local=host.hub.importer.existing_id(card.id); plan[i].error=""; plan[i].skip=false
	redraw(); review.select(i)
func skip_selected() -> void:
	if host.busy or index()<0: return
	var i: int = index(); plan[i].skip=not plan[i].skip; redraw(); review.select(i)
func commit() -> void:
	if host.busy: return
	if plan.is_empty(): host.status.text="Parse and resolve a deck first."; return
	if not issues.is_empty() and not ignore_bad.button_pressed: host.status.text="Correct the unparsed lines or explicitly choose Skip unparsed lines."; return
	host.busy=true; input.editable=false
	var response: Dictionary = await host.hub.importer.commit(plan,deck_name.text)
	host.status.text=response.error if response.has("error") else "Deck saved: "+str(response.deck.deck_name)+". Available cards refreshed automatically."
	if not response.has("error"):
		var deck: Node = preload("res://scripts/collection_workflow.gd").valid_deck(host.hub.context_owner)
		if deck != null: deck.refresh_saved()
	input.editable=true; host.busy=false
