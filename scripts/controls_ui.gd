extends Label
## Sol-alt kontroller paneli: oyundaki tum input action'larini InputMap'ten
## okuyup Label'a yazar. Boylece yeni bir kontrol eklenirse GUI otomatik guncellenir.

const ORDER: Array[String] = [
	"move_forward",
	"move_backward",
	"move_left",
	"move_right",
	"fire",
	"look_hold",
	"eject_mag",
	"rack_slide",
	"clear_jam",
	"toggle_cursor",
]

const DESCRIPTIONS := {
	"move_forward": "Ileri",
	"move_backward": "Geri",
	"move_left": "Sol",
	"move_right": "Sag",
	"fire": "Ates (durbun ACMAZ)",
	"look_hold": "Durbun / Nisan (basili tut)",
	"eject_mag": "Sarjor Degistir (hane bos ise sonra F)",
	"rack_slide": "Surgu Cek / Tutukluk Gider",
	"clear_jam": "Surgu Cek / Tutukluk Gider",
	"toggle_cursor": "Imlec Ac/Kapat",
}


func _ready() -> void:
	text = build_text()


func build_text() -> String:
	var lines: Array[String] = ["KONTROLLER"]
	# WASD'yi tek satirda grupla
	var fwd := _key_text("move_forward")
	var back := _key_text("move_backward")
	var left := _key_text("move_left")
	var right := _key_text("move_right")
	lines.append("WASD: Hareket (%s/%s/%s/%s)" % [fwd, left, back, right])
	lines.append("Mouse: Once silah (iki eksen), sinirda kamera (bodycam)")
	lines.append("%s (basili tut): Durbun + hassas kamera" % _key_text("look_hold"))
	lines.append("%s: Ates (durbun acmaz)" % _key_text("fire"))
	for action in ["eject_mag", "rack_slide", "toggle_cursor"]:
		var desc: String = str(DESCRIPTIONS.get(action, action))
		lines.append("%s: %s" % [_key_text(action), desc])
	return "\n".join(lines)


func _key_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var events := InputMap.action_get_events(action)
	var parts: Array[String] = []
	for ev in events:
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var code: int = int(k.physical_keycode) if k.physical_keycode != 0 else int(k.keycode)
			var s := OS.get_keycode_string(code)
			if s == "":
				s = OS.get_keycode_string(int(k.keycode))
			parts.append(s)
		elif ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			match mb.button_index:
				MOUSE_BUTTON_LEFT:
					parts.append("LMB")
				MOUSE_BUTTON_RIGHT:
					parts.append("RMB")
				MOUSE_BUTTON_MIDDLE:
					parts.append("MMB")
				_:
					parts.append("Mouse%d" % int(mb.button_index))
		elif ev is InputEventJoypadButton:
			parts.append("Pad%d" % int((ev as InputEventJoypadButton).button_index))
		elif ev is InputEventJoypadMotion:
			parts.append("PadAxis")
	if parts.is_empty():
		return "?"
	return "/".join(parts)
