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

Bedbug :: struct {
	core:     ^core.Core,
	renderer: ^renderer.BbRenderer,
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

	layer_names := reflect.enum_field_names(plugin.tag)
	for &layer, index in plugin.layers {
		name := strings.to_lower(layer_names[index])
		layer_symbols := core.layer_load(name, &layer)
		layer_symbols.setup(bedbug, layer_symbols.self)
	}
}

cleanup :: proc(bedbug: ^Bedbug, plugin: ^Plugin($T)) {

	log.info("cleaning up bedbug...")

	for &layer, index in plugin.layers {
		layer_symbols := core.layer_get_version(&layer)
		layer_symbols.cleanup(bedbug, layer_symbols.self)
		core.layer_unload(&layer)
		delete(layer.versions)
		delete(layer.name)
	}

	renderer.cleanup(bedbug.renderer)
	free(bedbug.renderer)

	core.window_cleanup()
	free(bedbug.core)
}

update :: proc(bedbug: ^Bedbug) {

	core.window_poll_events()

	core.timer_tick(&bedbug.core.timer)
}

should_run :: proc() -> bool {

	return !core.window_should_close()
}

run :: proc(bedbug: ^Bedbug, plugin: ^Plugin($T)) {

	current_layer_symbols := make([dynamic]^core.LayerSymbols)
	defer delete(current_layer_symbols)
	for &layer, index in plugin.layers {
		append(&current_layer_symbols, core.layer_get_version(&layer))
	}

	current_frame: u32 = 0
	loop: for should_run() {

		update(bedbug)

		if bedbug.core.window.iconified {
			core.wait_events()
			continue loop
		}

		renderer.begin_frame()

		for &layer_symbols in current_layer_symbols {
			layer_symbols.update(bedbug, layer_symbols.self)
		}

		renderer.end_frame()

		renderer.frame_draw(bedbug.renderer)

		// todo: imple in core
		// force_reload := game.force_reload()
		// force_restart := game.force_restart()
		force_reload := false
		force_restart := false

		// for plugin in plugins {
		// 	if plugin.should_reload()
		// }

		// if core.dynlib_should_reload(game_lib) || force_reload || force_restart {
		// 	game_lib = core.dynlib_load(core.Game_Symbols)
		// 	game_reload := core.dynlib_generation(game_lib)

		// 	force_restart = force_restart || game.memory_size() != game_reload.memory_size()

		// 	if !force_restart {
		// 		game_memory := game.memory()
		// 		game = game_reload
		// 		game.hot_reloaded(game_memory)

		// 	} else {

		// 		game.cleanup()

		// 		core.allocator_clear()

		// 		// dynlib_unload(&game_lib)
		// 		clear(&game_lib.generations)

		// 		game = game_reload
		// 		game.setup()
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

Layer :: core.Layer
Plugin :: struct($T: typeid) {
	tag:    typeid,
	layers: [T]Layer,
}
