extends RefCounted
## Playtest agent external policy bridge (docs/features/playtest-agent.md, "Wire format"). The
## game is the TCP client of an out-of-process policy server on 127.0.0.1 and speaks
## line-delimited JSON: one UTF-8 JSON object per line. Each decision blocks the game for at most
## `timeout_ms`; the game is frozen meanwhile, so a slow policy costs wall time, not fairness.
## Any failure (no server, timeout, bad reply, unknown key) returns "" and the caller falls back.

const PROTOCOL := 1
const HOST := "127.0.0.1"
const CONNECT_MS := 3000
const POLL_USEC := 500

var connected := false
## Why the last request failed ("" after a success).
var error := ""
var _peer := StreamPeerTCP.new()
var _pending := ""


func connect_to(port: int, hello: Dictionary) -> bool:
	if _peer.connect_to_host(HOST, port) != OK:
		error = "connect_failed"
		return false
	var deadline := Time.get_ticks_msec() + CONNECT_MS
	while Time.get_ticks_msec() < deadline:
		_peer.poll()
		match _peer.get_status():
			StreamPeerTCP.STATUS_CONNECTED:
				connected = true
				var message := hello.duplicate()
				message["type"] = "hello"
				message["protocol"] = PROTOCOL
				return send(message)
			StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
				break
		OS.delay_usec(POLL_USEC)
	error = "connect_timeout"
	return false


func send(message: Dictionary) -> bool:
	if not connected:
		return false
	var bytes := (JSON.stringify(message) + "\n").to_utf8_buffer()
	if _peer.put_data(bytes) != OK:
		_disconnect("send_failed")
		return false
	return true


## Sends one decision request and waits for the matching `action` reply. Returns the chosen key,
## or "" with `error` set to timeout, disconnected, bad_reply or not_connected.
func decide(
	tick: int, state: Dictionary, candidates: Array, hint: String, timeout_ms: int
) -> String:
	error = ""
	if not connected:
		error = "not_connected"
		return ""
	var request := {
		"type": "decide", "tick": tick, "state": state, "candidates": candidates, "hint": hint
	}
	if not send(request):
		return ""
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var line := _read_line()
		if not connected:
			return ""
		if line.is_empty():
			OS.delay_usec(POLL_USEC)
			continue
		var reply = JSON.parse_string(line)
		if not reply is Dictionary or reply.get("type") != "action":
			error = "bad_reply"
			return ""
		if int(reply.get("tick", -1)) != tick:
			continue  # A late answer to an earlier, timed-out request.
		var key = reply.get("key")
		if not key is String:
			error = "bad_reply"
			return ""
		return key
	error = "timeout"
	return ""


func close(summary: Dictionary) -> void:
	if connected:
		send({"type": "bye", "summary": summary})
		_peer.poll()
	_disconnect("")


func _read_line() -> String:
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_disconnect("disconnected")
		return ""
	var available := _peer.get_available_bytes()
	if available > 0:
		var chunk: Array = _peer.get_data(available)
		if chunk[0] == OK:
			_pending += (chunk[1] as PackedByteArray).get_string_from_utf8()
	var end := _pending.find("\n")
	if end < 0:
		return ""
	var line := _pending.substr(0, end).strip_edges()
	_pending = _pending.substr(end + 1)
	return line


func _disconnect(reason: String) -> void:
	if connected:
		_peer.disconnect_from_host()
	connected = false
	if not reason.is_empty():
		error = reason
