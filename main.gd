extends Node

@onready var menu: MenuNode = $CanvasLayer/Menu
var my_own_little_pingus: PingusPrime = PingusPrime.new()

func _ready() -> void:
   print(IP.get_local_addresses())
   var arguments = {}
   for argument in OS.get_cmdline_args():
      # Parse valid command-line arguments into a dictionary
      if argument.find("=") > -1:
         var key_value = argument.split("=")
         arguments[key_value[0].lstrip("--")] = key_value[1]
   if arguments.keys().has("port"):
      print(arguments["port"])
      my_own_little_pingus = PingusPrime.new(int(arguments["port"]))
   
   menu.connect_button_pressed.connect(touch_something_with_my_own_little_pingus)
   menu.send_msg_button_pressed.connect(touch_something_with_my_own_little_stringus)
   
   var handle_IP_singleton: Callable 
   handle_IP_singleton = func(msg: String, type: PingusPrime.SignalTypes) -> void:
      if msg != "IP RECIEVED" or type != PingusPrime.SignalTypes.CONTROL: printerr("INVALID MESSAGE ARRIVED EARLY")
      for function in my_own_little_pingus.message_recieved.get_connections():
         my_own_little_pingus.message_recieved.disconnect(function["callable"])
      my_own_little_pingus.message_recieved.connect(_recieve_message)
      menu._set_ip_label(my_own_little_pingus.ExternAddr)
   my_own_little_pingus.message_recieved.connect(handle_IP_singleton)
   
   my_own_little_pingus.set_name("my_own_little_pingus")
   add_child(my_own_little_pingus)

func touch_something_with_my_own_little_pingus(Addr: String) -> void:
   if my_own_little_pingus:
      my_own_little_pingus.TargetAddr = Addr
func touch_something_with_my_own_little_stringus(Msg: String) -> void:
   if my_own_little_pingus:
      my_own_little_pingus.send_stringus(Msg)

func _recieve_message(Msg: String, Type: PingusPrime.SignalTypes) -> void:
   match Type:
      PingusPrime.SignalTypes.DATA:
         menu._append_to_chatlog("[THEM]: " + Msg)
      PingusPrime.SignalTypes.CONTROL:
         menu.MESSAGE_LABEL.text = Msg
   if my_own_little_pingus.PingusState == PingusPrime.PingusStates.CONNECTED:
      menu._toggle_fields(true)
