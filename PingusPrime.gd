extends Node
class_name  PingusPrime
# ========= #
# constants #
# ========= #
enum  PingusStates {NOT_STARTED, SPRAYING, INFORMING, CONNECTED}
enum  SignalTypes {DATA, CONTROL}
enum  PingusTypes {SPRAY = 0x5912A459, INFORM = 0x115F0125, KEEPALIVE = 0x8EE9115E, STRING = 0x1E77E125, INTEGER = 0x12345678, FLOAT = 0xF10A7159, DATA = 0xDA7ADA7A, CONTROL = 0x5CA1AB1E}
const TYPE_SIZE  : int           = 4
const RETRY_TIME : float         = 2.5
const MAX_RETRIES: int           = 5
const SPRAY_RATE : int           = 100
const INFORM_RATE: int           = 10
const KEEP_ALIVE_TIME  : float   = 15.0
const KEEP_ALIVE_PINGUS: int     = 0x1153
# ========= #
# variables #
# ========= #
var PingusState: PingusStates  = PingusStates.NOT_STARTED
var Udp        : PacketPeerUDP = PacketPeerUDP.new()
var TargetAddr : String        = "":
   set(NewAddress):
      var regex = RegEx.new()
      regex.compile("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
      var result = regex.search(NewAddress)
      if result: TargetAddr = NewAddress
var TargetPort : int           = -1:
   set(NewPort):
      var regex = RegEx.new()
      regex.compile("^(0|[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$")
      var result = regex.search(str(NewPort))
      if result: TargetPort = NewPort
var ExternAddr : String        = "":
   set(NewAddress):
      var regex = RegEx.new()
      regex.compile("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
      var result = regex.search(NewAddress)
      if result: ExternAddr = NewAddress
var ExternPort : int           = -1:
   set(NewPort):
      var regex = RegEx.new()
      regex.compile("^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$")
      var result = regex.search(str(NewPort))
      if result: ExternPort = NewPort
var PingusTimer: float         = -1
signal message_recieved(msg: String, type: SignalTypes)
signal data_recieved(data: PackedByteArray)
#var  PairedPorts: Array[int]    = []
func _init(local_port: int = 0) -> void:
   var ipg := IPGopher.new()
   ipg.ip_fetching_finished.connect(
      func(result: IPGopher.IpFetchingErrs):
         var retry_on_fail: Callable = func(err_str: String):
            PingusTimer += 1
            if PingusTimer < MAX_RETRIES:
               printerr(err_str + " Retrying... ")
               await get_tree().create_timer(RETRY_TIME).timeout
               ipg._attempt_addr_fetch()
            else:
               printerr(err_str + " Aborting...")
         
         match result:
            IPGopher.IpFetchingErrs.OK:
               ExternAddr = ipg.get_address_as_string()
               message_recieved.emit("IP RECIEVED", SignalTypes.CONTROL)
               ipg.queue_free()
            IPGopher.IpFetchingErrs.BAD_RESULT  : retry_on_fail.call("BAD_RESULT.")
            IPGopher.IpFetchingErrs.BAD_RESPONSE: retry_on_fail.call("BAD_RESPONSE.")
            IPGopher.IpFetchingErrs.BAD_IP      : retry_on_fail.call("BAD_IP.")
   )
   ipg.set_name("IPGopher")
   add_child(ipg)
   
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
            message_recieved.emit("Attempting to connect to " + TargetAddr, SignalTypes.CONTROL)
      # SPRAYING: the PingusPrime is trying every valid port on the target.
      # (and the target is doing the same.)
      # -> INFORMING: when a packet is recieved, if it is the bytes 0x00..0x0F,
      # the target is not aware of the PingusPrime and must be informed. if it
      # is NOT 0x00..0x0F, the target is informing the PingusPrime of connection.
      PingusStates.SPRAYING:
         spray_pingus()
         if Udp.get_available_packet_count() > 0:
            var pkt = Udp.get_packet()
            if pkt.size() < TYPE_SIZE: message_recieved.emit("ERROR: Encountered undersized packet while spraying.", SignalTypes.CONTROL); return
            var pkt_type: PingusTypes = pkt.decode_u32(0) as PingusTypes
            if pkt_type != PingusTypes.SPRAY and pkt_type != PingusTypes.INFORM: message_recieved.emit("ERROR: Encountered incorrect packet type while spraying.", SignalTypes.CONTROL); return
            var _pkt_ip = Udp.get_packet_ip()
            var _pkt_port = Udp.get_packet_port()
            TargetAddr = Udp.get_packet_ip()
            TargetPort = Udp.get_packet_port()
            message_recieved.emit("Establishing connection to " + TargetAddr + ":" + str(TargetPort), SignalTypes.CONTROL)
            if TargetAddr != "" and TargetPort >= 1:
               PingusState = PingusStates.INFORMING
      # INFORMING: the PingusPrime has recieved a valid packet. it is sending
      # the target's port to the target.
      # -> CONNECTED: when a packet is recieved, if it is NOT 0x00..0x0F, the 
      # target is also informing the PingusPrime of connection.
      PingusStates.INFORMING:
         inform_pingus()
         if Udp.get_available_packet_count() > 0:
            var pkt := Udp.get_packet()
            if pkt.size() < TYPE_SIZE: message_recieved.emit("ERROR: Encountered undersized packet while informing.", SignalTypes.CONTROL); return
            var pkt_type: PingusTypes = pkt.decode_u32(0) as PingusTypes
            if pkt_type != PingusTypes.SPRAY and pkt_type != PingusTypes.INFORM: message_recieved.emit("ERROR: Encountered incorrect packet type while informing.", SignalTypes.CONTROL); return
            if pkt_type == PingusTypes.INFORM:
               ExternPort = pkt.decode_u16(0)
               message_recieved.emit("PingusPrime: Extablished connection to " + TargetAddr + ":" + str(TargetPort) + " from local port " + str(ExternPort), SignalTypes.CONTROL)
               PingusState = PingusStates.CONNECTED
      # CONNECTED: both the PingusPrime and the target are aware of each other.
      # continually send pings to keep the connection alive.
      PingusStates.CONNECTED:
         if Udp.get_available_packet_count() > 0:
            var pkt := Udp.get_packet()
            if pkt.size() < TYPE_SIZE: message_recieved.emit("ERROR: Encountered undersized packet while connected.", SignalTypes.CONTROL); return
            if not Udp.get_packet_ip() == TargetAddr or not Udp.get_packet_port() == TargetPort: message_recieved.emit("ERROR: Encountered packet from unidentified source while connected.", SignalTypes.CONTROL); return
            
            var pkt_type: PingusTypes = pkt.decode_u32(0) as PingusTypes
            if   pkt_type == PingusTypes.INFORM   : message_recieved.emit("Extablished connection to " + TargetAddr + ":" + str(TargetPort) + " from local port " + str(ExternPort), SignalTypes.CONTROL)
            elif pkt_type == PingusTypes.KEEPALIVE: message_recieved.emit(TargetAddr + ":" + str(TargetPort) + " is keeping connection to local port " + str(ExternPort) + " alive", SignalTypes.CONTROL)
            elif pkt_type == PingusTypes.STRING   : message_recieved.emit(pkt.slice(TYPE_SIZE).get_string_from_utf8(), SignalTypes.DATA); PingusTimer = 0.0
            elif pkt_type == PingusTypes.DATA     : data_recieved.emit(pkt.slice(TYPE_SIZE)); PingusTimer = 0.0
            else: message_recieved.emit("ERROR: Encountered incorrect packet type while connected.", SignalTypes.CONTROL); return
         
         PingusTimer += delta
         if PingusTimer >= KEEP_ALIVE_TIME:
            PingusTimer -= KEEP_ALIVE_TIME
            timed_pingus()
# ============== #
# packet sending #
# ============== #
# PingusStates.SPRAYING
func spray_pingus() -> void:
   var count = SPRAY_RATE
   while count > 0:
      count -= 1
      TargetPort -= 1; 
      if TargetPort >= 65535 or TargetPort < 1: TargetPort = 65534
      Udp.set_dest_address(TargetAddr, TargetPort)
      
      var pkt := PackedByteArray()
      pkt.resize(TYPE_SIZE)
      pkt.encode_u32(0, PingusTypes.SPRAY)
      
      var send_err = Udp.put_packet(pkt)
      if send_err != OK: printerr("Failed to send spray to ", TargetAddr, ":", TargetPort)
      elif not TargetPort%107: message_recieved.emit("Spraying port " + str(TargetPort) + " on " + TargetAddr, SignalTypes.CONTROL)
# PingusStates.INFORMING
func inform_pingus() -> void:
   var count = INFORM_RATE
   while count > 0:
      count -= 1
      Udp.set_dest_address(TargetAddr, TargetPort)
      
      var pkt := PackedByteArray()
      pkt.resize(TYPE_SIZE + 2)
      pkt.encode_u32(0, PingusTypes.INFORM)
      pkt.encode_u16(TYPE_SIZE, TargetPort)
      
      var send_err = Udp.put_packet(pkt)
      if send_err != OK: printerr("Failed to send inform to ", TargetAddr, ":", TargetPort)
      elif count==1: message_recieved.emit("Informing " + TargetAddr + " at port: " + str(TargetPort), SignalTypes.CONTROL)
# PingusStates.CONNECTED
func timed_pingus() -> void:
   Udp.set_dest_address(TargetAddr, TargetPort)
   
   var pkt := PackedByteArray()
   pkt.resize(TYPE_SIZE)
   pkt.encode_u32(0, PingusTypes.KEEPALIVE)
   
   var send_err = Udp.put_packet(pkt)
   if send_err != OK: printerr("Failed to send keepalive to ", TargetAddr, ":", TargetPort)
   else: message_recieved.emit("Preventing timeout with " + TargetAddr + ":" + str(TargetPort), SignalTypes.CONTROL)
func send_stringus(msg: String) -> void:
   Udp.set_dest_address(TargetAddr, TargetPort)
   
   var pkt := PackedByteArray()
   pkt.resize(TYPE_SIZE)
   pkt.encode_u32(0, PingusTypes.STRING)
   pkt.append_array(PackedStringArray([msg]).to_byte_array())
   
   var send_err = Udp.put_packet(pkt)
   if send_err != OK: printerr("Failed to send stringus to ", TargetAddr, ":", TargetPort)
   else: message_recieved.emit("Sent message to " + TargetAddr + ":" + str(TargetPort), SignalTypes.CONTROL)
func send_data(data: PackedByteArray) -> void:
   Udp.set_dest_address(TargetAddr, TargetPort)
   
   var pkt := PackedByteArray()
   pkt.resize(TYPE_SIZE)
   pkt.encode_u32(0, PingusTypes.DATA)
   pkt.append_array(data)
   
   var send_err = Udp.put_packet(pkt)
   if send_err != OK: printerr("Failed to send data to ", TargetAddr, ":", TargetPort)
   else: message_recieved.emit("Sent data to " + TargetAddr + ":" + str(TargetPort), SignalTypes.CONTROL)

# ======================== #
# small utility class to   #
# fetch external facing IP #
# ======================== #
class IPGopher extends Node:
   const  IP_FETCHING_URL = "https://api.ipify.org"
   enum   IpFetchingErrs {OK, BAD_RESULT, BAD_RESPONSE, BAD_IP}
   signal ip_fetching_finished(err: IpFetchingErrs)
   var    Address: PackedInt32Array
   
   func get_address()           -> PackedInt32Array: return Address
   func get_address_as_string() -> String: return str(Address[0])+"."+str(Address[1])+"."+str(Address[2])+"."+str(Address[3])
   func _ready()                -> void: _attempt_addr_fetch()
   func _attempt_addr_fetch()   -> void:
      var http_req := HTTPRequest.new()
      add_child(http_req)
      http_req.request_completed.connect(
         func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
            if result        != HTTPRequest.Result.RESULT_SUCCESS  : ip_fetching_finished.emit(IpFetchingErrs.BAD_RESULT)  ; http_req.queue_free(); return
            if response_code != HTTPClient.ResponseCode.RESPONSE_OK: ip_fetching_finished.emit(IpFetchingErrs.BAD_RESPONSE); http_req.queue_free(); return
            var IP_str: PackedStringArray = body.get_string_from_utf8().split(".")
            if IP_str.size() != 4                                  : ip_fetching_finished.emit(IpFetchingErrs.BAD_IP)      ; http_req.queue_free(); return
            Address = PackedInt32Array([int(IP_str[0]), int(IP_str[1]), int(IP_str[2]), int(IP_str[3])])
            ip_fetching_finished.emit(IpFetchingErrs.OK)
            http_req.queue_free()
      )
      http_req.request(IP_FETCHING_URL)
