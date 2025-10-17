package editor

import bb "bedbug:runtime"
import im "bedbug:vendor/imgui"
import "core:log"
import "core:mem"

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
editor_cleanup :: proc(bedbug: rawptr, self: rawptr) -> (ok: bool) {

	log.info("cleaning up editor...")
	free(self)
	return true
}

@(export)
editor_update :: proc(bedbug: rawptr, self: rawptr) -> (ok: bool) {

	// log.info("updating editor...")
	return true
}

@(export)
editor_draw :: proc(bedbug: rawptr, self: rawptr) -> (ok: bool) {

	bedbug := (^bb.Bedbug)(bedbug)
	backend := &bedbug.renderer.backend

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

	if im.begin("Memory Usage", nil, {.Always_Auto_Resize}) {

		ta := &bedbug.tracking_allocator
		im.text("%s currently allocated", bb.bytes_formated_string(ta.current_memory_allocated))
		im.separator()
		im.text("%s peak allocated", bb.bytes_formated_string(ta.peak_memory_allocated))
		im.text(
			"%s total allocated | %d allocations",
			bb.bytes_formated_string(ta.total_memory_allocated),
			ta.total_allocation_count,
		)
		im.text("%s total freed | %d frees", bb.bytes_formated_string(ta.total_memory_freed), ta.total_free_count)

		im.separator()
	}

	im.end()

	// im.show_demo_window()

	return true
}
