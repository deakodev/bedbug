package editor

import bb "bedbug:runtime"
import im "bedbug:vendor/imgui"
import "core:log"

Editor :: struct {}

@(export)
editor_setup :: proc(bedbug: rawptr) -> (self: rawptr, type: typeid) {

	log.info("setting up editor...")
	imgui := ((^bb.Bedbug)(bedbug)).renderer.backend.imgui
	im.set_current_context(imgui)

	self = new(Editor)

	return self, type_of(self)
}

@(export)
editor_cleanup :: proc(bedbug: rawptr, self: rawptr) {

	log.info("cleaning up editor...")
	free(self)
}

@(export)
editor_update :: proc(bedbug: rawptr, self: rawptr) {

	// log.info("updating editor...")
}

@(export)
editor_draw :: proc(bedbug: rawptr, self: rawptr) {

	backend := &((^bb.Bedbug)(bedbug)).renderer.backend

	if im.begin("Background", nil, {.Always_Auto_Resize}) {
		im.slider_float("Render scale", &backend.draw_target.scale, 0.3, 1.0)

		background_state := &backend.draw_target.pipeline.push_constants
		// if im.begin_combo("Effect", effect_selected.name) {
		// 	for effect, i in backend.background.effects {
		// 		is_selected := i == backend.background.selected
		// 		if im.selectable(effect.name, is_selected) {
		// 			backend.background.selected = i
		// 		}

		// 		if is_selected {
		// 			im.set_item_default_focus()
		// 		}
		// 	}
		// 	im.end_combo()
		// }

		im.input_float4("push_constants _1", &background_state._1)
		im.input_float4("push_constants _2", &background_state._2)
		im.input_float4("push_constants _3", &background_state._3)
		im.input_float4("push_constants _4", &background_state._4)
	}

	im.end()

	// im.show_demo_window()
}
