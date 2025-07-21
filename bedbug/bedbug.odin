package bedbug

import "bedbug:core"
import "bedbug:modules/renderer"

import "base:runtime"
import "core:fmt"
import "core:log"

TITLE :: "Bedbug"
WIDTH :: 1200
HEIGHT :: 800

Bedbug :: struct {
	core:     ^core.Core,
	renderer: ^renderer.BbRenderer,
}

setup :: proc(bedbug: ^Bedbug) -> (ok: bool) {

	log.info("setting up bedbug...")
	log.assert(bedbug != nil, "bedbug pointer is nil.")

	bedbug.core = new(core.Core)
	core.set_callback(proc() -> ^core.Core {
		bedbug := cast(^Bedbug)context.user_ptr
		log.assert(bedbug != nil, "bedbug pointer is nil.")
		log.assert(bedbug.core != nil, "bedbug core pointer is nil.")
		return bedbug.core
	})
	bedbug.core.window = core.window_setup(TITLE, WIDTH, HEIGHT)

	bedbug.renderer = new(renderer.BbRenderer)
	renderer.setup(bedbug.renderer) or_return

	return true
}

cleanup :: proc() {

	log.info("cleaning up bedbug...")
	core.window_cleanup()
	core.allocator_cleanup()
}

update :: proc() {
	core.window_poll_events()
}

should_run :: proc() -> bool {
	return !core.window_should_close()
}

logger_setup :: core.logger_setup

allocator_setup :: core.allocator_setup
allocator_clear :: core.allocator_clear
allocator_check :: core.allocator_check
allocator_cleanup :: core.allocator_cleanup

Futon_Symbols :: core.Futon_Symbols
Game_Symbols :: core.Game_Symbols
dynlib_load :: core.dynlib_load
dynlib_unload :: core.dynlib_unload
dynlib_generation :: core.dynlib_generation
dynlib_should_reload :: core.dynlib_should_reload

//temp
frame_draw :: renderer.frame_draw
