package renderer

import backend "./vulkan"
import bb "bedbug:core"
import im "bedbug:vendor/imgui"
import im_glfw "bedbug:vendor/imgui/imgui_impl_glfw"
import im_vk "bedbug:vendor/imgui/imgui_impl_vulkan"
import "core:log"

BbRenderer :: struct {
	backend: backend.Vulkan,
	camera:  Camera,
}

setup :: proc(self: ^BbRenderer) {

	log.info("Setting up renderer...")
	log.assert(self != nil, "renderer pointer is nil.")

	backend.setup(&self.backend)

	self.camera = Camera {
		position        = bb.vec3{0.0, 0.0, -2.5},
		target          = bb.vec3{0.0, 0.0, 0.0},
		up              = bb.vec3{0.0, 1.0, 0.0},
		near            = 1.0,
		far             = 256.0,
		y_fov           = 60.0,
		projection_type = .PERSPECTIVE,
	}
}

cleanup :: proc(self: ^BbRenderer) {

	log.info("cleaning up renderer...")
	log.assert(self != nil, "renderer pointer is nil.")
	backend.cleanup(&self.backend)
}

frame_prepare :: proc(self: ^BbRenderer) {

	backend.frame_prepare(&self.backend)
}

frame_begin :: proc() {

	im_glfw.new_frame()
	im_vk.new_frame()
	im.new_frame()
}

frame_end :: proc(self: ^BbRenderer) {

	im.render()
	backend.frame_draw(&self.backend)
}
