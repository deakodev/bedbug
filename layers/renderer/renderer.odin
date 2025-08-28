package renderer

import backend "./vulkan"
import bb "bedbug:core"
import im "bedbug:vendor/imgui"
import im_glfw "bedbug:vendor/imgui/imgui_impl_glfw"
import im_vk "bedbug:vendor/imgui/imgui_impl_vulkan"
import "core:log"

Renderer :: struct {
	backend: backend.Vulkan,
	camera:  Camera,
}

setup :: proc(renderer: ^Renderer) {

	log.info("Setting up renderer...")
	log.assert(renderer != nil, "renderer pointer is nil.")

	backend.setup(&renderer.backend)
	log.ensure(renderer.backend.initialized, "failed to initialize renderer backend.")

	renderer.camera = Camera {
		position        = bb.vec3{0.0, 0.0, -2.5},
		target          = bb.vec3{0.0, 0.0, 0.0},
		up              = bb.vec3{0.0, 1.0, 0.0},
		near            = 1.0,
		far             = 256.0,
		y_fov           = 60.0,
		projection_type = .PERSPECTIVE,
	}
}

cleanup :: proc(renderer: ^Renderer) -> (ok: bool) {

	log.info("cleaning up renderer...")
	log.assert(renderer != nil, "renderer pointer is nil.")
	backend.cleanup(&renderer.backend) or_return

	return true
}

frame_prepare :: proc(renderer: ^Renderer) {

	backend.update(&renderer.backend)
}

frame_begin :: proc() {

	im_glfw.new_frame()
	im_vk.new_frame()
	im.new_frame()
}

frame_end :: proc(renderer: ^Renderer) {

	im.render()
	backend.draw(&renderer.backend)
}
