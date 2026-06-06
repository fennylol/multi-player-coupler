extends Control
class_name MenuNode

@onready var IP_LABEL       : Label         = $HBoxContainer/VBoxContainer/YourIP/Label
@onready var COPY_IP_BUTTON : Button        = $HBoxContainer/VBoxContainer/YourIP/Button
@onready var IP_FIELDS      : HBoxContainer = $HBoxContainer/VBoxContainer/IPfields
@onready var IP_ENTRY_BOX   : TextEdit      = $HBoxContainer/VBoxContainer/IPfields/TextEdit
@onready var CONNECT_BUTTON : Button        = $HBoxContainer/VBoxContainer/IPfields/Button
@onready var MSG_FIELDS     : VBoxContainer = $HBoxContainer/VBoxContainer/MSGfields
@onready var CHAT_LOG       : TextEdit      = $HBoxContainer/VBoxContainer/MSGfields/chatlog
@onready var MSG_ENTRY_BOX  : LineEdit      = $HBoxContainer/VBoxContainer/MSGfields/MSGfields/LineEdit
@onready var SEND_MSG_BUTTON: Button        = $HBoxContainer/VBoxContainer/MSGfields/MSGfields/Button
@onready var MESSAGE_LABEL  : Label         = $HBoxContainer/VBoxContainer/Label2
signal connect_button_pressed(Address: String)
signal send_msg_button_pressed(Message: String)
# ======== #
# ultility #
# ======== #
func _ready() -> void:
   CONNECT_BUTTON.pressed.connect(_on_connect_button_pressed)
   SEND_MSG_BUTTON.pressed.connect(_on_send_msg_button_pressed)
   _toggle_fields(false)
func _process(_delta: float) -> void:
   if Input.is_action_just_pressed("enter"):
      if IP_FIELDS.visible:
         CONNECT_BUTTON.pressed.emit()
         IP_ENTRY_BOX.grab_focus()
      elif MSG_FIELDS.visible:
         SEND_MSG_BUTTON.pressed.emit()
         MSG_ENTRY_BOX.grab_focus()
func _toggle_fields(msg_visible: bool) -> void:
   if msg_visible: MSG_ENTRY_BOX.focus_mode = Control.FOCUS_ALL
   else          : IP_ENTRY_BOX.focus_mode = Control.FOCUS_ALL
   IP_FIELDS.visible = not msg_visible
   MSG_FIELDS.visible = msg_visible
func is_valid_ip_port(input_text: String) -> bool:
   var regex = RegEx.new()
   regex.compile("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
   var result = regex.search(input_text)
   return true if result else false
# ========= #
# ip fields #
# ========= #
func _set_ip_label(input_text: String) -> void:
   if is_valid_ip_port(input_text):
      IP_LABEL.text = "YOUR IP: " + input_text
      COPY_IP_BUTTON.pressed.connect(DisplayServer.clipboard_set.bind(input_text))
func _on_connect_button_pressed() -> void:
   var input_text = IP_ENTRY_BOX.text.strip_edges()
   if is_valid_ip_port(input_text):
      MESSAGE_LABEL.text = "CONNECTING TO: " + input_text
      connect_button_pressed.emit(input_text)
   else: 
      IP_ENTRY_BOX.text = ""
      MESSAGE_LABEL.text = input_text + " is not a valid IP address."
# ========== #
# msg fields #
# ========== #
func _on_send_msg_button_pressed() -> void:
   var input_text = MSG_ENTRY_BOX.text.strip_edges()
   MSG_ENTRY_BOX.text = ""
   if input_text:
      _append_to_chatlog("[YOU]: " + input_text)
      send_msg_button_pressed.emit(input_text)
func _append_to_chatlog(Msg: String) -> void:
   CHAT_LOG.text += Time.get_time_string_from_system() + " " + Msg+"\n" 
   CHAT_LOG.scroll_vertical = CHAT_LOG.get_line_count()
