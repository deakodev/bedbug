package editor

import bb "bedbug:bedbug"
import im "bedbug:vendor/imgui"
import "core:log"

@(export)
editor_setup :: proc(bedbug: rawptr, self: rawptr) {

	log.info("setting up editor...")
	imgui := ((^bb.Bedbug)(bedbug)).renderer.backend.imgui
	im.set_current_context(imgui)
}

@(export)
editor_cleanup :: proc(bedbug: rawptr, self: rawptr) {

	log.info("cleaning up editor...")
}

@(export)
editor_update :: proc(bedbug: rawptr, self: rawptr) {

	backend := &((^bb.Bedbug)(bedbug)).renderer.backend

	// log.info("editor")


	if im.begin("Background", nil, {.Always_Auto_Resize}) {
		effect_selected := &backend.background.effects[backend.background.selected]

		if im.begin_combo("Effect", effect_selected.name) {
			for effect, i in backend.background.effects {
				is_selected := i == backend.background.selected
				if im.selectable(effect.name, is_selected) {
					backend.background.selected = i
				}

				if is_selected {
					im.set_item_default_focus()
				}
			}
			im.end_combo()
		}

		im.input_float4("push_constants _1", &effect_selected.push_constants._1)
		im.input_float4("push_constants _2", &effect_selected.push_constants._2)
		im.input_float4("push_constants _3", &effect_selected.push_constants._3)
		im.input_float4("push_constants _4", &effect_selected.push_constants._4)
	}

	im.end()

	// im.show_demo_window()
}
