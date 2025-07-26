package futon

import bb "bedbug:bedbug"
import im "bedbug:vendor/imgui"
import im_glfw "bedbug:vendor/imgui/imgui_impl_glfw"
import im_vk "bedbug:vendor/imgui/imgui_impl_vulkan"

import "base:runtime"
import "core:fmt"
import "core:log"


@(export)
futon_setup :: proc(imgui: rawptr) {

	log.info("setting up futon")
	im.set_current_context((^im.Context)(imgui))
}


@(export)
futon_cleanup :: proc() {

	log.info("cleaning up futon")

}

@(export)
futon_update :: proc(bedbug: rawptr) {

	backend := &((^bb.Bedbug)(bedbug)).renderer.backend

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

	im.render()
}
