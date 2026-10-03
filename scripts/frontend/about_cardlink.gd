extends Window
const AppInfo = preload("res://scripts/frontend/app_info.gd")
var feedback: Button
static func open(parent: Node) -> Window:
    var panel := new()
    parent.add_child(panel)
    panel.popup_centered_clamped(Vector2i(650,580),0.95)
    return panel
func _ready() -> void:
    title = "About " + AppInfo.LABEL
    size = Vector2i(650,580)
    close_requested.connect(queue_free)
    var margin := MarginContainer.new()
    add_child(margin)
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for edge in ["left","right","top","bottom"]:
        margin.add_theme_constant_override("margin_" + edge,18)
    var column := VBoxContainer.new()
    margin.add_child(column)
    var text := RichTextLabel.new()
    text.size_flags_vertical = Control.SIZE_EXPAND_FILL
    text.bbcode_enabled = true
    text.text = "[b]" + AppInfo.LABEL + "[/b]\n\nCardLink is still in active development. Bugs and rough edges are expected. Feedback is greatly appreciated and helps improve the project. Thank you for testing CardLink!\n\n[b]Your kitchen table, your rules[/b]\nA free, community-focused manual card sandbox for custom cards and many tabletop systems. There is no automatic rules enforcement. Open-source publication is planned.\n\n[b]License[/b]\nGNU General Public License v3.0 (GPL-3.0). Third-party content retains its original rights and licensing.\n\n[b]Unofficial project[/b]\nNot affiliated with, sponsored by, or endorsed by Wizards of the Coast, The Pokémon Company, Konami, or other game publishers. Third-party content belongs to its rights holders. Scryfall is an optional, user-triggered integration.\n\n[b]FIRST BETA TESTERS[/b]\nMattamn\nPicklenick99\n\nSpecial thanks for helping test real matches, identify usability problems, and shape CardLink development.\n\n[b]Credits · Beta testers[/b]\nSpecial thanks to the early testers who found bugs, tested multiplayer, and improved CardLink. Your feedback helped shape the project. Names are added only with permission.\nBuilt with Godot Engine. Engine license and component notices: https://godotengine.org/license/\n\n[b]Online service notice[/b]\nThe current server is provided for testing and community use. Continued availability and uptime are not guaranteed. Multiple selectable community servers and donated relay capacity are future possibilities, not current features.\n\n[b]Feedback[/b]\nPlease include your version, operating system, Online/Offline mode, and steps to reproduce. Never share passwords, keys, room credentials, or personal information. The project link will become available after publication."
    column.add_child(text)
    feedback = Button.new()
    feedback.text = "Send Feedback / Project"
    feedback.disabled = AppInfo.PROJECT_URL.is_empty()
    feedback.tooltip_text = "Project URL is not configured yet." if feedback.disabled else "Open the project website."
    feedback.pressed.connect(func() -> void:
        if AppInfo.PROJECT_URL.begins_with("https://"): OS.shell_open(AppInfo.PROJECT_URL))
    column.add_child(feedback)
    var close := Button.new()
    close.text = "Close"
    close.pressed.connect(queue_free)
    column.add_child(close)
