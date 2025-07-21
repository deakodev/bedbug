package core

core: proc() -> ^Core

Core :: struct {
	window: Window,
}

set_callback :: proc(cb: proc() -> ^Core) {
	core = cb
}
