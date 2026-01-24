extends Node
class_name  PingusPrime
# ========= #
# variables #
# ========= #
enum PingusStates {NOT_STARTED, SPRAYING, INFORMING, CONNECTED}
var  PingusState: PingusStates  = PingusStates.NOT_STARTED
var  Udp        : PacketPeerUDP = PacketPeerUDP.new()
var  TargetAddr : String        = "":
	set(NewAddress):
		var regex = RegEx.new()
		regex.compile("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
		var result = regex.search(NewAddress)
		if result: TargetAddr = NewAddress
var  TargetPort : int           = -1:
	set(NewPort):
		var regex = RegEx.new()
		regex.compile("^(0|[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$")
		var result = regex.search(str(NewPort))
		if result: TargetPort = NewPort
var  ExternPort : int           = -1:
	set(NewPort):
		var regex = RegEx.new()
		regex.compile("^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$")
		var result = regex.search(str(NewPort))
		if result: ExternPort = NewPort
#var  PairedPorts: Array[int]    = []
var  LastPingus : float         = -1
const PINGUSTIME: float         = 15.0
signal message_recieved(msg: String)

func _init(local_port: int = 0) -> void:
	var bind_err = Udp.bind(local_port)
	if bind_err != OK: printerr("PingusPrime: failed to bind UDP socket"); return

func _process(delta: float) -> void:
	match PingusState:
		# NOT_STARTED: the PingusPrime has not begun attempting a connection.
		# -> SPRAYING: once a target is set, it will begin spraying packets at 
		# the target.
		PingusStates.NOT_STARTED:
			if TargetAddr != "" and TargetPort == -1:
				PingusState = PingusStates.SPRAYING
				message_recieved.emit("Attempting to connect to " + TargetAddr)
		# SPRAYING: the PingusPrime is trying every valid port on the target.
		# (and the target is doing the same.)
		# -> INFORMING: when a packet is recieved, if it is the bytes 0x00..0x0F,
		# the target is not aware of the PingusPrime and must be informed. if it
		# is NOT 0x00..0x0F, the target is informing the PingusPrime of connection.
		PingusStates.SPRAYING:
			spray_pingus()
			if Udp.get_available_packet_count() > 0:
				var msg = Udp.get_packet()
				var pkt_addr = Udp.get_packet_ip()
				var pkt_port = Udp.get_packet_port()
				TargetAddr = pkt_addr
				TargetPort = pkt_port
				message_recieved.emit("Establishing connection to " + TargetAddr + ":" + str(TargetPort))
				if TargetAddr != "" and TargetPort >= 1:
					PingusState = PingusStates.INFORMING
		# INFORMING: the PingusPrime has recieved a valid packet. it is sending
		# the target's port to the target.
		# -> CONNECTED: when a packet is recieved, if it is NOT 0x00..0x0F, the 
		# target is also informing the PingusPrime of connection.
		PingusStates.INFORMING:
			inform_pingus()
			if Udp.get_available_packet_count() > 0:
				var msg := Udp.get_packet()
				if msg.size() != 16:
					ExternPort = int(msg.get_string_from_utf8())
					message_recieved.emit("Extablished connection to " + TargetAddr + ":" + str(TargetPort) + " from local port " + str(ExternPort))
					PingusState = PingusStates.CONNECTED
		# CONNECTED: both the PingusPrime and the target are aware of each other.
		# continually send pings to keep the connection alive.
		PingusStates.CONNECTED:
			if Udp.get_available_packet_count() > 0:
				var msg := Udp.get_packet()
				print("Recived PINGUS:", msg)
			
			LastPingus += delta
			if LastPingus >= PINGUSTIME:
				LastPingus -= PINGUSTIME
				timed_pingus()
# ============== #
# packet sending #
# ============== #
# PingusStates.SPRAYING
func spray_pingus() -> void:
	var count = 0
	while count < 100:
		count += 1
		TargetPort += 1; 
		if TargetPort >= 65535 or TargetPort < 1: TargetPort = 1
		Udp.set_dest_address(TargetAddr, TargetPort)
		var packet = PackedByteArray([
			0x0, 0x1, 0x2, 0x3, 
			0x4, 0x5, 0x6, 0x7, 
			0x8, 0x9, 0xA, 0xB, 
			0xC, 0xD, 0xE, 0xF
		])
		var send_err = Udp.put_packet(packet)
		if send_err != OK: printerr("Failed to send pingus to ", TargetAddr, ":", TargetPort)
		elif not TargetPort%1000: message_recieved.emit("Spraying packet #" + str(TargetPort) + " to " + TargetAddr)
# PingusStates.INFORMING
func inform_pingus() -> void:
	var count = 0
	while count < 100:
		count += 1
		Udp.set_dest_address(TargetAddr, TargetPort)
		var packet = PackedByteArray([TargetPort])
		var send_err = Udp.put_packet(packet)
		if send_err != OK: printerr("Failed to send pingus to ", TargetAddr, ":", TargetPort)
		elif count == 10: message_recieved.emit("Informing " + TargetAddr +" at port: " + str(TargetPort))
# PingusStates.CONNECTED
func timed_pingus() -> void:
	Udp.set_dest_address(TargetAddr, TargetPort)
	var packet = PackedByteArray(PackedInt32Array([6,7]))
	var send_err = Udp.put_packet(packet)
	if send_err != OK: printerr("Failed to send pingus to ", TargetAddr, ":", TargetPort)
	else: message_recieved.emit("Preventing timeout with " + TargetAddr)
