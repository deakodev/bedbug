package vulkan_backend

import "base:runtime"
import bb "bedbug:core"
import im "bedbug:vendor/imgui"
import im_vk "bedbug:vendor/imgui/imgui_impl_vulkan"
import "core:c/libc"
import "core:log"
import "core:mem"
import "vendor:glfw"
import vk "vendor:vulkan"

//temp
import "core:math"

@(private = "package")
g_foreign_context: runtime.Context

Background :: struct {
	effects:  [ComputeEffect]ComputePipeline,
	selected: ComputeEffect,
}

SceneUniformData :: struct {
	view:               bb.mat4,
	proj:               bb.mat4,
	viewproj:           bb.mat4,
	ambient_color:      bb.vec4,
	sunlight_direction: bb.vec4, // w for sun power
	sunlight_color:     bb.vec4,
}

Scene :: struct {
	data:              SceneUniformData,
	descriptor_layout: vk.DescriptorSetLayout,
	rectangle:         MeshBuffers,
	test_meshes:       Meshes,
}

RenderTarget :: struct {
	color_image: AllocatedImage, // written via compute shader
	depth_image: AllocatedImage,
	descriptor:  Descriptor,
	extent:      vk.Extent3D,
	scale:       f32,
}

Vulkan :: struct {
	instance:         Instance,
	device:           Device,
	swapchain:        Swapchain,
	pipelines:        [GraphicsEffect]GraphicsPipeline,
	background:       Background,
	scene:            Scene,
	imgui:            ^im.Context,
	frames:           []Frame,
	next_frame_index: u32,
	render_target:    RenderTarget,
	textures:         struct {
		white_image:              AllocatedImage,
		black_image:              AllocatedImage,
		grey_image:               AllocatedImage,
		error_checkerboard_image: AllocatedImage,
		default_sampler_linear:   vk.Sampler,
		default_sampler_nearest:  vk.Sampler,
	},
}

MAX_CONCURRENT_FRAMES :: 2

setup :: proc(self: ^Vulkan) {

	g_foreign_context = context
	log.assert(self != nil, "renderer backend pointer is nil.")

	instance_setup(self)
	device_setup(self)
	swapchain_setup(self)
	descriptor_setup(self)
	pipeline_setup(self)
	frame_setup(self)
	imgui_setup(self)

	scene_setup(self)
}

cleanup :: proc(self: ^Vulkan) {

	log.assert(self != nil, "renderer backend pointer is nil.")
	log.ensure(vk.DeviceWaitIdle(self.device.handle) == .SUCCESS)

	for &mesh in self.scene.test_meshes {
		allocated_buffer_cleanup(mesh.buffers.index_buffer)
		allocated_buffer_cleanup(mesh.buffers.vertex_buffer)
	}
	meshes_destroy(&self.scene.test_meshes)

	frame_cleanup(self)
	swapchain_cleanup(self)
	device_cleanup(self)
	instance_cleanup(self)
}

frame_prepare :: proc(backend: ^Vulkan) {

	frame := _get_next_frame(backend)
	resource_stack_flush(&frame.ephemeral_stack)

	vk_ok(vk.WaitForFences(backend.device.handle, 1, &frame.fence, true, max(u64)))
	vk_ok(vk.ResetFences(backend.device.handle, 1, &frame.fence))

	descriptor_allocator_clear_pools(&frame.descriptor_allocator)

	backend.render_target.extent = {
		width  = u32(
			f32(min(backend.swapchain.extent.width, backend.render_target.color_image.extent.width)) *
			backend.render_target.scale,
		),
		height = u32(
			f32(min(backend.swapchain.extent.height, backend.render_target.color_image.extent.height)) *
			backend.render_target.scale,
		),
	}

	result := vk.AcquireNextImageKHR(
		backend.device.handle,
		backend.swapchain.handle,
		max(u64),
		frame.present_semaphore,
		0,
		&frame.image_index,
	)

	if result != .ERROR_OUT_OF_DATE_KHR && result != .SUBOPTIMAL_KHR { 	// handled after vk.QueuePresentKHR
		vk_ok(result)
	}
}

