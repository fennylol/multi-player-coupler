extends Node

@onready var menu: MenuNode = $CanvasLayer/Menu
#var my_own_little_pingus: Pingus
var my_own_little_pingus: PingusCannon


func _ready() -> void:
	#menu.connect_button_pressed.connect(touch_something_with_my_own_little_pingus)
	menu.connect_button_pressed.connect(touch_something_with_my_own_little_pingus)
	
	print(IP.get_local_addresses())
	
	var ipf := IPFinder.new()
	ipf.ip_finding_finished.connect(
		func(result: IPFinder.IPFinderError):
			if result == IPFinder.IPFinderError.SUCCESS:
				var addrport: Dictionary = ipf._get_ip_address()
				if addrport.keys().has("ADDRESS") and addrport.keys().has("PORT"):
					var external_ip  : PackedInt32Array = addrport["ADDRESS"]
					var external_port: int              = addrport["PORT"]
					var addr_str: String = str(external_ip[0])+"."+str(external_ip[1])+"."+str(external_ip[2])+"."+str(external_ip[3])+":"+str(external_port)
					menu._set_ip_label(addr_str)
					
					#my_own_little_pingus = Pingus.new()
					my_own_little_pingus = PingusCannon.new()
	)
	
	add_child(ipf)

#func touch_something_with_my_own_little_pingus(Addr: String, Port: int) -> void: if my_own_little_pingus: my_own_little_pingus._send_a_pingus(Addr, Port)
func touch_something_with_my_own_little_pingus(Addr: String, _Port: int) -> void: if my_own_little_pingus: add_child(my_own_little_pingus); my_own_little_pingus.target = Addr; my_own_little_pingus.scanning = true
