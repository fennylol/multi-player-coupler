extends Node
class_name  PingusPrime
# ========= #
# constants #
# ========= #
enum  PingusStates {NOT_STARTED, SPRAYING, INFORMING, CONNECTED}
enum  PingusTypes {SPRAY = 0x5912A459, INFORM = 0x115F0125, KEEPALIVE = 0x8EE9115E, DATA = 0xDA7ADA7A}
enum  DataTypes {CONTROL = 0xC0}
const TYPE_SIZE      : int   = 4
const ID_SIZE        : int   = 4
# header layout: [pkt_type u32][sender NetworkID u32][target NetworkID u32].
# target 0 means "anyone" (manual connects, before the peer's ID is known).
const HEADER_SIZE    : int   = TYPE_SIZE + ID_SIZE + ID_SIZE
const DATA_TYPE_SIZE : int   = 1
const RETRY_TIME     : float = 2.5
const MAX_RETRIES    : int   = 5
const KEEP_ALIVE_TIME: float = 5.0
# ========= #
# variables #
# ========= #
var Udp         : PacketPeerUDP = PacketPeerUDP.new()
var PingusState : PingusStates  = PingusStates.NOT_STARTED
var PingusTimer : float         = -1
var TargetAddr  : String        = "":
   set(NewAddress):
      var regex = RegEx.new()
      regex.compile("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
      var result = regex.search(NewAddress)
      if result: TargetAddr = NewAddress
var TargetPort  : int           = -1:
   set(NewPort):
      var regex = RegEx.new()
      regex.compile("^(0|[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$")
      var result = regex.search(str(NewPort))
      if result: TargetPort = NewPort
var TargetID    : int           = 0
var ExternAddr  : String        = "":
   set(NewAddress):
      var regex = RegEx.new()
      regex.compile("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
      var result = regex.search(NewAddress)
      if result: ExternAddr = NewAddress
var ExternPort  : int           = -1:
   set(NewPort):
      var regex = RegEx.new()
      regex.compile("^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$")
      var result = regex.search(str(NewPort))
      if result: ExternPort = NewPort
var NetworkID   : int           = 0
var SprayPortMin: int           = 49152:
   set(NewPort):
      var regex = RegEx.new()
      regex.compile("^(0|[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$")
      var result = regex.search(str(NewPort))
      if result: SprayPortMin = NewPort
var SprayPortMax: int           = 65535:
   set(NewPort):
      var regex = RegEx.new()
      regex.compile("^(0|[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$")
      var result = regex.search(str(NewPort))
      if result: SprayPortMax = NewPort
var SprayRate   : int           = 3000
# ======= #
# signals #
# ======= #
signal recieved_data(sender_id: int, data_type: int, data: PackedByteArray)
signal connection_established(sender_id: int)

func _ready() -> void:
   var bind_err = Udp.bind(0)
   if bind_err != OK: printerr("PingusPrime: failed to bind UDP socket"); return
func _init(external_address: String = "", network_id: int = 0) -> void:
   NetworkID = network_id
   ExternAddr = external_address
   if NetworkID  == 0 : _discover_network_id()
   if ExternAddr == "": _discover_address()   
func _discover_network_id() -> void:
   while NetworkID == 0:
      seed((Time.get_unix_time_from_system()*100000) as int)
      NetworkID = randi()
func _discover_address() -> void:
   var ipg := IPGopher.new()
   ipg.ip_fetching_finished.connect(
      func(result: IPGopher.IpFetchingErrs):
         var retry_on_fail: Callable = func(err_str: String):
            PingusTimer += 1
            if PingusTimer < MAX_RETRIES:
               _emit_control(err_str + " Retrying... ")
               await get_tree().create_timer(RETRY_TIME).timeout
               ipg._attempt_addr_fetch()
            else:
               _emit_control(err_str + " Aborting...")

         match result:
            IPGopher.IpFetchingErrs.OK:
               ExternAddr = ipg.get_address_as_string()
               _emit_control("External IP recieved: " + ExternAddr)
               ipg.queue_free()
            IPGopher.IpFetchingErrs.BAD_RESULT  : retry_on_fail.call("BAD_RESULT.")
            IPGopher.IpFetchingErrs.BAD_RESPONSE: retry_on_fail.call("BAD_RESPONSE.")
            IPGopher.IpFetchingErrs.BAD_IP      : retry_on_fail.call("BAD_IP.")
   )
   ipg.set_name("IPGopher")
   add_child(ipg)
# =================== #
# PingusState machine #
# =================== #
func _process(delta: float) -> void:
   if TargetAddr == "" or ExternAddr == "" or NetworkID == 0:
      if not PingusState == PingusStates.NOT_STARTED:
         PingusState = PingusStates.NOT_STARTED
         _emit_control("ERROR: Malformed %s: %s. Returning to NOT_STARTED..." % (["target IP address", "[NULL]"] if TargetAddr == "" else ["external IP address", "[NULL]"] if ExternAddr == "" else ["network ID", "0"] if NetworkID == 0 else ["error", "like... this one.."]))
   
   match PingusState:
      # NOT_STARTED: the PingusPrime has not begun attempting a connection.
      # -> SPRAYING: once a target is set, it will begin spraying packets at
      # the target.
      PingusStates.NOT_STARTED:
         if TargetAddr != "" and TargetPort == -1 and ExternAddr != "" and NetworkID != 0:
            PingusState = PingusStates.SPRAYING
            _emit_control("Attempting to connect to " + TargetAddr)
      # SPRAYING: the PingusPrime is trying every valid port on the target.
      # (and the target is doing the same.)
      # -> INFORMING: when a SPRAY or INFORM packet is recieved, the target
      # has found one of our ports so lock onto theirs and start informing.
      PingusStates.SPRAYING:
         _spray_pingus(delta)
         while Udp.get_available_packet_count() > 0:
            var pkt = Udp.get_packet()
            # packet validation
            if pkt.size() < HEADER_SIZE: _emit_control("ERROR: undersized packet while spraying."); continue
            var pkt_type : PingusTypes = pkt.decode_u32(0) as PingusTypes
            var sender_id: int         = pkt.decode_u32(TYPE_SIZE)
            var target_id: int         = pkt.decode_u32(TYPE_SIZE + ID_SIZE)
            if pkt_type != PingusTypes.SPRAY and pkt_type != PingusTypes.INFORM: _emit_control("ERROR: incorrect packet type while spraying."); continue
            if sender_id == NetworkID: continue # one of our own sockets (same-machine instance)
            if TargetID  != 0 and sender_id != TargetID: continue # not the peer this connection is for
            if target_id != 0 and target_id != NetworkID: continue # meant for a different instance at our address
            # data collection
            TargetID   = sender_id
            TargetAddr = Udp.get_packet_ip()
            TargetPort = Udp.get_packet_port()
            if TargetAddr != "" and TargetPort >= 1:
               # state changes before the control emit so listeners reacting to
               # control messages observe the up-to-date state.
               PingusState = PingusStates.INFORMING
               _emit_control("Establishing connection to " + TargetAddr + ":" + str(TargetPort), sender_id)
               break
      # INFORMING: the PingusPrime has recieved a valid packet. it is sending
      # the target's port to the target.
      # -> CONNECTED: when an INFORM packet is recieved, the target is also
      # aware of the connection.
      PingusStates.INFORMING:
         _inform_pingus(delta)
         while Udp.get_available_packet_count() > 0:
            var pkt := Udp.get_packet()
            # packet validation
            if pkt.size() < HEADER_SIZE: _emit_control("ERROR: undersized packet while informing."); continue
            var pkt_type : PingusTypes = pkt.decode_u32(0) as PingusTypes
            var sender_id: int         = pkt.decode_u32(TYPE_SIZE)
            var target_id: int         = pkt.decode_u32(TYPE_SIZE + ID_SIZE)
            if pkt_type != PingusTypes.SPRAY and pkt_type != PingusTypes.INFORM: _emit_control("ERROR: incorrect packet type while informing."); continue
            if sender_id == NetworkID: continue # one of our own sockets (same-machine instance)
            if TargetID  != 0 and sender_id != TargetID: continue # not the peer this connection is for
            if target_id != 0 and target_id != NetworkID: continue # meant for a different instance at our address
            # data collection
            if pkt_type == PingusTypes.INFORM:
               if pkt.size() < HEADER_SIZE + 2: _emit_control("ERROR: INFORM packet too small for port."); continue
               ExternPort = pkt.decode_u16(HEADER_SIZE)
               PingusState = PingusStates.CONNECTED
               _emit_control("Established connection to " + str(sender_id) + " (" + TargetAddr + ":" + str(TargetPort) + ") from local port " + str(ExternPort), sender_id)
               connection_established.emit(sender_id)
               # the peer sends INFORM in bursts; stop draining here or every
               # queued INFORM re-emits connection_established. leftovers are
               # handled next frame by the CONNECTED branch.
               break
      # CONNECTED: both the PingusPrime and the target are aware of each other.
      # continually send pings to keep the connection alive.
      PingusStates.CONNECTED:
         PingusTimer += delta
         if PingusTimer >= KEEP_ALIVE_TIME:
            PingusTimer -= KEEP_ALIVE_TIME
            _timed_pingus()

         while Udp.get_available_packet_count() > 0:
            var pkt := Udp.get_packet()
            # packet validation
            if pkt.size() < HEADER_SIZE:
               _emit_control("ERROR: undersized packet while connected.")
               continue
            if Udp.get_packet_ip() != TargetAddr or Udp.get_packet_port() != TargetPort:
               _emit_control("ERROR: packet from unidentified source.")
               continue
            var pkt_type : PingusTypes = pkt.decode_u32(0) as PingusTypes
            var sender_id: int         = pkt.decode_u32(TYPE_SIZE)
            var target_id: int         = pkt.decode_u32(TYPE_SIZE + ID_SIZE)
            if sender_id != TargetID or (target_id != 0 and target_id != NetworkID):
               _emit_control("ERROR: packet signed by unidentified sender.")
               continue
            # data handling
            match pkt_type:
               PingusTypes.INFORM:    _emit_control(str(sender_id) + " (" + TargetAddr + ":" + str(TargetPort) + ") re-confirmed connection", sender_id)
               PingusTypes.KEEPALIVE: _emit_control(str(sender_id) + " (" + TargetAddr + ":" + str(TargetPort) + ") is keeping connection alive", sender_id)
               PingusTypes.DATA:
                  if pkt.size() < HEADER_SIZE + DATA_TYPE_SIZE: _emit_control("ERROR: DATA packet missing type byte."); continue
                  recieved_data.emit(sender_id, pkt.decode_u8(HEADER_SIZE), pkt.slice(HEADER_SIZE + DATA_TYPE_SIZE))
                  PingusTimer = 0.0
               _: _emit_control("ERROR: incorrect packet type while connected.")
# ============== #
# packet sending #
# ============== #
## send typed application data. data_type is a single byte; values other than
## PingusPrime.CONTROL are free for the application to define.
func send_data(data_type: int, data: PackedByteArray = PackedByteArray()) -> void:
   Udp.set_dest_address(TargetAddr, TargetPort)
   var pkt := _make_header(PingusTypes.DATA)
   pkt.resize(HEADER_SIZE + DATA_TYPE_SIZE)
   pkt.encode_u8(HEADER_SIZE, data_type)
   pkt.append_array(data)
   var send_err = Udp.put_packet(pkt)
   if send_err != OK: _emit_control("ERROR: failed to send data to " + TargetAddr + ":" + str(TargetPort))
func _make_header(pkt_type: PingusTypes) -> PackedByteArray:
   var hdr := PackedByteArray()
   hdr.resize(HEADER_SIZE)
   hdr.encode_u32(0, pkt_type)
   hdr.encode_u32(TYPE_SIZE, NetworkID)
   hdr.encode_u32(TYPE_SIZE + ID_SIZE, TargetID)
   return hdr
func _emit_control(msg: String, sender_id: int = 0) -> void:
   recieved_data.emit(sender_id if sender_id else NetworkID, DataTypes.CONTROL, msg.to_utf8_buffer())
# PingusStates.SPRAYING
func _spray_pingus(delta) -> void:
   var count := ceili(SprayRate * delta)
   while count > 0:
      count -= 1
      TargetPort -= 1
      if TargetPort > SprayPortMax or TargetPort < SprayPortMin:
         TargetPort = SprayPortMax

      Udp.set_dest_address(TargetAddr, TargetPort)
      var send_err = Udp.put_packet(_make_header(PingusTypes.SPRAY))
      if send_err != OK: _emit_control("ERROR: failed to send spray to " + TargetAddr + ":" + str(TargetPort))
   _emit_control("Spraying port " + str(TargetPort) + " on " + TargetAddr)
# PingusStates.INFORMING
func _inform_pingus(delta) -> void:
   Udp.set_dest_address(TargetAddr, TargetPort)
   var count = ceili((SprayRate/5.0) * delta)
   while count > 0:
      count -= 1
      var pkt := _make_header(PingusTypes.INFORM)
      pkt.resize(HEADER_SIZE + 2)
      pkt.encode_u16(HEADER_SIZE, TargetPort)
      var send_err = Udp.put_packet(pkt)
      if send_err != OK: _emit_control("ERROR: failed to send inform to " + TargetAddr + ":" + str(TargetPort))
   _emit_control("Informing " + TargetAddr + " at port: " + str(TargetPort))
# PingusStates.CONNECTED
func _timed_pingus() -> void:
   Udp.set_dest_address(TargetAddr, TargetPort)
   var send_err = Udp.put_packet(_make_header(PingusTypes.KEEPALIVE))
   if send_err != OK: _emit_control("ERROR: failed to send keepalive to " + TargetAddr + ":" + str(TargetPort))
   else: _emit_control("Preventing timeout with " + TargetAddr + ":" + str(TargetPort))
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
