package bedbug_runtime

import core "bedbug:core"
import "bedbug:layers"
import renderer "bedbug:layers/renderer"

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:reflect"
import "core:strings"

Dynlib :: core.Dynlib
Module :: core.Module
Plugin :: core.Plugin
Options :: core.Options

@(private = "file")
g_bedbug_stage: BedbugStage = .UNINITIALIZED
BedbugStage :: enum u8 {
	UNINITIALIZED,
	INITIALIZED,
}

Bedbug :: struct {
	core:               core.Core,
	renderer:           renderer.Renderer,
	tracking_allocator: mem.Tracking_Allocator,
}

setup :: proc(bedbug: ^Bedbug, plugin: ^Plugin($T), options: ^Options) -> (ok: bool) {

	log.ensure(bedbug != nil, "bedbug pointer is nil.")
	log.ensure(plugin != nil, "bedbug plugin is nil.")

	if g_bedbug_stage != .UNINITIALIZED {
		log.warn("Bedbug is already initialized.");return
	}

	core_callback :: proc() -> ^core.Core {
		bedbug := cast(^Bedbug)context.user_ptr
		log.assert(bedbug != nil, "bedbug pointer is nil.")
		return &bedbug.core
	}

	core.setup(&bedbug.core, options, core_callback)

	// setup internal subsystem layers
	renderer.setup(&bedbug.renderer)

	// setup external plugin modules
	lib_names := reflect.enum_field_names(T)
	for &lib, index in plugin.libs {
		lib.name = strings.to_lower(lib_names[index])
		lib.versions = make([dynamic]core.DynlibSymbols)

		module := &plugin.modules[index]
		module.symbols = core.dynlib_load(&lib)
		module.self, module.type = module.setup(bedbug)
	}

	g_bedbug_stage = .INITIALIZED
	return true
}

cleanup :: proc(bedbug: ^Bedbug, plugin: ^Plugin($T)) -> (ok: bool) {

	log.ensure(bedbug != nil, "bedbug pointer is nil.")
	log.ensure(plugin != nil, "bedbug plugin is nil.")

	if g_bedbug_stage != .INITIALIZED {
		log.warn("Bedbug is not initialized.");return false
	}

	for &lib, index in plugin.libs {
		module := plugin.modules[index]
		module.cleanup(bedbug, module.self) or_return
		core.dynlib_unload(&lib) or_return
	}

	renderer.cleanup(&bedbug.renderer) or_return

	core.cleanup(&bedbug.core) or_return

	g_bedbug_stage = .UNINITIALIZED
	return true
}

update :: proc(bedbug: ^Bedbug) {

	core.timer_update(&bedbug.core.timer)
}

poll_events :: proc(bedbug: ^Bedbug) {

	core.window_poll_events()
}

should_run :: proc() -> bool {

	return !core.window_should_close()
}

run :: proc(bedbug: ^Bedbug, plugin: ^Plugin($T)) -> (ok: bool) {

	log.ensure(bedbug != nil, "bedbug pointer is nil.")
	log.ensure(plugin != nil, "bedbug plugin is nil.")

	if g_bedbug_stage != .INITIALIZED {
		log.warn("Bedbug is not initialized.");return false
	}

	loop: for should_run() {
		if !bedbug.core.window.iconified {
			renderer.frame_prepare(&bedbug.renderer)
		}

		update(bedbug)

		for &module in plugin.modules {
			module.update(bedbug, module.self)
		}

		if bedbug.core.window.iconified {
			core.window_wait_events()
			core.timer_setup(&bedbug.core.timer, bedbug.core.window.fps)
			continue loop
		}

		renderer.frame_begin()

		for &module in plugin.modules {
			module.draw(bedbug, module.self)
		}

		renderer.frame_end(&bedbug.renderer)

		if core.dynlib_should_reload(&plugin.libs[plugin.client]) {
			client_module := plugin.modules[plugin.client]
			client_module.symbols = core.dynlib_load(&plugin.libs[plugin.client])
		}

		client_should_reset := core.input_key_pressed(.KEY_F5)
		if client_should_reset {
			client_module := &plugin.modules[plugin.client]
			client_module.cleanup(bedbug, client_module.self)
			client_module.self, client_module.type = client_module.setup(bedbug)
		}

		poll_events(bedbug)

		free_all(context.temp_allocator)

		when ODIN_DEBUG {
			core.allocator_tracking_check(&bedbug.tracking_allocator)
		}
	}

	return true
}
