package core

import "core:c"
import "core:log"

EventCode :: enum u16 {
	CLEANUP         = 0x01,
	KEY_PRESSED     = 0x02,
	KEY_RELEASED    = 0x03,
	BUTTON_PRESSED  = 0x04,
	BUTTON_RELEASED = 0x05,
	MOUSE_MOVED     = 0x06,
	MOUSE_WHEEL     = 0x07,
	RESIZED         = 0x08,
}

EventPayload :: union {
	[2]i64,
	[2]u64,
	[2]f64,
	[4]i32,
	[4]u32,
	[4]f32,
	[8]i16,
	[8]u16,
	[16]i8,
	[16]u8,
}

EventReciever :: struct {
	listener: rawptr,
	callback: on_event,
}

EventEntry :: [dynamic]EventReciever
EventRegistry :: [dynamic]EventEntry

on_event :: proc(code: u16, sender: rawptr, listener: rawptr, payload: ^EventPayload) -> (handled: bool)

event_setup :: proc(registry: ^EventRegistry) -> (ok: bool) {

	registry^ = make(EventRegistry)
	return true
}

event_cleanup :: proc(registry: ^EventRegistry) {

	for entry in registry {
		delete(entry)
	}
}

event_register :: proc(code: u16, listener: rawptr, callback: on_event, registry: ^EventRegistry) -> (ok: bool) {

	if registry[code] == nil {
		registry[code] = make(EventEntry)
	}

	for reciever in registry[code] {
		if reciever.listener == listener {
			log.warn("event_register: listener %p already registered for event code %d", listener, code)
			return false
		}
	}

	reciever := EventReciever {
		listener = listener,
		callback = callback,
	}

	append(&registry[code], reciever)

	return true
}

event_unregister :: proc(code: u16, listener: rawptr, callback: on_event, registry: ^EventRegistry) -> (ok: bool) {

	if registry[code] == nil {
		log.warn("event_unregister: no listeners registered for event code %d", code)
		return false
	}

	for reciever, index in registry[code] {
		if reciever.listener == listener && reciever.callback == callback {
			ordered_remove(&registry[code], index)
			return true
		}
	}

	return false // not found
}

event_dispatch :: proc(code: u16, sender: rawptr, payload: ^EventPayload, registry: ^EventRegistry) -> (ok: bool) {

	if registry[code] == nil {
		log.warn("event_dispatch: no listeners registered for event code %d", code)
		return false
	}

	for reciever in registry[code] {
		if (reciever.callback(code, sender, reciever.listener, payload)) {
			return true // event handled, stop propagation
		}
	}

	return false // not handled
}
