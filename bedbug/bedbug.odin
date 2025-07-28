package bedbug

import "bedbug:core"
import "bedbug:modules/renderer"

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:reflect"
import "core:strings"

TITLE :: "Bedbug"
WIDTH :: 1200
HEIGHT :: 800

Layer :: core.DynlibSymbols
Dynlib :: core.Dynlib
Plugin :: struct($T: typeid) {
	tag:  typeid,
	libs: [T]Dynlib,
}

Bedbug :: struct {
	core:     ^core.Core,
	renderer: ^renderer.BbRenderer,
	layers:   []^Layer,
}

setup :: proc(bedbug: ^Bedbug, plugin: ^Plugin($T)) {

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

	core.timer_setup(&bedbug.core.timer, 60)

	bedbug.renderer = new(renderer.BbRenderer)
	renderer.setup(bedbug.renderer)

	ensure(reflect.enum_value_has_name(T.GAME), "bedbug plugin enum T must have field value .GAME")
	lib_names := reflect.enum_field_names(plugin.tag)
	bedbug.layers = make([]^Layer, len(plugin.libs))

	for &lib, index in plugin.libs {
		lib.name = strings.to_lower(lib_names[index])
		lib.versions = make([dynamic]core.DynlibSymbols)
		layer := core.dynlib_load(&lib)

		layer.setup(bedbug, layer.self)
		bedbug.layers[index] = layer
	}
}

cleanup :: proc(bedbug: ^Bedbug, plugin: ^Plugin($T)) {

	log.info("cleaning up bedbug...")

	for &lib, index in plugin.libs {
		layer := bedbug.layers[index]
		layer.cleanup(bedbug, layer.self)
		core.dynlib_unload(&lib)
	}
	delete(bedbug.layers)

	renderer.cleanup(bedbug.renderer)
	free(bedbug.renderer)

	core.window_cleanup()
	free(bedbug.core)

	free(bedbug)
}

update :: proc(bedbug: ^Bedbug) {

	core.window_poll_events()

	core.timer_tick(&bedbug.core.timer)
}

should_run :: proc() -> bool {

	return !core.window_should_close()
}

run :: proc(bedbug: ^Bedbug, plugin: ^Plugin($T)) {

	current_frame: u32 = 0
	loop: for should_run() {

		update(bedbug)

		if bedbug.core.window.iconified {
			core.wait_events()
			continue loop
		}

		renderer.begin_frame()

		for &layer in bedbug.layers {
			layer.update(bedbug, layer.self)
		}

		renderer.end_frame()

		renderer.frame_draw(bedbug.renderer)

		should_reload_game := core.dynlib_should_reload(&plugin.libs[T.GAME])
		if should_reload_game {
			for &lib, index in plugin.libs {
				if lib.name == "game" {
					game_layer := bedbug.layers[index]
					new_layer := core.dynlib_load(&plugin.libs[T.GAME])

					if new_layer != nil {
						new_layer.self = game_layer.self
						bedbug.layers[index] = new_layer
					}
				}
			}
		}

		// todo: fix
		// should_reset_game := core.input_key_pressed(.KEY_F5)
		// if should_reset_game {
		// 	for &lib, index in plugin.libs {
		// 		if lib.name == "game" {
		// 			game_layer := bedbug.layers[index]
		// 			new_layer := core.dynlib_load(&plugin.libs[T.GAME])
		// 			game_layer.cleanup(bedbug, game_layer.self)
		// 			// core.allocator_clear()
		// 			new_layer.self = game_layer.self
		// 			new_layer.setup(bedbug, new_layer.self)
		// 			bedbug.layers[index] = new_layer
		// 		}
		// 	}
		// }

		free_all(context.temp_allocator)
		core.allocator_check()
	}
}

logger_setup :: core.logger_setup
allocator_setup :: core.allocator_setup
allocator_clear :: core.allocator_clear
allocator_check :: core.allocator_check
allocator_cleanup :: core.allocator_cleanup
