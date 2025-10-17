package platform

import bc "bedbug:core"
import "core:log"
import "core:mem"
import win "core:sys/windows"

@(private = "file")
ProcessInternal :: struct {
	hinstance: win.HINSTANCE,
	hwnd:      win.HWND,
	hdc:       win.HDC,
	buffer:    OffscreenBuffer,
}

@(private = "package")
OffscreenBuffer :: struct {
	info:            win.BITMAPINFO,
	memory:          rawptr,
	width, height:   int,
	bytes_pitch:     int,
	bytes_per_pixel: int,
}

@(private = "file")
g_offscreen_buffer: ^OffscreenBuffer // non-owning

@(private = "file")
g_platform_initialized: bool

@(private = "package")
_platform_setup :: proc(platform: ^Platform) -> (ok: bool) {

	internal := new(ProcessInternal)

	_window_buffer_resize(&internal.buffer, 1280, 720)

	internal.hinstance = win.HINSTANCE(win.GetModuleHandleW(nil))
	if internal.hinstance == nil {
		log.error("failed to get win32 instance handle.")
		return false
	}

	win.SetProcessDpiAwarenessContext(win.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)

	window_class := win.WNDCLASSW {
		style         = win.CS_DBLCLKS | win.CS_VREDRAW | win.CS_HREDRAW | win.CS_OWNDC,
		lpfnWndProc   = _window_message_proc,
		lpszClassName = win.L("WindowClass"),
		hInstance     = internal.hinstance,
		hCursor       = win.LoadCursorA(nil, win.IDC_ARROW),
		hIcon         = win.LoadIconA(nil, win.IDI_APPLICATION),
	}

	result := win.RegisterClassW(&window_class)
	if result == 0 {
		log.error("failed to register win32 window class.")
		return false
	}

	window_style := win.WS_OVERLAPPEDWINDOW
	window_ex_style := win.WS_EX_APPWINDOW

	border_rect: win.RECT
	win.AdjustWindowRectEx(&border_rect, window_style, false, window_ex_style)

	window_x := CLIENT_X + border_rect.left
	window_y := CLIENT_Y + border_rect.top
	window_width := CLIENT_WIDTH + (border_rect.right - border_rect.left)
	window_height := CLIENT_HEIGHT + (border_rect.bottom - border_rect.top)

	internal.hwnd = win.CreateWindowExW(
		window_ex_style,
		window_class.lpszClassName,
		win.L(CLIENT_NAME),
		window_style,
		window_x,
		window_y,
		window_width,
		window_height,
		nil,
		nil,
		internal.hinstance,
		nil,
	)

	if internal.hwnd == nil {
		log.error("failed to create win32 window.")
		return false
	}

	should_show := true // set to false for inputless window
	show_cmd := should_show ? win.SW_SHOW : win.SW_SHOWNOACTIVATE
	win.ShowWindow(internal.hwnd, show_cmd)

	internal.hdc = win.GetDC(internal.hwnd)

	platform._internal = rawptr(internal)

	g_offscreen_buffer = &internal.buffer
	g_platform_initialized = true

	return true
}

@(private = "package")
_platform_offscreen_buffer :: proc(platform: ^Platform) -> ^OffscreenBuffer {

	log.assert(
		platform._internal != nil && g_platform_initialized,
		"must initialize platform before calling platform_offscreen_buffer",
	)
	internal := cast(^ProcessInternal)(platform._internal)
	return &internal.buffer
}

@(private = "package")
_platform_message_dispatch :: proc() {

	log.assert(g_platform_initialized, "initialize platform before calling platform_messages_dispatch")

	message: win.MSG
	for win.PeekMessageW(&message, nil, 0, 0, win.PM_REMOVE) {
		if message.message == win.WM_QUIT {
			bc.core_get().running = false
		}

		win.TranslateMessage(&message)
		win.DispatchMessageW(&message)
	}
}

@(private = "package")
_platform_window_buffer_display :: proc(platform: ^Platform) {

	log.assert(
		platform._internal != nil && g_platform_initialized,
		"initialize platform before calling platform_window_buffer_display",
	)
	internal := cast(^ProcessInternal)(platform._internal)

	window_width, window_height := _window_dimensions(internal.hwnd)
	_window_buffer_display(internal.hdc, window_width, window_height, &internal.buffer)
}

