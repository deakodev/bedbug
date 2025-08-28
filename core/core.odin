package core

import "core:log"
import "core:text/edit"

Options :: struct {
	window_title:  Maybe(cstring),
	window_width:  Maybe(u32),
	window_height: Maybe(u32),
	target_fps:    Maybe(u32),
	fullscreen:    bool,
}

DEFAULT_OPTIONS: Options = {
	window_title  = "Bedbug",
	window_width  = 1200,
	window_height = 800,
	target_fps    = 60,
}

Core :: struct {
	window: Window,
	timer:  Timer,
}

core: proc() -> ^Core // callback core().xxx for layer access to core data

setup :: proc(core_ptr: ^Core, options: ^Options, callback: proc() -> ^Core) {

	core = callback

	options := options if options != nil else &DEFAULT_OPTIONS
	title := options.window_title.? or_else DEFAULT_OPTIONS.window_title.?
	width := options.window_width.? or_else DEFAULT_OPTIONS.window_width.?
	height := options.window_height.? or_else DEFAULT_OPTIONS.window_height.?
	fps := options.target_fps.? or_else DEFAULT_OPTIONS.target_fps.?
	fullscreen := options.fullscreen

	core_ptr.window = window_setup(title, width, height, fps, fullscreen)

	timer_setup(&core_ptr.timer, fps)
}

cleanup :: proc() -> (ok: bool) {

	window_cleanup() or_return
	return true
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
