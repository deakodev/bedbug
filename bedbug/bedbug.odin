package bedbug

import "bedbug:core"
import "bedbug:modules/renderer"

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:reflect"
import "core:strings"

Dynlib :: core.Dynlib
Layer :: core.Layer
Plugin :: core.Plugin

Options :: struct {
	window_title:  Maybe(cstring),
	window_width:  Maybe(u32),
	window_height: Maybe(u32),
	target_fps:    Maybe(u32),
	fullscreen:    bool,
}

g_default_options := Options {
	window_title  = "Bedbug",
	window_width  = 1200,
	window_height = 800,
	target_fps    = 60,
}

Bedbug :: struct {
	core:     ^core.Core,
	renderer: ^renderer.Renderer,
}

setup :: proc(bedbug: ^Bedbug, plugin: ^Plugin($T), options: ^Options) {

	log.info("setting up bedbug...")
	log.ensure(bedbug != nil, "bedbug pointer is nil.")
	log.ensure(plugin != nil, "bedbug plugin is nil.")

	bedbug.core = new(core.Core)
	core.set_callback(proc() -> ^core.Core {
		bedbug := cast(^Bedbug)context.user_ptr
		log.assert(bedbug != nil, "bedbug pointer is nil.")
		log.assert(bedbug.core != nil, "bedbug core pointer is nil.")
		return bedbug.core
	})

	options := options if options != nil else &g_default_options
	title := options.window_title.? or_else g_default_options.window_title.?
	width := options.window_width.? or_else g_default_options.window_width.?
	height := options.window_height.? or_else g_default_options.window_height.?
	fps := options.target_fps.? or_else g_default_options.target_fps.?
	fullscreen := options.fullscreen

	bedbug.core.window = core.window_setup(title, width, height, fps, fullscreen)

	core.timer_setup(&bedbug.core.timer, fps)

	bedbug.renderer = new(renderer.Renderer)
	renderer.setup(bedbug.renderer)

	log.ensure(reflect.enum_value_has_name(T.GAME), "bedbug plugin enum T must have field '.GAME' (layer).")
	lib_names := reflect.enum_field_names(T)

	for &lib, index in plugin.libs {
		lib.name = strings.to_lower(lib_names[index])
		lib.versions = make([dynamic]core.DynlibSymbols)

		layer := &plugin.layers[index]
		layer.symbols = core.dynlib_load(&lib)
		layer.self, layer.type = layer.setup(bedbug)
	}
}

cleanup :: proc(bedbug: ^Bedbug, plugin: ^Plugin($T)) {

	log.info("cleaning up bedbug...")
	log.assert(bedbug != nil, "bedbug pointer is nil.")
	log.assert(plugin != nil, "bedbug plugin is nil.")

	for &lib, index in plugin.libs {
		layer := plugin.layers[index]
		layer.cleanup(bedbug, layer.self)
		core.dynlib_unload(&lib)
	}

	renderer.cleanup(bedbug.renderer)
	free(bedbug.renderer)

	core.window_cleanup()
	free(bedbug.core)

	free(bedbug)

}

update :: proc(bedbug: ^Bedbug) {

	core.timer_tick(&bedbug.core.timer)
}

poll_events :: proc(bedbug: ^Bedbug) {

	core.window_poll_events()
}

should_run :: proc() -> bool {

	return !core.window_should_close()
}

run :: proc(bedbug: ^Bedbug, plugin: ^Plugin($T)) {

	log.info("running bedbug...")
	log.assert(bedbug != nil, "bedbug pointer is nil.")
	log.assert(plugin != nil, "bedbug plugin is nil.")

	loop: for should_run() {

		if !bedbug.core.window.iconified {
			renderer.frame_prepare(bedbug.renderer)
		}

		update(bedbug)

		for &layer in plugin.layers {
			layer.update(bedbug, layer.self)
		}

		if bedbug.core.window.iconified {
			core.window_wait_events()
			core.timer_setup(&bedbug.core.timer, bedbug.core.window.fps) // todo: event callback to limit triggering?
			continue loop
		}

		renderer.frame_begin()

		for &layer in plugin.layers {
			layer.draw(bedbug, layer.self)
		}

		renderer.frame_end(bedbug.renderer)

		if core.dynlib_should_reload(&plugin.libs[T.GAME]) {
			game_layer := plugin.layers[T.GAME]
			game_layer.symbols = core.dynlib_load(&plugin.libs[T.GAME])
		}

		game_should_reset := core.input_key_pressed(.KEY_F5)
		if game_should_reset {
			game_layer := &plugin.layers[T.GAME]
			game_layer.cleanup(bedbug, game_layer.self)
			game_layer.self, game_layer.type = game_layer.setup(bedbug)
		}

		poll_events(bedbug)

		free_all(context.temp_allocator)
		core.allocator_check()
	}
}

logger_setup :: core.logger_setup
allocator_setup :: core.allocator_setup
allocator_clear :: core.allocator_clear
allocator_check :: core.allocator_check
allocator_cleanup :: core.allocator_cleanup