frame_draw :: proc(backend: ^Vulkan) {

	frame := _get_next_frame(backend)
	swapchain_image := backend.swapchain.images[frame.image_index]

	vk_ok(vk.ResetCommandBuffer(frame.command_buffer, {}))

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	vk_ok(vk.BeginCommandBuffer(frame.command_buffer, &begin_info))

	image_transition(frame.command_buffer, backend.render_target.color_image.handle, .UNDEFINED, .GENERAL)

	frame_draw_background(backend, frame)

	image_transition(
		frame.command_buffer,
		backend.render_target.color_image.handle,
		.GENERAL,
		.COLOR_ATTACHMENT_OPTIMAL,
	)

	image_transition(
		frame.command_buffer,
		backend.render_target.depth_image.handle,
		.UNDEFINED,
		.DEPTH_ATTACHMENT_OPTIMAL,
	)

	frame_draw_geometry(backend, frame)

	image_transition(
		frame.command_buffer,
		backend.render_target.color_image.handle,
		.COLOR_ATTACHMENT_OPTIMAL,
		.TRANSFER_SRC_OPTIMAL,
	)
	image_transition(frame.command_buffer, swapchain_image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

	image_copy(
		frame.command_buffer,
		backend.render_target.color_image.handle,
		swapchain_image,
		{backend.render_target.extent.width, backend.render_target.extent.height},
		backend.swapchain.extent,
	)

	image_transition(frame.command_buffer, swapchain_image, .TRANSFER_DST_OPTIMAL, .COLOR_ATTACHMENT_OPTIMAL)

	frame_draw_imgui(backend, frame)

	image_transition(frame.command_buffer, swapchain_image, .COLOR_ATTACHMENT_OPTIMAL, .PRESENT_SRC_KHR)

	vk_ok(vk.EndCommandBuffer(frame.command_buffer))

	command_buffer_info := vk.CommandBufferSubmitInfo {
		sType         = .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer = frame.command_buffer,
	}

	signal_info := vk.SemaphoreSubmitInfo {
		sType     = .SEMAPHORE_SUBMIT_INFO,
		semaphore = frame.submit_semaphore,
		stageMask = {.ALL_GRAPHICS},
		value     = 1,
	}

	wait_info := vk.SemaphoreSubmitInfo {
		sType     = .SEMAPHORE_SUBMIT_INFO,
		semaphore = frame.present_semaphore,
		stageMask = {.COLOR_ATTACHMENT_OUTPUT_KHR},
		value     = 1,
	}

	submit_info := vk.SubmitInfo2 {
		sType                    = .SUBMIT_INFO_2,
		waitSemaphoreInfoCount   = 1,
		pWaitSemaphoreInfos      = &wait_info,
		signalSemaphoreInfoCount = 1,
		pSignalSemaphoreInfos    = &signal_info,
		commandBufferInfoCount   = 1,
		pCommandBufferInfos      = &command_buffer_info,
	}

	vk_ok(vk.QueueSubmit2(backend.device.graphics_queue, 1, &submit_info, frame.fence))

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &frame.submit_semaphore,
		swapchainCount     = 1,
		pSwapchains        = &backend.swapchain.handle,
		pImageIndices      = &frame.image_index,
	}

	result := vk.QueuePresentKHR(backend.device.graphics_queue, &present_info)

	if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR {
		swapchain_resize(backend)
	} else {
		vk_ok(result)
	}

	_set_next_frame(backend)
}

