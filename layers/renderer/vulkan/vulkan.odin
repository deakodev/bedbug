package vulkan_backend

import "base:runtime"
import bb "bedbug:core"
import im "bedbug:vendor/imgui"
import "core:c/libc"
import "core:log"
import "core:mem"
import "vendor:glfw"
import vk "vendor:vulkan"

@(private = "package")
g_foreign_context: runtime.Context

Vulkan :: struct {
	instance:                   Instance,
	device:                     Device,
	swapchain:                  Swapchain,
	draw_target:                DrawTarget,
	frames:                     Frames,
	imgui:                      ^im.Context,
	scene:                      Scene,
	next_frame_index:           u32,
	textures:                   struct {
		white_image:              AllocatedImage,
		black_image:              AllocatedImage,
		grey_image:               AllocatedImage,
		error_checkerboard_image: AllocatedImage,
		default_sampler_linear:   vk.Sampler,
		default_sampler_nearest:  vk.Sampler,
	},
	pipelines:                  [PipelineType]Pipeline,
	initialized:                bool,
	vertex_descriptor_layout:   vk.DescriptorSetLayout,
	metal_rough:                MetalRough,
	material_descriptor_layout: vk.DescriptorSetLayout,
}

setup :: proc(backend: ^Vulkan) -> (ok: bool) {

	log.ensure(backend != nil, "failed with null backend.")
	if backend.initialized {log.warn("failed to steup, backend already initialized.");return}
	g_foreign_context = context

	instance_setup(backend) or_return
	device_setup(backend) or_return
	swapchain_setup(backend) or_return
	draw_target_setup(backend) or_return
	frame_setup(backend) or_return
	imgui_setup(backend) or_return
	scene_setup(backend) or_return

	backend.initialized = true
	return true
}

cleanup :: proc(backend: ^Vulkan) {

	log.ensure(backend != nil, "failed with null backend.")
	if !backend.initialized {log.warn("failed to cleanup, backend not initialized.");return}
	log.ensure(vk.DeviceWaitIdle(backend.device.handle) == .SUCCESS)

	for &mesh in backend.scene.test_meshes {
		allocated_buffer_cleanup(mesh.buffers.index_buffer)
		allocated_buffer_cleanup(mesh.buffers.vertex_buffer)
	}
	meshes_destroy(&backend.scene.test_meshes)

	frame_cleanup(backend)
	swapchain_cleanup(backend)
	device_cleanup(backend)
	instance_cleanup(backend)

	backend.initialized = false
}

update :: proc(backend: ^Vulkan) -> (ok: bool) {

	frame := get_next_frame(backend)

	vk_ok(vk.WaitForFences(backend.device.handle, 1, &frame.fence, true, max(u64))) or_return

	resource_stack_flush(&frame.ephemeral_stack)
	descriptor_allocator_clear_pools(&frame.descriptor_allocator)

	vk_ok(vk.ResetFences(backend.device.handle, 1, &frame.fence)) or_return

	draw_target_extent := vk.Extent3D {
		width  = u32(
			f32(min(backend.swapchain.extent.width, backend.draw_target.color_image.extent.width)) *
			backend.draw_target.scale,
		),
		height = u32(
			f32(min(backend.swapchain.extent.height, backend.draw_target.color_image.extent.height)) *
			backend.draw_target.scale,
		),
		depth  = 1,
	}
	backend.draw_target.color_image.extent = draw_target_extent
	backend.draw_target.depth_image.extent = draw_target_extent


	result := vk.AcquireNextImageKHR(
		backend.device.handle,
		backend.swapchain.handle,
		max(u64),
		frame.present_semaphore,
		0,
		&frame.image_index,
	)

	if result != .ERROR_OUT_OF_DATE_KHR && result != .SUBOPTIMAL_KHR { 	// handled after vk.QueuePresentKHR
		vk_ok(result) or_return
	}

	return true
}
