extends RefCounted

const WINDOW_CLOSE_ICON = preload("res://assets/ui/window-close.svg")

# Direction: Modern Transit Signage + Architectural Atlas.
# High-contrast dark signage headers (#142822), crisp white elevated cards (#FFFFFF),
# warm drafting-paper canvas (#EFEFE7), and clear tactile button hierarchy.
const CANVAS := Color("#F7F6F2")          # warm architectural drafting ground
const SURFACE := Color("#FFFFFF")         # crisp elevated card surface
const SURFACE_ALT := Color("#F8F7F2")     # soft ivory well, secondary controls
const HEADER_DARK := Color("#16221C")     # deep architectural ink
const INK := Color("#1A1F1D")             # crisp editorial dark charcoal
const MUTED := Color("#69736E")           # legible warm slate annotation
const ACCENT := Color("#1B5E4F")          # museum transit green
const ACCENT_HOVER := Color("#14483C")
# Text that sits on an ACCENT fill.
const ON_ACCENT := Color("#FFFFFF")
const ACCENT_SOFT := Color("#E8F2EE")
const BORDER := Color("#E4E2DA")          # structural hairline
const BORDER_STRONG := Color("#CCC9BF")   # outer card / island border
const WATER := Color("#D6E3EC")
const SUCCESS := Color("#1B5E4F")
const WARNING := Color("#B87314")
const WARNING_SOFT := Color("#FAF2E3")
const DANGER := Color("#C44E35")          # proof-reader's red
const DANGER_SOFT := Color("#F9EBE8")
const BLUE := Color("#2471A3")
const BLUE_SOFT := Color("#E6EFF5")
# Ink for light-filled export surfaces (schematic sheets, share cards).
const INK_ON_LIGHT := Color("#20332B")

