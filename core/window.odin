package core

import "base:runtime"
import "core:log"
import "vendor:glfw"

@(private = "file")
g_foreign_context: runtime.Context

Window :: struct {
	handle:    glfw.WindowHandle,
	iconified: bool,
	resized:   bool,
}

window_setup :: proc(title: cstring, width: i32, height: i32) -> (window: Window) {

	log.info("setting up window...")

	glfw.SetErrorCallback(proc "c" (code: i32, description: cstring) {
		context = g_foreign_context
		log.errorf("glfw %i: %s", code, description)
	})

	if !glfw.Init() {
		log.panic("failed to initialize glfw.")
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)
	glfw.WindowHint(glfw.SCALE_TO_MONITOR, glfw.TRUE)

	window.handle = glfw.CreateWindow(width, height, title, nil, nil)
	if window.handle == nil {
		log.panic("failed to create glfw window.")
	}

	glfw.SetWindowUserPointer(window.handle, core())

	glfw.SetFramebufferSizeCallback(window.handle, proc "c" (handle: glfw.WindowHandle, _, _: i32) {
		core := cast(^Core)glfw.GetWindowUserPointer(handle)
		core.window.resized = true
	})

	glfw.SetWindowIconifyCallback(window.handle, proc "c" (handle: glfw.WindowHandle, iconified: i32) {
		core := cast(^Core)glfw.GetWindowUserPointer(handle)
		core.window.iconified = bool(iconified)
	})

	return window
}

window_cleanup :: proc() {

	if core().window.handle != nil {
		glfw.DestroyWindow(core().window.handle)
		glfw.Terminate()
	}
}

window_poll_events :: proc() {

	glfw.PollEvents()
}

window_should_close :: proc() -> bool {

	return bool(glfw.WindowShouldClose(core().window.handle))
}

window_wait_events :: proc() {

	glfw.WaitEvents()
}
