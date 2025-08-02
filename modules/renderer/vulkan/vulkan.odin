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

	// written via compute shader
	draw:             struct {
		image:      AllocatedImage,
		descriptor: Descriptor,
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
}

cleanup :: proc(self: ^Vulkan) {

	log.assert(self != nil, "renderer backend pointer is nil.")
	log.ensure(vk.DeviceWaitIdle(self.device.handle) == .SUCCESS)

	frame_cleanup(self)
	swapchain_cleanup(self)
	device_cleanup(self)
	instance_cleanup(self)
}

frame_prepare :: proc(backend: ^Vulkan) {

	frame := _get_next_frame(backend)
	resource_stack_flush(&frame.ephemeral_stack)
	descriptor_allocator_clear_pools(&frame.descriptor_allocator)

	vk_ok(vk.WaitForFences(backend.device.handle, 1, &frame.fence, true, max(u64)))
	vk_ok(vk.ResetFences(backend.device.handle, 1, &frame.fence))

	image_index: u32 = ---
	result := vk.AcquireNextImageKHR(
		backend.device.handle,
		backend.swapchain.handle,
		max(u64),
		frame.present_semaphore,
		0,
		&frame.image_index,
	)

	// todo: check result
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

	image_transition(frame.command_buffer, backend.draw.image.handle, .UNDEFINED, .GENERAL)

	frame_draw_background(backend, frame)

	image_transition(frame.command_buffer, backend.draw.image.handle, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL)

	frame_draw_geometry(backend, frame)

	image_transition(frame.command_buffer, backend.draw.image.handle, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
	image_transition(frame.command_buffer, swapchain_image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

	image_copy(
		frame.command_buffer,
		backend.draw.image.handle,
		swapchain_image,
		{backend.draw.image.extent.width, backend.draw.image.extent.height},
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

	// todo: check result

	_set_next_frame(backend)
}

frame_draw_background :: proc(self: ^Vulkan, frame: ^Frame) {

	effect := &self.background.effects[self.background.selected]
	vk.CmdBindPipeline(frame.command_buffer, .COMPUTE, effect.handle)

	vk.CmdBindDescriptorSets(frame.command_buffer, .COMPUTE, effect.layout, 0, 1, &self.draw.descriptor.set, 0, nil)

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
		u32(math.ceil(f32(self.draw.image.extent.width) / 16.0)),
		u32(math.ceil(f32(self.draw.image.extent.height) / 16.0)),
		1,
	)
}

frame_draw_geometry :: proc(self: ^Vulkan, frame: ^Frame) {

	color_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = self.draw.image.view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .LOAD,
		storeOp     = .STORE,
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {offset = {0, 0}, extent = {self.draw.image.extent.width, self.draw.image.extent.height}},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
	}

	vk.CmdBeginRendering(frame.command_buffer, &rendering_info)

	vk.CmdBindPipeline(frame.command_buffer, .GRAPHICS, self.pipelines[.TRIANGLE].handle)

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(self.draw.image.extent.width),
		height   = f32(self.draw.image.extent.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}

	vk.CmdSetViewport(frame.command_buffer, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = {self.draw.image.extent.width, self.draw.image.extent.height},
	}

	vk.CmdSetScissor(frame.command_buffer, 0, 1, &scissor)

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
		buffer = scene_uniform_buffer.handle,
		size = size_of(SceneUniformData),
		offset = 0,
		type = .UNIFORM_BUFFER,
	)
	descriptor_writer_update_set(&writer, global_descriptor)

	// Launch a draw command to draw 3 vertices
	vk.CmdDraw(frame.command_buffer, 3, 1, 0, 0)

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
