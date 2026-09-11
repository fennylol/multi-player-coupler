extends Node

@onready var menu: MenuNode = $CanvasLayer/Menu
var my_own_little_pingus: OneTruePingus
var playing_globally: bool = true
var my_name: String = ""
var peer_names: Dictionary[int, String] = {}

enum DataTypes {
   # do not use 0xC0 #
   Message = 0x01, ConnectionData = 0xCD, DisconnectionData = 0xDD, IdentityData = 0x15
}

func _ready() -> void:
   print(IP.get_local_addresses())
   var arguments = {}
   for argument in OS.get_cmdline_args():
      if argument.find("=") > -1:
         var key_value = argument.split("=")
         arguments[key_value[0].lstrip("--")] = key_value[1]
   my_own_little_pingus = OneTruePingus.new("", int(arguments.get("network_id", 0)))
   my_name = str(my_own_little_pingus.NetworkID)
   menu.set_name_placeholder(my_name)

   menu.connect_button_pressed.connect(touch_something_with_my_own_little_pingus)
   menu.send_msg_button_pressed.connect(touch_something_with_my_own_little_stringus)
   menu.network_type_changed.connect(_on_network_type_changed)
   menu.name_changed.connect(_on_name_changed)

   my_own_little_pingus.recieved_data.connect(_recieve_message)
   my_own_little_pingus.connection_established.connect(_on_connection_established)

   my_own_little_pingus.set_name("my_own_little_pingus")
   add_child(my_own_little_pingus)
   _refresh_ip_label()
func _notification(what: int) -> void:
   if what == NOTIFICATION_WM_CLOSE_REQUEST and my_own_little_pingus:
      my_own_little_pingus.send_data(DataTypes.DisconnectionData)

func touch_something_with_my_own_little_pingus(Addr: String) -> void:
   var parts := Addr.rsplit(":", true, 1)
   if parts.size() < 2: return
   my_own_little_pingus.add_peer(parts[0], parts[1].to_int())
   _refresh_peer_list()
func touch_something_with_my_own_little_stringus(Msg: String) -> void:
   my_own_little_pingus.send_data(DataTypes.Message, Msg.to_utf8_buffer())

# =============== #
# signal handling #
# =============== #
func _on_network_type_changed(global: bool) -> void:
   playing_globally = global
   # LAN play shouldn't have to wait on STUN before the pingus starts listening
   if not global and my_own_little_pingus.ExternAddr == "":
      my_own_little_pingus.ExternAddr = "PEE.POO.CUM.POO"
      my_own_little_pingus.ExternPort = my_own_little_pingus.LocalPort
   _refresh_ip_label()
func _on_name_changed(new_name: String) -> void:
   my_name = new_name
   _send_identity_data()
func _on_connection_established(network_id: int, peer_address: String, peer_port: int) -> void:
   # introduce the new peer to everyone, and everyone to the new peer
   _send_connection_data(network_id, peer_address, peer_port)
   for peer in my_own_little_pingus.Peers:
      if peer.NetworkID == network_id: continue
      if peer.State != OneTruePingus.PingusStates.CONNECTED: continue
      _send_connection_data(peer.NetworkID, peer.Addr, peer.Port)
   _send_identity_data()
   menu.show_chat(true)
   _refresh_peer_list()
func _refresh_ip_label() -> void:
   if playing_globally and my_own_little_pingus.ExternAddr == "":
      menu.set_ip_label("fetching...")
   else:
      menu.set_ip_label(my_own_little_pingus.get_addr_port(playing_globally))
func _refresh_peer_list() -> void:
   menu.update_peers(my_own_little_pingus.Peers, peer_names)
func _name_of(network_id: int) -> String:
   return peer_names.get(network_id, str(network_id))

# ============ #
# data routing #
# ============ #
func _recieve_message(sender_id: int, data_type: int, data: PackedByteArray) -> void:
   match data_type:
      DataTypes.Message          : menu._append_to_chatlog("[" + _name_of(sender_id) + "]: " + data.get_string_from_utf8())
      DataTypes.ConnectionData   : _recieve_connection_data(data)
      DataTypes.DisconnectionData: _recieve_disconnection_data(sender_id)
      DataTypes.IdentityData     : _recieve_identity_data(sender_id, data)
      OneTruePingus.DataTypes.CONTROL:
         menu.MESSAGE_LABEL.text = data.get_string_from_utf8()
         _refresh_ip_label()
         _refresh_peer_list()
func _recieve_connection_data(data: PackedByteArray) -> void:
   if data.size() < OneTruePingus.NETWORK_ID_SIZE + OneTruePingus.PORT_SIZE: return
   var peer_id      : int    = data.decode_u32(0)
   var peer_port    : int    = data.decode_u16(OneTruePingus.NETWORK_ID_SIZE)
   var peer_address : String = data.slice(OneTruePingus.NETWORK_ID_SIZE + OneTruePingus.PORT_SIZE).get_string_from_utf8()
   var otp := my_own_little_pingus
   if (peer_id == otp.NetworkID) \
   or (peer_address == otp.ExternAddr and peer_port == otp.ExternPort) \
   or (peer_address == otp.LocalAddr and peer_port == otp.LocalPort):
      return
   otp.add_peer(peer_address, peer_port, peer_id)
   _refresh_peer_list()
func _recieve_disconnection_data(sender_id: int) -> void:
   for peer in my_own_little_pingus.Peers:
      if peer.NetworkID == sender_id:
         my_own_little_pingus.Peers.erase(peer)
         break
   menu._append_to_chatlog(_name_of(sender_id) + " left")
   peer_names.erase(sender_id)
   _refresh_peer_list()
func _recieve_identity_data(sender_id: int, data: PackedByteArray) -> void:
   var new_name: String = data.get_string_from_utf8()
   if not peer_names.has(sender_id)       : menu._append_to_chatlog(new_name + " joined")
   elif peer_names[sender_id] != new_name : menu._append_to_chatlog(peer_names[sender_id] + " is now " + new_name)
   peer_names[sender_id] = new_name
   _refresh_peer_list()

func _send_connection_data(network_id: int, peer_address: String, peer_port: int) -> void:
   var data: PackedByteArray = []
   data.resize(OneTruePingus.NETWORK_ID_SIZE + OneTruePingus.PORT_SIZE)
   data.encode_u32(0, network_id)
   data.encode_u16(OneTruePingus.NETWORK_ID_SIZE, peer_port)
   data.append_array(peer_address.to_utf8_buffer())
   my_own_little_pingus.send_data(DataTypes.ConnectionData, data)
func _send_identity_data() -> void:
   my_own_little_pingus.send_data(DataTypes.IdentityData, my_name.to_utf8_buffer())
