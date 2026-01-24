extends Node

@onready var menu: MenuNode = $CanvasLayer/Menu
var my_own_little_pingus: PingusPrime = PingusPrime.new()

func _ready() -> void:
	menu.connect_button_pressed.connect(touch_something_with_my_own_little_pingus)
	menu.send_msg_button_pressed.connect()
	my_own_little_pingus.message_recieved.connect(_print_message)
	my_own_little_pingus.set_name("my_own_little_pingus")
	add_child(my_own_little_pingus)
	
	var ipg := IPGopher.new()
	ipg.ip_fetching_finished.connect(
		func(result: IPGopher.IpFetchingErrs):
			match result:
				IPGopher.IpFetchingErrs.OK:
					menu._set_ip_label(ipg.get_address_as_string())
				IPGopher.IpFetchingErrs.BAD_RESULT:
					printerr("BAD_RESULT. Retrying... ")
					ipg._attempt_addr_fetch()
				IPGopher.IpFetchingErrs.BAD_RESPONSE:
					printerr("BAD_RESPONSE. Retrying... ")
					ipg._attempt_addr_fetch()
				IPGopher.IpFetchingErrs.BAD_IP:
					printerr("BAD_IP. Retrying... ")
					ipg._attempt_addr_fetch()
	)
	ipg.set_name("IPGopher")
	add_child(ipg)

func touch_something_with_my_own_little_pingus(Addr: String) -> void:
	if my_own_little_pingus:
		my_own_little_pingus.TargetAddr = Addr
func touch_something_with_my_own_little_stringus(Msg: String) -> void:
	if my_own_little_pingus:
		my_own_little_pingus.send_stringus(Msg)

func _print_message(msg: String) -> void:
	menu.MESSAGE_LABEL.text = msg
	if my_own_little_pingus.PingusState == PingusPrime.PingusStates.CONNECTED:
		menu._toggle_fields(true)
