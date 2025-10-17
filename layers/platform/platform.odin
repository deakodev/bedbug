package platform

CLIENT_NAME :: #config(CLIENT_NAME, "Bedbug")
CLIENT_X :: #config(CLIENT_X, 100)
CLIENT_Y :: #config(CLIENT_Y, 100)
CLIENT_WIDTH :: #config(CLIENT_WIDTH, 1280)
CLIENT_HEIGHT :: #config(CLIENT_HEIGHT, 720)

// Window :: struct {
// 	title:         cstring,
// 	width, height: int,
// 	dpi_scale:     f32,
// 	iconified:     bool,
// }

Platform :: struct {
	_internal: rawptr,
}

platform_setup: proc(platform: ^Platform) -> (ok: bool) = _platform_setup

platform_message_dispatch: proc() = _platform_message_dispatch

platform_offscreen_buffer: proc(platform: ^Platform) -> ^OffscreenBuffer = _platform_offscreen_buffer

platform_window_buffer_display: proc(platform: ^Platform) = _platform_window_buffer_display