frame_draw_background :: proc(self: ^Vulkan, frame: ^Frame) {

	effect := &self.background.effects[self.background.selected]
	vk.CmdBindPipeline(frame.command_buffer, .COMPUTE, effect.handle)

	vk.CmdBindDescriptorSets(
		frame.command_buffer,
		.COMPUTE,
		effect.layout,
		0,
		1,
		&self.render_target.descriptor.set,
		0,
		nil,
	)

	vk.CmdPushConstants(
		frame.command_buffer,
		effect.layout,
		{.COMPUTE},
		0,
		size_of(ComputePushConstants),
		&effect.push_constants,
	)

	vk.CmdDispatch(
		frame.command_buffer,
		u32(math.ceil(f32(self.render_target.extent.width) / 16.0)),
		u32(math.ceil(f32(self.render_target.extent.height) / 16.0)),
		1,
	)
}

frame_draw_geometry :: proc(self: ^Vulkan, frame: ^Frame) {

	image_width := self.render_target.extent.width
	image_height := self.render_target.extent.height

	color_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = self.render_target.color_image.view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .LOAD,
		storeOp     = .STORE,
	}

	depth_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = self.render_target.depth_image.view,
		imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
	}
	depth_attachment.clearValue.depthStencil.depth = 0.0

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {offset = {0, 0}, extent = {image_width, image_height}},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
		pDepthAttachment = &depth_attachment,
	}
	log.debug(rendering_info.renderArea)
	vk.CmdBeginRendering(frame.command_buffer, &rendering_info)

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(image_width),
		height   = f32(image_height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}

	vk.CmdSetViewport(frame.command_buffer, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = {image_width, image_height},
	}

	vk.CmdSetScissor(frame.command_buffer, 0, 1, &scissor)

	vk.CmdBindPipeline(frame.command_buffer, .GRAPHICS, self.pipelines[.MESH].handle)

	view := bb.mat4_translate(bb.vec3{0, 0, -2})

	projection := bb.mat4_perspective_reverse_z(
		f32(bb.to_radians(f32(70.0))),
		f32(image_width) / f32(image_height),
		0.1,
		true,
	)

	push_constants := DrawPushConstants {
		world_matrix = projection * view,
	}

	vk.CmdPushConstants(
		frame.command_buffer,
		self.pipelines[.MESH].layout,
		{.VERTEX},
		0,
		size_of(DrawPushConstants),
		&push_constants,
	)

	scene_uniform_buffer := allocated_buffer_create(self, size_of(SceneUniformData), {.UNIFORM_BUFFER}, .Cpu_To_Gpu)

	resource_stack_push(&frame.ephemeral_stack, scene_uniform_buffer)

	scene_uniform_data := cast(^SceneUniformData)scene_uniform_buffer.alloc_info.mapped_data
	scene_uniform_data^ = self.scene.data

	global_descriptor := descriptor_allocator_new_set(&frame.descriptor_allocator, &self.scene.descriptor_layout)

	writer: DescriptorWriter
	descriptor_writer_setup(&writer, self.device.handle)
	descriptor_writer_write_buffer(
		&writer,
		binding = 0,
		buffer = self.scene.test_meshes[2].buffers.vertex_buffer.handle,
		size = self.scene.test_meshes[2].buffers.vertex_buffer.alloc_info.size,
		offset = 0,
		type = .STORAGE_BUFFER,
	)
	descriptor_writer_update_set(&writer, global_descriptor)

	vk.CmdBindDescriptorSets(
		frame.command_buffer,
		.GRAPHICS,
		self.pipelines[.MESH].layout,
		0,
		1,
		&global_descriptor,
		0,
		nil,
	)

	vk.CmdBindIndexBuffer(frame.command_buffer, self.scene.test_meshes[2].buffers.index_buffer.handle, 0, .UINT32)

	vk.CmdDrawIndexed(
		frame.command_buffer,
		self.scene.test_meshes[2].surfaces[0].count,
		1,
		self.scene.test_meshes[2].surfaces[0].start_index,
		0,
		0,
	)

	vk.CmdEndRendering(frame.command_buffer)
}

