package sandbox

import "base:intrinsics"
import bc "bedbug:core"
import bpl "bedbug:layers/platform"
import bp "bedbug:plugins"
import "core:log"
import "core:mem"

// TODO: temp
import win "core:sys/windows"

core: bc.Core

main :: proc()
{
	context.logger = bc.logger_setup()
	log.info("Sandbox started")

	core_callback :: proc() -> ^bc.Core
	{
		return &core
	}

	bc.setup(&core, nil, core_callback)

	dcm_parser, ok := bc.plugin_interface(bp.DcmParser, bp.dcm_parser_config())
	if !ok
	{
		log.error("failed to get dcm_parser plugin interface")
		return
	}

	dcm := dcm_parser.handle_create("plugins/dcm_parser/dcms/sm_image.dcm")

	dcm_parser.parse(dcm)

	dcm_parser.parse_frame(dcm, 0)

	// platform: bpl.Platform
	// bpl.platform_setup(&platform)

	// begin_cycle_count := intrinsics.read_cycle_counter() // rdtsc

	// count_frequency: win.LARGE_INTEGER
	// win.QueryPerformanceFrequency(&count_frequency)

	// begin_count: win.LARGE_INTEGER
	// win.QueryPerformanceCounter(&begin_count)

	// core.running = true
	// x_offset := 0

	// for core.running {
	// 	bpl.platform_message_dispatch()

	// 	// for controller_index in 0 ..< win.XUSER_MAX_COUNT {
	// 	// 	controller_state: win.XINPUT_STATE
	// 	// 	if win.XInputGetState(controller_index, &controller_state) == win.ERROR_SUCCESS {
	// 	// 		gamepad := &controller_state.Gamepad


	// 	// 	} else {
	// 	// 		log.debugf("controller %d is not connected", user_index)
	// 	// 		// TODO: handle
	// 	// 	}
	// 	// }

	// 	platform_offscreen_buffer := bpl.platform_offscreen_buffer(&platform)
	// 	offscreen_buffer := OffscreenBuffer {
	// 		memory          = platform_offscreen_buffer.memory,
	// 		width           = platform_offscreen_buffer.width,
	// 		height          = platform_offscreen_buffer.height,
	// 		bytes_pitch     = platform_offscreen_buffer.bytes_pitch,
	// 		bytes_per_pixel = platform_offscreen_buffer.bytes_per_pixel,
	// 	}
	// 	render_weird_gradient(&offscreen_buffer, x_offset, 0)

	// 	bpl.platform_window_buffer_display(&platform)

	// 	x_offset += 1

	// 	end_cycle_count := intrinsics.read_cycle_counter() // rdtsc

	// 	end_count: win.LARGE_INTEGER
	// 	win.QueryPerformanceCounter(&end_count)

	// 	elapsed_cycles := end_cycle_count - begin_cycle_count
	// 	megacycles_per_frame := f32(elapsed_cycles) / 1_000_000

	// 	elapsed_count := end_count - begin_count
	// 	frames_per_second := count_frequency / elapsed_count
	// 	milliseconds_per_frame := f32(elapsed_count * 1000) / f32(count_frequency)

	// 	// log.infof("%.2f mc/f, %d f/s (%.2f ms/f)", megacycles_per_frame, frames_per_second, milliseconds_per_frame)

	// 	begin_cycle_count = end_cycle_count
	// 	begin_count = end_count
	// }

	log.info("Sandbox ended")
}

// TODO: below is temp

OffscreenBuffer :: struct
{
	memory:          rawptr,
	width, height:   int,
	bytes_pitch:     int,
	bytes_per_pixel: int,
}

render_weird_gradient :: proc(buffer: ^OffscreenBuffer, x_offset, y_offset: int)
{

	row := cast(^u8)buffer.memory
	for y: int = 0; y < int(buffer.height); y += 1
	{
		pixels := cast([^]u32)row

		for x: int = 0; x < int(buffer.width); x += 1
		{
			blue := u32(u8(x + x_offset))
			green := u32(u8(y + y_offset))
			pixels[x] = (green << 8) | blue // little-endian BGRA (no alpha set here)
		}

		row = cast(^u8)mem.ptr_offset(row, buffer.bytes_pitch)
	}
}