static func create_theme(base_font: Font, bold_font: Font, scale: float) -> Theme:
	var result := Theme.new()
	result.default_font = base_font
	result.default_font_size = roundi(18.0 * scale)
	result.set_color("font_color", "Label", INK)
	result.set_color("font_hover_color", "Label", INK)
	result.set_color("font_color", "Button", INK)
	result.set_color("font_hover_color", "Button", ACCENT_HOVER)
	result.set_color("font_pressed_color", "Button", ACCENT)
	result.set_color("font_disabled_color", "Button", MUTED)
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
	result.set_color("font_disabled_color", "TabContainer", MUTED)
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
	result.set_color("font_disabled_color", "LinkButton", MUTED)
	result.set_color("font_color", "TooltipLabel", INK)
	result.set_color("font_hover_color", "PopupMenu", INK)
	result.set_color("font_disabled_color", "PopupMenu", MUTED)
	for check_type in ["CheckButton", "CheckBox"]:
		result.set_color("font_color", check_type, INK)
		result.set_color("font_hover_color", check_type, INK)
		result.set_color("font_pressed_color", check_type, ACCENT)
		result.set_color("font_disabled_color", check_type, MUTED)
	result.set_stylebox("normal", "CheckButton", _box(SURFACE_ALT, BORDER, 5))
	result.set_stylebox("hover", "CheckButton", _box(ACCENT_SOFT, ACCENT, 5))
	result.set_stylebox("pressed", "CheckButton", _box(ACCENT_SOFT, ACCENT, 5))
	result.set_stylebox("disabled", "CheckButton", _box(SURFACE_ALT, BORDER, 5))
	result.set_stylebox("normal", "Button", secondary_button_box())
	result.set_stylebox("hover", "Button", secondary_button_hover_box())
	result.set_stylebox("pressed", "Button", _box(ACCENT_SOFT, ACCENT, 5))
	result.set_stylebox("disabled", "Button", _box(Color("#F6F5F0"), Color("#DFDFD6"), 5))
	result.set_stylebox("focus", "Button", _box(SURFACE, ACCENT, 5, 2))
	result.set_stylebox("normal", "OptionButton", _box(SURFACE, BORDER_STRONG, 5))
	result.set_stylebox("hover", "OptionButton", _box(SURFACE_ALT, ACCENT, 5))
	result.set_stylebox("pressed", "OptionButton", _box(ACCENT_SOFT, ACCENT, 5))
	result.set_stylebox("disabled", "OptionButton", _box(SURFACE_ALT, BORDER, 5))
	result.set_stylebox("focus", "OptionButton", _box(SURFACE, ACCENT, 5, 2))
	result.set_stylebox("normal", "LineEdit", _box(SURFACE_ALT, BORDER_STRONG, 5))
	result.set_stylebox("focus", "LineEdit", _box(SURFACE, ACCENT, 5, 2))
	result.set_stylebox("hover", "LineEdit", _box(SURFACE, BORDER_STRONG, 5))
	result.set_stylebox("read_only", "LineEdit", _box(SURFACE_ALT, BORDER, 5))
	result.set_stylebox("normal", "TabContainer", _box(SURFACE, BORDER, 5))
	result.set_stylebox("tab_selected", "TabContainer", _box(SURFACE, ACCENT, 5, 1))
	result.set_stylebox("tab_unselected", "TabContainer", _box(SURFACE_ALT, BORDER, 5))
	result.set_stylebox("tab_hovered", "TabContainer", _box(SURFACE_ALT, BORDER_STRONG, 5))
	result.set_stylebox("tab_disabled", "TabContainer", _box(Color("#F2F4F7"), BORDER, 5))
	result.set_stylebox("tab_focus", "TabContainer", _box(SURFACE, ACCENT, 5, 2))
	result.set_stylebox("panel", "TabContainer", _box(SURFACE, BORDER, 5))
	result.set_stylebox("panel", "FileDialog", _box(SURFACE, BORDER_STRONG, 6))
	result.set_stylebox("background", "FileDialog", _box(SURFACE, BORDER_STRONG, 6))
	result.set_stylebox("panel", "AcceptDialog", _dialog_box())
	result.set_stylebox("panel", "ConfirmationDialog", _dialog_box())
	result.set_stylebox("embedded_border", "Window", _window_box())
	result.set_stylebox("embedded_unfocused_border", "Window", _window_box())
	result.set_stylebox("normal", "TextEdit", _box(SURFACE_ALT, BORDER_STRONG, 5))
	result.set_stylebox("focus", "TextEdit", _box(SURFACE, ACCENT, 5, 2))
	result.set_stylebox("panel", "PanelContainer", card_box())
	result.set_stylebox("panel", "PopupMenu", _box(SURFACE, BORDER_STRONG, 5))
	result.set_stylebox("separator", "PopupMenu", _box(BORDER, Color.TRANSPARENT, 0))
	result.set_stylebox("background", "TooltipPanel", _box(SURFACE, BORDER_STRONG, 5))
	result.set_stylebox("grabber_area", "HSlider", _box(BORDER, Color.TRANSPARENT, 2))
	result.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT_SOFT, Color.TRANSPARENT, 2))
	result.set_stylebox("grabber", "HSlider", _box(ACCENT, ACCENT, 12))
	result.set_stylebox("grabber_highlight", "HSlider", _box(ACCENT, ACCENT, 12))
	result.set_stylebox("selected", "ItemList", _box(ACCENT_SOFT, BORDER_STRONG, 4))
	result.set_stylebox("cursor", "ItemList", _box(ACCENT, ACCENT, 2))
	result.set_stylebox("selected", "Tree", _box(ACCENT_SOFT, BORDER_STRONG, 4))
	result.set_stylebox("selected_focus", "Tree", _box(ACCENT_SOFT, ACCENT, 4))
	result.set_stylebox("cursor", "Tree", _box(ACCENT, ACCENT, 2))
	for scrollbar_type in ["VScrollBar", "HScrollBar"]:
		result.set_constant("scrollbar_size", scrollbar_type, 8)
		result.set_stylebox("scroll", scrollbar_type, _scroll_box(SURFACE_ALT, BORDER))
		result.set_stylebox("scroll_focus", scrollbar_type, _scroll_box(SURFACE_ALT, ACCENT))
		result.set_stylebox("grabber", scrollbar_type, _scroll_box(BORDER_STRONG, BORDER_STRONG))
		result.set_stylebox("grabber_highlight", scrollbar_type, _scroll_box(MUTED, MUTED))
		result.set_stylebox("grabber_pressed", scrollbar_type, _scroll_box(ACCENT, ACCENT))
	result.set_constant("separation", "VBoxContainer", 10)
	result.set_constant("separation", "HBoxContainer", 8)
	result.set_font("bold_font", "Label", bold_font)
	return result

