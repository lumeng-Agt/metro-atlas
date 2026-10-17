extends RefCounted

const WINDOW_CLOSE_ICON = preload("res://assets/ui/window-close.svg")

const CANVAS := Color("#F5F3ED")
const SURFACE := Color("#FFFEFA")
const SURFACE_ALT := Color("#F1F0EA")
const INK := Color("#24332F")
const MUTED := Color("#63706A")
const ACCENT := Color("#24745E")
const ACCENT_SOFT := Color("#E6F1EB")
const BORDER := Color("#DEDED7")
const BORDER_STRONG := Color("#C8CDC4")
const WATER := Color("#DCE8E5")
const SUCCESS := Color("#276D52")
const WARNING := Color("#865C12")
const WARNING_SOFT := Color("#F5EEDC")
const DANGER := Color("#A23935")
const DANGER_SOFT := Color("#F6E9E5")
const BLUE := Color("#365F8C")
const BLUE_SOFT := Color("#E8EEF4")

static func create_theme(base_font: Font, bold_font: Font, scale: float) -> Theme:
	var result := Theme.new()
	result.default_font = base_font
	result.default_font_size = roundi(18.0 * scale)
	result.set_color("font_color", "Label", INK)
	result.set_color("font_hover_color", "Label", INK)
	result.set_color("font_color", "Button", INK)
	result.set_color("font_hover_color", "Button", INK)
	result.set_color("font_pressed_color", "Button", INK)
	result.set_color("font_disabled_color", "Button", Color("#A1A49B"))
	result.set_color("font_focus_color", "Button", INK)
	result.set_font("font", "Button", base_font)
	result.set_font("font", "Label", base_font)
	result.set_font("font", "LineEdit", base_font)
	result.set_font("font", "TextEdit", base_font)
	result.set_font("font", "OptionButton", base_font)
	result.set_font("font", "TabContainer", base_font)
	result.set_font("font", "Tree", base_font)
	result.set_font("font", "ItemList", base_font)
	result.set_font("font", "PopupMenu", base_font)
	result.set_font("font", "AcceptDialog", base_font)
	result.set_font("title_font", "Window", bold_font)
	result.set_color("title_color", "Window", INK)
	result.set_color("title_outline_modulate", "Window", Color.TRANSPARENT)
	result.set_font_size("title_font_size", "Window", roundi(16.0 * scale))
	result.set_icon("close", "Window", WINDOW_CLOSE_ICON)
	result.set_icon("close_pressed", "Window", WINDOW_CLOSE_ICON)
	result.set_color("font_color", "LineEdit", INK)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("font_uneditable_color", "LineEdit", MUTED)
	result.set_color("font_color", "TextEdit", INK)
	result.set_color("font_color", "OptionButton", INK)
	result.set_color("font_selected_color", "TabContainer", ACCENT)
	result.set_color("font_unselected_color", "TabContainer", MUTED)
	result.set_color("font_hovered_color", "TabContainer", INK)
	result.set_color("font_disabled_color", "TabContainer", Color("#A1A49B"))
	result.set_color("font_color", "Tree", INK)
	result.set_color("font_selected_color", "Tree", INK)
	result.set_color("font_hovered_color", "Tree", INK)
	result.set_color("font_color", "ItemList", INK)
	result.set_color("font_selected_color", "ItemList", INK)
	result.set_color("font_hovered_color", "ItemList", INK)
	result.set_color("font_color", "PopupMenu", INK)
	result.set_color("font_color", "LinkButton", ACCENT)
	result.set_color("font_hover_color", "LinkButton", INK)
	result.set_color("font_pressed_color", "LinkButton", ACCENT)
	result.set_color("font_disabled_color", "LinkButton", Color("#A1A49B"))
	result.set_color("font_color", "TooltipLabel", INK)
	result.set_color("font_hover_color", "PopupMenu", INK)
	result.set_color("font_disabled_color", "PopupMenu", Color("#A1A49B"))
	for check_type in ["CheckButton", "CheckBox"]:
		result.set_color("font_color", check_type, INK)
		result.set_color("font_hover_color", check_type, INK)
		result.set_color("font_pressed_color", check_type, ACCENT)
		result.set_color("font_disabled_color", check_type, Color("#92948D"))
	result.set_stylebox("normal", "Button", _box(SURFACE_ALT, BORDER, 8))
	result.set_stylebox("hover", "Button", _box(Color("#EAEAE2"), BORDER_STRONG, 8))
	result.set_stylebox("pressed", "Button", _box(Color("#E3E5DC"), BORDER_STRONG, 8))
	result.set_stylebox("disabled", "Button", _box(Color("#F0EFEA"), BORDER, 8))
	result.set_stylebox("focus", "Button", _box(SURFACE, ACCENT, 8, 2))
	result.set_stylebox("normal", "OptionButton", _box(SURFACE, BORDER_STRONG, 8))
	result.set_stylebox("hover", "OptionButton", _box(Color("#F3F3ED"), BORDER_STRONG, 8))
	result.set_stylebox("pressed", "OptionButton", _box(Color("#ECEDE6"), ACCENT, 8))
	result.set_stylebox("disabled", "OptionButton", _box(SURFACE_ALT, BORDER, 8))
	result.set_stylebox("focus", "OptionButton", _box(SURFACE, ACCENT, 8, 2))
	result.set_stylebox("normal", "LineEdit", _box(SURFACE, BORDER_STRONG, 8))
	result.set_stylebox("focus", "LineEdit", _box(SURFACE, ACCENT, 8, 2))
	result.set_stylebox("hover", "LineEdit", _box(SURFACE, BORDER_STRONG, 8))
	result.set_stylebox("read_only", "LineEdit", _box(SURFACE_ALT, BORDER, 8))
	result.set_stylebox("normal", "TabContainer", _box(SURFACE, BORDER, 12))
	result.set_stylebox("tab_selected", "TabContainer", _box(SURFACE, ACCENT, 8, 1))
	result.set_stylebox("tab_unselected", "TabContainer", _box(SURFACE_ALT, BORDER, 8))
	result.set_stylebox("tab_hovered", "TabContainer", _box(Color("#F3F3ED"), BORDER_STRONG, 8))
	result.set_stylebox("tab_disabled", "TabContainer", _box(Color("#F0EFEA"), BORDER, 8))
	result.set_stylebox("tab_focus", "TabContainer", _box(SURFACE, ACCENT, 8, 2))
	result.set_stylebox("panel", "TabContainer", _box(SURFACE, BORDER, 12))
	result.set_stylebox("panel", "FileDialog", _box(SURFACE, BORDER, 12))
	result.set_stylebox("background", "FileDialog", _box(SURFACE, BORDER, 12))
	result.set_stylebox("panel", "AcceptDialog", _box(SURFACE, BORDER, 16))
	result.set_stylebox("panel", "ConfirmationDialog", _box(SURFACE, BORDER, 16))
	result.set_stylebox("embedded_border", "Window", _window_box())
	result.set_stylebox("embedded_unfocused_border", "Window", _window_box())
	result.set_stylebox("normal", "TextEdit", _box(SURFACE, BORDER_STRONG, 8))
	result.set_stylebox("focus", "TextEdit", _box(SURFACE, ACCENT, 8, 2))
	result.set_stylebox("panel", "PanelContainer", _box(SURFACE, BORDER, 12))
	result.set_stylebox("panel", "PopupMenu", _box(SURFACE, BORDER, 10))
	result.set_stylebox("separator", "PopupMenu", _box(BORDER, Color.TRANSPARENT, 0))
	result.set_stylebox("background", "TooltipPanel", _box(SURFACE, BORDER, 8))
	result.set_stylebox("grabber_area", "HSlider", _box(BORDER, Color.TRANSPARENT, 2))
	result.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT_SOFT, Color.TRANSPARENT, 2))
	result.set_stylebox("grabber", "HSlider", _box(ACCENT, ACCENT, 12))
	result.set_stylebox("grabber_highlight", "HSlider", _box(ACCENT, ACCENT, 12))
	result.set_stylebox("selected", "ItemList", _box(ACCENT_SOFT, Color("#C4D9CE"), 6))
	result.set_stylebox("cursor", "ItemList", _box(ACCENT, ACCENT, 2))
	result.set_stylebox("selected", "Tree", _box(ACCENT_SOFT, Color("#C4D9CE"), 6))
	result.set_stylebox("selected_focus", "Tree", _box(ACCENT_SOFT, ACCENT, 6))
	result.set_stylebox("cursor", "Tree", _box(ACCENT, ACCENT, 2))
	for scrollbar_type in ["VScrollBar", "HScrollBar"]:
		result.set_constant("scrollbar_size", scrollbar_type, 10)
		result.set_stylebox("scroll", scrollbar_type, _scroll_box(SURFACE_ALT, BORDER))
		result.set_stylebox("scroll_focus", scrollbar_type, _scroll_box(SURFACE_ALT, ACCENT))
		result.set_stylebox("grabber", scrollbar_type, _scroll_box(BORDER_STRONG, BORDER_STRONG))
		result.set_stylebox("grabber_highlight", scrollbar_type, _scroll_box(MUTED, MUTED))
		result.set_stylebox("grabber_pressed", scrollbar_type, _scroll_box(ACCENT, ACCENT))
	result.set_constant("separation", "VBoxContainer", 8)
	result.set_constant("separation", "HBoxContainer", 8)
	result.set_font("bold_font", "Label", bold_font)
	return result

static func _box(fill: Color, edge: Color, radius: int, edge_width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(edge_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

static func _window_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE
	box.border_color = BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.expand_margin_left = 1
	box.expand_margin_top = 36
	box.expand_margin_right = 1
	box.expand_margin_bottom = 1
	return box

static func _scroll_box(fill: Color, edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(0)
	box.set_corner_radius_all(5)
	return box