frame_draw_imgui :: proc(self: ^Vulkan, frame: ^Frame) {

	color_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = self.swapchain.views[frame.image_index],
		imageLayout = .GENERAL,
		loadOp      = .LOAD,
		storeOp     = .STORE,
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {offset = {0, 0}, extent = {self.swapchain.extent.width, self.swapchain.extent.height}},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
	}

	vk.CmdBeginRendering(frame.command_buffer, &rendering_info)

	im_vk.render_draw_data(im.get_draw_data(), frame.command_buffer)

	vk.CmdEndRendering(frame.command_buffer)

}

@(private = "file")
_get_next_frame :: #force_inline proc(backend: ^Vulkan) -> (frame: ^Frame) #no_bounds_check {
	return &backend.frames[backend.next_frame_index % MAX_CONCURRENT_FRAMES]
}

@(private = "file")
_set_next_frame :: #force_inline proc(backend: ^Vulkan) {
	backend.next_frame_index = (backend.next_frame_index + 1) % MAX_CONCURRENT_FRAMES
}

scene_setup :: proc(self: ^Vulkan) {

	self.scene.test_meshes, _ = meshes_create_from_gtlf(self, "modules/renderer/assets/basicmesh.glb")

	rect_vertices := [4]MeshVertex {
		{position = {0.5, -0.5, 0}, color = {0, 0, 0.0, 1.0}},
		{position = {0.5, 0.5, 0}, color = {0.5, 0.5, 0.5, 1.0}},
		{position = {-0.5, -0.5, 0}, color = {1, 0, 0.0, 1.0}},
		{position = {-0.5, 0.5, 0}, color = {0.0, 1.0, 0.0, 1.0}},
	}

	rect_indices := [6]u32{0, 1, 2, 2, 1, 3}

	self.scene.rectangle = mesh_buffers_create(self, rect_indices[:], rect_vertices[:])

	white := bb.pack_unorm_4x8({1, 1, 1, 1})
	self.textures.white_image = allocated_image_create_from_data(self, &white, {1, 1, 1}, .R8G8B8A8_UNORM, {.SAMPLED})

	grey := bb.pack_unorm_4x8({0.66, 0.66, 0.66, 1})
	self.textures.grey_image = allocated_image_create_from_data(self, &grey, {1, 1, 1}, .R8G8B8A8_UNORM, {.SAMPLED})

	black := bb.pack_unorm_4x8({0, 0, 0, 0})
	self.textures.black_image = allocated_image_create_from_data(self, &black, {1, 1, 1}, .R8G8B8A8_UNORM, {.SAMPLED})

	// Checkerboard image
	magenta := bb.pack_unorm_4x8({1, 0, 1, 1})
	pixels: [16 * 16]u32
	for x in 0 ..< 16 {
		for y in 0 ..< 16 {
			pixels[y * 16 + x] = ((x % 2) ~ (y % 2)) != 0 ? magenta : black
		}
	}
	self.textures.error_checkerboard_image = allocated_image_create_from_data(
		self,
		raw_data(pixels[:]),
		{16, 16, 1},
		.R8G8B8A8_UNORM,
		{.SAMPLED},
	)

	sampler_info := vk.SamplerCreateInfo {
		sType     = .SAMPLER_CREATE_INFO,
		magFilter = .NEAREST,
		minFilter = .NEAREST,
	}

	vk_ok(vk.CreateSampler(self.device.handle, &sampler_info, nil, &self.textures.default_sampler_nearest))

	sampler_info.magFilter = .LINEAR
	sampler_info.minFilter = .LINEAR

	vk_ok(vk.CreateSampler(self.device.handle, &sampler_info, nil, &self.textures.default_sampler_linear))

	resource_stack_push(
		&self.device.cleanup_stack,
		self.scene.rectangle.index_buffer,
		self.scene.rectangle.vertex_buffer,
		self.textures.white_image,
		self.textures.grey_image,
		self.textures.black_image,
		self.textures.error_checkerboard_image,
		self.textures.default_sampler_nearest,
		self.textures.default_sampler_linear,
	)
}
