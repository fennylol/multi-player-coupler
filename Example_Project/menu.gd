extends Control
class_name MenuNode

@onready var GLOBAL_BUTTON  : Button        = $HBoxContainer/VBoxContainer/WAN_vs_LAN_box/global_button
@onready var LOCAL_BUTTON   : Button        = $HBoxContainer/VBoxContainer/WAN_vs_LAN_box/local_button
@onready var IP_LABEL       : Label         = $HBoxContainer/VBoxContainer/YourIP/Label
@onready var COPY_IP_BUTTON : Button        = $HBoxContainer/VBoxContainer/YourIP/Button
@onready var NAME_ENTRY_BOX : LineEdit      = $HBoxContainer/VBoxContainer/NameBox/LineEdit
@onready var SET_NAME_BUTTON: Button        = $HBoxContainer/VBoxContainer/NameBox/Button
@onready var IP_ENTRY_BOX   : TextEdit      = $HBoxContainer/VBoxContainer/IPfields/TextEdit
@onready var CONNECT_BUTTON : Button        = $HBoxContainer/VBoxContainer/IPfields/Button
@onready var PEER_LIST      : TextEdit      = $HBoxContainer/VBoxContainer/peer_list
@onready var MSG_FIELDS     : VBoxContainer = $HBoxContainer/VBoxContainer/MSGfields
@onready var CHAT_LOG       : TextEdit      = $HBoxContainer/VBoxContainer/MSGfields/chatlog
@onready var MSG_ENTRY_BOX  : LineEdit      = $HBoxContainer/VBoxContainer/MSGfields/MSGfields/LineEdit
@onready var SEND_MSG_BUTTON: Button        = $HBoxContainer/VBoxContainer/MSGfields/MSGfields/Button
@onready var MESSAGE_LABEL  : Label         = $HBoxContainer/VBoxContainer/Label2
signal network_type_changed(global: bool)
signal name_changed(new_name: String)
signal connect_button_pressed(Address: String)
signal send_msg_button_pressed(Message: String)
var _MyAddrPort: String = ""
# ======== #
# ultility #
# ======== #
func _ready() -> void:
   GLOBAL_BUTTON.pressed.connect(_on_network_type_changed.bind(true))
   LOCAL_BUTTON.pressed.connect(_on_network_type_changed.bind(false))
   COPY_IP_BUTTON.pressed.connect(func(): DisplayServer.clipboard_set(_MyAddrPort))
   SET_NAME_BUTTON.pressed.connect(_on_set_name_button_pressed)
   CONNECT_BUTTON.pressed.connect(_on_connect_button_pressed)
   SEND_MSG_BUTTON.pressed.connect(_on_send_msg_button_pressed)
   show_chat(false)
func _process(_delta: float) -> void:
   if Input.is_action_just_pressed("enter"):
      if   NAME_ENTRY_BOX.has_focus(): SET_NAME_BUTTON.pressed.emit()
      elif IP_ENTRY_BOX.has_focus()  : CONNECT_BUTTON.pressed.emit()
      elif MSG_FIELDS.visible:
         SEND_MSG_BUTTON.pressed.emit()
         MSG_ENTRY_BOX.grab_focus()
func show_chat(msg_visible: bool) -> void:
   MSG_FIELDS.visible = msg_visible
func is_valid_ip_addr(input_text: String) -> bool:
   var regex = RegEx.new()
   regex.compile("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
   var result = regex.search(input_text)
   return true if result else false
func is_valid_ip_port(input_text: String) -> bool:
   var parts := input_text.rsplit(":", true, 1)
   if parts.size() != 2: return false
   if not is_valid_ip_addr(parts[0]): return false
   if not parts[1].is_valid_int(): return false
   var port := int(parts[1])
   return port >= 1 and port <= 65535
# ========= #
# ip fields #
# ========= #
func set_ip_label(input_text: String) -> void:
   _MyAddrPort = input_text
   IP_LABEL.text = "YOUR IP: " + input_text
   COPY_IP_BUTTON.disabled = not is_valid_ip_port(input_text)
func _on_network_type_changed(global: bool) -> void:
   GLOBAL_BUTTON.disabled = global
   LOCAL_BUTTON.disabled = not global
   network_type_changed.emit(global)
func _on_connect_button_pressed() -> void:
   var input_text = IP_ENTRY_BOX.text.strip_edges()
   IP_ENTRY_BOX.text = ""
   if is_valid_ip_port(input_text):
      MESSAGE_LABEL.text = "CONNECTING TO: " + input_text
      connect_button_pressed.emit(input_text)
   else:
      MESSAGE_LABEL.text = input_text + " is not a valid IP:PORT address."
# =========== #
# name fields #
# =========== #
func set_name_placeholder(current_name: String) -> void:
   NAME_ENTRY_BOX.placeholder_text = current_name
func _on_set_name_button_pressed() -> void:
   var new_name: String = NAME_ENTRY_BOX.text.strip_edges()
   NAME_ENTRY_BOX.text = ""
   if new_name != "":
      set_name_placeholder(new_name)
      name_changed.emit(new_name)
# ========= #
# peer list #
# ========= #
func update_peers(peers: Array[OneTruePingus.PingusPeer], names: Dictionary[int, String]) -> void:
   var lines: PackedStringArray = []
   for peer in peers:
      var state_str: String = peer.Addr + ":" + str(peer.Port)
      match peer.State:
         OneTruePingus.PingusStates.NOT_STARTED: state_str += " not started"
         OneTruePingus.PingusStates.INFORMING  : state_str += " informing..."
         OneTruePingus.PingusStates.CONNECTED  : state_str += " connected"
         _                                     : state_str += " unknown"
      if names.has(peer.NetworkID):
         state_str = names[peer.NetworkID] + " (" + str(peer.NetworkID) + ")\n" + state_str
      lines.append(state_str)
   var new_text := "\n".join(lines)
   if PEER_LIST.text != new_text: PEER_LIST.text = new_text
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
