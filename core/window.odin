package core

import "base:runtime"
import "core:log"
import "vendor:glfw"

@(private = "file")
g_foreign_context: runtime.Context

Window :: struct {
	handle:    glfw.WindowHandle,
	fps:       u32,
	iconified: bool,
	resized:   bool,
}

window_setup :: proc(title: cstring, width: u32, height: u32, fps: u32, fullscreen: bool) -> (window: Window) {

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

	width := i32(width)
	height := i32(height)
	window.fps = fps

	monitor: glfw.MonitorHandle
	mode: ^glfw.VidMode

	if fullscreen {
		monitor = glfw.GetPrimaryMonitor()
		mode = glfw.GetVideoMode(monitor)

		width = mode.width
		height = mode.height
		window.fps = u32(mode.refresh_rate)

		glfw.WindowHint(glfw.RED_BITS, mode.red_bits)
		glfw.WindowHint(glfw.GREEN_BITS, mode.green_bits)
		glfw.WindowHint(glfw.BLUE_BITS, mode.blue_bits)
		glfw.WindowHint(glfw.REFRESH_RATE, mode.refresh_rate)
	}

	window.handle = glfw.CreateWindow(width, height, title, nil, nil)
	if window.handle == nil {
		log.panic("failed to create glfw window.")
	}

	if fullscreen {
		glfw.SetWindowMonitor(window.handle, monitor, 0, 0, mode.width, mode.height, mode.refresh_rate)
	}

	glfw.SetWindowUserPointer(window.handle, core())

	glfw.SetFramebufferSizeCallback(window.handle, proc "c" (handle: glfw.WindowHandle, _, _: i32) {
		core := cast(^Core)glfw.GetWindowUserPointer(handle)
		core.window.resized = true
	})

	glfw.SetWindowIconifyCallback(window.handle, proc "c" (handle: glfw.WindowHandle, _: i32) {
		core := cast(^Core)glfw.GetWindowUserPointer(handle)
		core.window.iconified = true
	})

	glfw.SetWindowMaximizeCallback(window.handle, proc "c" (handle: glfw.WindowHandle, maximize: i32) {
		core := cast(^Core)glfw.GetWindowUserPointer(handle)
		core.window.iconified = false

		if bool(maximize) {
			monitor := glfw.GetPrimaryMonitor()
			mode := glfw.GetVideoMode(monitor)

			core.window.fps = u32(mode.refresh_rate)

			glfw.WindowHint(glfw.RED_BITS, mode.red_bits)
			glfw.WindowHint(glfw.GREEN_BITS, mode.green_bits)
			glfw.WindowHint(glfw.BLUE_BITS, mode.blue_bits)
			glfw.WindowHint(glfw.REFRESH_RATE, mode.refresh_rate)

			glfw.SetWindowMonitor(core.window.handle, monitor, 0, 0, mode.width, mode.height, mode.refresh_rate)
		}
	})

	return window
}

window_cleanup :: proc() -> (ok: bool) {

	if core().window.handle != nil {
		glfw.DestroyWindow(core().window.handle)
		glfw.Terminate()
		return true
	}

	return false
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

monitor_resolution :: proc() -> (u32, u32) {

	mode := glfw.GetVideoMode(glfw.GetPrimaryMonitor())
	log.ensure(mode != nil)
	return u32(mode.width), u32(mode.height)
}
