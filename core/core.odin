package core

core: proc() -> ^Core

Core :: struct {
	window: Window,
	timer:  Timer,
}

set_callback :: proc(cb: proc() -> ^Core) {
	core = cb
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
