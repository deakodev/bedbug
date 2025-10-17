package core

import "base:runtime"
import "core:log"
import "core:text/edit"

@(private = "package")
g_context: runtime.Context

Options :: struct {
	window_title:  cstring,
	window_width:  u32,
	window_height: u32,
	target_fps:    u32,
	fullscreen:    bool,
}

Core :: struct {
	timer:          Timer,
	window:         Window,
	event_registry: EventRegistry,
	running:        bool,
}

Stage :: enum u8 {
	UNINITIALIZED,
	INITIALIZED,
}

core_get: proc() -> ^Core // callback core_get().xxx for layer access to core data

setup :: proc(core_ptr: ^Core, options: ^Options, callback: proc() -> ^Core) {

	g_context = context
	core_get = callback

	// event_setup(&core_ptr.event_registry)

	// core_ptr.window = window_setup(
	// 	options.window_title,
	// 	options.window_width,
	// 	options.window_height,
	// 	options.target_fps,
	// 	options.fullscreen,
	// )

	// timer_setup(&core_ptr.timer, options.target_fps)
}

cleanup :: proc(core: ^Core) -> (ok: bool) {

	window_cleanup(&core.window)
	event_cleanup(&core.event_registry)
	return true
}

global_context :: proc() -> runtime.Context {
	return g_context
}

when ODIN_OS == .Windows {
	BUILD_OS_STRING :: "build/win32"
} else when ODIN_OS == .Darwin {
	BUILD_OS_STRING :: "build/macos"
} else when ODIN_OS == .Linux {
	BUILD_OS_STRING :: "build/linux"
}

when ODIN_DEBUG {
	BUILD_MODE_STRING :: "/debug"
} else {
	BUILD_MODE_STRING :: "/release"
}

BUILD_DIR :: BUILD_OS_STRING + BUILD_MODE_STRING
