package renderer

import backend "./vulkan"
import bb "bedbug:core"
import "core:log"

BbRenderer :: struct {
	backend: backend.Vulkan,
	camera:  Camera,
}

setup :: proc(renderer: ^BbRenderer) -> (ok: bool) {

	log.info("Setting up renderer...")

	backend.setup(&renderer.backend) or_return

	renderer.camera = Camera {
		position        = bb.vec3{0.0, 0.0, -2.5},
		target          = bb.vec3{0.0, 0.0, 0.0},
		up              = bb.vec3{0.0, 1.0, 0.0},
		near            = 1.0,
		far             = 256.0,
		y_fov           = 60.0,
		projection_type = .PERSPECTIVE,
	}

	return true
}

frame_draw :: proc(renderer: ^BbRenderer, current_frame: u32) -> u32 {

	aspect := f32(renderer.backend.swapchain.extent.width) / f32(renderer.backend.swapchain.extent.height)

	projection := bb.mat4_perspective(
		bb.to_radians(renderer.camera.y_fov),
		aspect,
		renderer.camera.near,
		renderer.camera.far,
	)

	view := bb.mat4_look_at(renderer.camera.position, renderer.camera.target, renderer.camera.up)


	shader_data := ShaderData {
		projection = projection,
		view       = view,
		model      = bb.mat4(1.0),
	}

	return backend.frame_draw(&renderer.backend, &shader_data, current_frame)
}

ShaderData :: backend.ShaderData