@(private = "package")
_window_buffer_display :: proc(hdc: win.HDC, window_width, window_height: win.INT, buffer: ^OffscreenBuffer) {

	bitmap_width := win.INT(buffer.width)
	bitmap_height := win.INT(buffer.height)

	// TODO: aspect ratio correction
	
	// odinfmt: disable 
	win.StretchDIBits(
		hdc, 
		0, 0, window_width, window_height,
		0, 0, bitmap_width, bitmap_height,
		buffer.memory, &buffer.info, 
		win.DIB_RGB_COLORS,
		win.SRCCOPY,
	)
	// odinfmt: enable
}

@(private = "file")
_window_buffer_resize :: proc(buffer: ^OffscreenBuffer, width, height: win.INT) {

	if buffer.memory != nil {
		win.VirtualFree(buffer.memory, 0, win.MEM_RELEASE)
	}

	buffer.info = win.BITMAPINFO {
		bmiHeader = win.BITMAPINFOHEADER {
			biSize          = size_of(win.BITMAPINFOHEADER),
			biWidth         = win.LONG(width),
			biHeight        = win.LONG(-height), // top-down
			biPlanes        = 1,
			biBitCount      = 32,
			biCompression   = win.BI_RGB,
			biSizeImage     = 0,
			biXPelsPerMeter = 0,
			biYPelsPerMeter = 0,
			biClrUsed       = 0,
			biClrImportant  = 0,
		},
	}

	buffer.width = int(width)
	buffer.height = int(height)
	buffer.bytes_per_pixel = 4
	buffer.bytes_pitch = buffer.width * buffer.bytes_per_pixel

	bitmap_memory_size := buffer.width * buffer.height * buffer.bytes_per_pixel
	buffer.memory = win.VirtualAlloc(
		nil,
		win.SIZE_T(bitmap_memory_size),
		win.MEM_RESERVE | win.MEM_COMMIT,
		win.PAGE_READWRITE,
	)
}

@(private = "file")
_window_dimensions :: proc(hwnd: win.HWND) -> (width: win.INT, height: win.INT) {

	client_rect: win.RECT
	win.GetClientRect(hwnd, &client_rect)
	return win.INT(client_rect.right - client_rect.left), win.INT(client_rect.bottom - client_rect.top)
}


@(private = "file")
_window_message_proc :: proc "stdcall" (
	hwnd: win.HWND,
	message: win.UINT,
	wparam: win.WPARAM,
	lparam: win.LPARAM,
) -> (
	result: win.LRESULT,
) {

	context = bc.global_context()

	switch (message) {
	// case win.WM_SIZE:
	case win.WM_SYSKEYDOWN:
	case win.WM_KEYDOWN:
	case win.WM_SYSKEYUP:
	case win.WM_KEYUP:
		was_down := (lparam & (1 << 30)) != 0
		is_down := (lparam & (1 << 31)) == 0
		if was_down != is_down {
			vk_code := win.UINT(wparam)
			if vk_code == win.VK_ESCAPE {
				bc.core_get().running = false
			}
			if vk_code == win.VK_W {
				log.debug("W")
			}
			if vk_code == win.VK_A {
				log.debug("A")
			}
			if vk_code == win.VK_S {
				log.debug("S")
			}
			if vk_code == win.VK_D {
				log.debug("D")
			}
		}
	case win.WM_DESTROY:
		// TODO: handle this with message to user?
		bc.core_get().running = false
		log.debug("window destroy message")
	case win.WM_CLOSE:
		// TODO: handle this with window recreation?
		bc.core_get().running = false
		log.debug("window close message")
	case win.WM_DPICHANGED:
		log.debug("window dpi changed message")
	case win.WM_ACTIVATEAPP:
		log.debug("window activate message")
	case win.WM_PAINT:
		ps: win.PAINTSTRUCT
		hdc := win.BeginPaint(hwnd, &ps)
		window_width, window_height := _window_dimensions(hwnd)
		_window_buffer_display(hdc, window_width, window_height, g_offscreen_buffer)
		win.EndPaint(hwnd, &ps)
	case:
		result = win.DefWindowProcW(hwnd, message, wparam, lparam)
	}

	return result
}
