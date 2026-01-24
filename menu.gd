extends Control
class_name MenuNode

@onready var IP_LABEL      : Label    = $HBoxContainer/VBoxContainer/Label
@onready var IP_ENTRY_BOX  : TextEdit = $HBoxContainer/VBoxContainer/HBoxContainer/TextEdit
@onready var CONNECT_BUTTON: Button   = $HBoxContainer/VBoxContainer/HBoxContainer/Button
@onready var MESSAGE_LABEL : Label    = $HBoxContainer/VBoxContainer/Label2
signal connect_button_pressed(Address: String)

func _ready() -> void:
	CONNECT_BUTTON.pressed.connect(_on_connect_button_pressed)

func _set_ip_label(input_text: String) -> void:
	if is_valid_ip_port(input_text):
		IP_LABEL.text = "YOUR IP: " + input_text
		MESSAGE_LABEL.text = "IP copied to clipboard! :3"
		DisplayServer.clipboard_set(input_text)

func _on_connect_button_pressed() -> void:
	var input_text = IP_ENTRY_BOX.text.strip_edges()
	if is_valid_ip_port(input_text):
		MESSAGE_LABEL.text = "CONNECTING TO: " + input_text
		connect_button_pressed.emit(input_text)
	else: 
		MESSAGE_LABEL.text = input_text + " is not a valid IP address."

func is_valid_ip_port(input_text: String) -> bool:
	var regex = RegEx.new()
	regex.compile("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
	var result = regex.search(input_text)
	return true if result else false
