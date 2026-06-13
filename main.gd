extends Node

@onready var menu: MenuNode = $CanvasLayer/Menu
var my_own_little_pingus: PingusPrime = PingusPrime.new()

const MSG_DATA_TYPE: int = 0x01

func _ready() -> void:
   print(IP.get_local_addresses())
   var arguments = {}
   for argument in OS.get_cmdline_args():
      if argument.find("=") > -1:
         var key_value = argument.split("=")
         arguments[key_value[0].lstrip("--")] = key_value[1]
   if arguments.keys().has("network_id"):
      my_own_little_pingus = PingusPrime.new("", int(arguments["network_id"]))

   menu.connect_button_pressed.connect(touch_something_with_my_own_little_pingus)
   menu.send_msg_button_pressed.connect(touch_something_with_my_own_little_stringus)

   my_own_little_pingus.recieved_data.connect(_recieve_message)
   my_own_little_pingus.connection_established.connect(func(_id): menu._toggle_fields(true))

   my_own_little_pingus.set_name("my_own_little_pingus")
   add_child(my_own_little_pingus)

func touch_something_with_my_own_little_pingus(Addr: String) -> void:
   if my_own_little_pingus:
      my_own_little_pingus.TargetAddr = Addr
func touch_something_with_my_own_little_stringus(Msg: String) -> void:
   if my_own_little_pingus:
      my_own_little_pingus.send_data(MSG_DATA_TYPE, Msg.to_utf8_buffer())

func _recieve_message(_sender_id: int, data_type: int, data: PackedByteArray) -> void:
   match data_type:
      PingusPrime.DataTypes.CONTROL:
         menu.MESSAGE_LABEL.text = data.get_string_from_utf8()
         if my_own_little_pingus.ExternAddr != "":
            menu._set_ip_label(my_own_little_pingus.ExternAddr)
      MSG_DATA_TYPE:
         menu._append_to_chatlog("[THEM]: " + data.get_string_from_utf8())