static func _box(fill: Color, edge: Color, radius: int, edge_width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(edge_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

static func primary_button_box(hover: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = ACCENT_HOVER if hover else ACCENT
	box.border_color = Color("#113B32")
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	box.shadow_color = Color(0.06, 0.10, 0.08, 0.12)
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 3)
	return box

static func secondary_button_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#FAF9F5")
	box.border_color = Color("#DEDCD4")
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

static func secondary_button_hover_box() -> StyleBoxFlat:
	var box := secondary_button_box()
	box.bg_color = ACCENT_SOFT
	box.border_color = ACCENT
	return box

static func toolbar_button_box(hover: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = ACCENT_SOFT if hover else Color.TRANSPARENT
	box.border_color = ACCENT if hover else Color.TRANSPARENT
	box.set_border_width_all(1 if hover else 0)
	box.set_corner_radius_all(14)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	return box

static func menu_entry_box(primary: bool = false, hover: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	# Entries share one shape; only the primary carries the accent fill. The old
	# 4px left bar made every secondary entry look like an alert.
	if primary:
		box.bg_color = ACCENT_HOVER if hover else ACCENT
		box.border_color = Color("#0F382F")
		box.set_border_width_all(1)
		box.border_width_bottom = 2
	else:
		box.bg_color = ACCENT_SOFT if hover else SURFACE_ALT
		box.border_color = ACCENT if hover else BORDER
		box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

## A utility action: no fill, no edge, a rule under the label on hover.
static func quiet_link_box(hover: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.TRANSPARENT
	box.border_color = ACCENT if hover else Color.TRANSPARENT
	box.set_border_width_all(0)
	box.border_width_bottom = 1 if hover else 0
	box.set_corner_radius_all(0)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

static func _dialog_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE
	box.border_color = BORDER_STRONG
	box.set_border_width_all(1)
	box.border_width_top = 4
	box.set_corner_radius_all(6)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	box.shadow_color = Color(0.06, 0.10, 0.08, 0.14)
	box.shadow_size = 12
	box.shadow_offset = Vector2(0, 4)
	return box

static func _window_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE
	box.border_color = BORDER_STRONG
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.expand_margin_left = 1
	box.expand_margin_top = 36
	box.expand_margin_right = 1
	box.expand_margin_bottom = 1
	box.shadow_color = Color(0.06, 0.10, 0.08, 0.16)
	box.shadow_size = 14
	box.shadow_offset = Vector2(0, 4)
	return box

static func _scroll_box(fill: Color, edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(0)
	box.set_corner_radius_all(4)
	return box

static func _flat_box(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = Color.TRANSPARENT
	box.set_border_width_all(0)
	box.set_corner_radius_all(4)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

static func _underline_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = ACCENT_SOFT
	box.border_color = ACCENT
	box.set_border_width_all(0)
	box.border_width_bottom = 3
	box.set_corner_radius_all(4)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

## Segmented dock container (wraps bottom tools or panel tabs).
static func dock_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#FFFFFF", 0.96)
	box.border_color = Color("#DFDCD4")
	box.set_border_width_all(1)
	box.set_corner_radius_all(22)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	box.shadow_color = Color(0.06, 0.10, 0.08, 0.10)
	box.shadow_size = 14
	box.shadow_offset = Vector2(0, 4)
	return box

static func segment_active_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = ACCENT
	box.border_color = Color("#113B32")
	box.set_border_width_all(1)
	box.set_corner_radius_all(18)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box

static func segment_idle_box(hover: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = ACCENT_SOFT if hover else Color.TRANSPARENT
	box.border_color = Color.TRANSPARENT
	box.set_border_width_all(0)
	box.set_corner_radius_all(18)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box

## Top signage bar: floating capsule island with subtle border and soft shadow.
static func shell_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(SURFACE, 0.96)
	box.border_color = BORDER_STRONG
	box.set_border_width_all(1)
	box.set_corner_radius_all(18)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	box.shadow_color = Color(0.06, 0.10, 0.08, 0.10)
	box.shadow_size = 14
	box.shadow_offset = Vector2(0, 4)
	return box

## Bottom work bar: crisp white surface with a 1px top border.
static func shell_box_top() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE
	box.border_color = BORDER_STRONG
	box.set_border_width_all(0)
	box.border_width_top = 1
	box.set_corner_radius_all(0)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

## Signage badge pill for the city & date in the top bar.
static func badge_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = HEADER_DARK
	box.border_color = ACCENT
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	return box

## Main menu & modal sheet card with a bold 6px metro-green top signage stripe.
static func menu_card_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE
	box.border_color = ACCENT
	box.set_border_width_all(1)
	box.border_width_top = 6
	box.set_corner_radius_all(6)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 24
	box.content_margin_bottom = 24
	box.shadow_color = Color(0.06, 0.10, 0.08, 0.12)
	box.shadow_size = 16
	box.shadow_offset = Vector2(0, 6)
	return box

## A card inside lists/dialogs.
static func card_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#FAF9F5", 0.70)
	box.border_color = Color("#E5E2DA", 0.75)
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

static func accent_card_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#F4F8F6", 0.85)
	box.border_color = ACCENT
	box.set_border_width_all(0)
	box.border_width_left = 3
	box.set_corner_radius_all(10)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

static func canvas_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = CANVAS
	box.border_color = BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	return box

## A drawing note pinned over the map: crisp card with a 4px left metro-green bar.
static func note_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(SURFACE, 0.96)
	box.border_color = ACCENT
	box.set_border_width_all(1)
	box.border_width_left = 5
	box.set_corner_radius_all(5)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	box.shadow_color = Color(0.06, 0.10, 0.08, 0.10)
	box.shadow_size = 10
	box.shadow_offset = Vector2(0, 3)
	return box

## Floating archive card on the left of the map: crisp border, 18px rounded card, generous shadow.
static func chapter_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(SURFACE, 0.96)
	box.border_color = Color("#DFDCD4")
	box.set_border_width_all(1)
	box.set_corner_radius_all(18)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	box.shadow_color = Color(0.06, 0.10, 0.08, 0.12)
	box.shadow_size = 22
	box.shadow_offset = Vector2(0, 6)
	return box

## Floating inspector drawer on the right of the map.
static func floating_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(SURFACE, 0.98)
	box.border_color = BORDER_STRONG
	box.set_border_width_all(1)
	box.set_corner_radius_all(16)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 18
	box.content_margin_bottom = 18
	box.shadow_color = Color(0.06, 0.10, 0.08, 0.12)
	box.shadow_size = 18
	box.shadow_offset = Vector2(0, 6)
	return box

static func floating_card_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.TRANSPARENT
	box.border_color = Color.TRANSPARENT
	box.set_border_width_all(0)
	box.set_corner_radius_all(0)
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	return box
