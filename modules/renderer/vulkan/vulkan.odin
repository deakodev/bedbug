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

Vulkan :: struct {
	instance:         Instance,
	device:           Device,
	swapchain:        Swapchain,
	descriptor_pool:  vk.DescriptorPool,
	// pipelines:        [PipelineType]Pipeline,
	background:       Background,
	frames:           []Frame,
	next_frame_index: u32,
}

MAX_CONCURRENT_FRAMES :: 2

setup :: proc(self: ^Vulkan) -> (ok: bool) {

	g_foreign_context = context

	vulkan_instance_setup(self)
	vulkan_device_setup(self)
	vulkan_swapchain_setup(self)
	vulkan_descriptor_setup(self)
	vulkan_frame_setup(self)

	background_pipelines_setup(self)

	vulkan_imgui_setup(self)


	return true
}

cleanup :: proc(self: ^Vulkan) {

	ensure(vk.DeviceWaitIdle(self.device.handle) == .SUCCESS)
	vulkan_frame_cleanup(self)
	vulkan_swapchain_cleanup(self)
	vulkan_device_cleanup(self)
	vulkan_instance_cleanup(self)
}

frame_draw :: proc(backend: ^Vulkan) {

	frame := _get_next_frame(backend)
	vk_ok(vk.WaitForFences(backend.device.handle, 1, &frame.fence, true, max(u64)))
	vk_ok(vk.ResetFences(backend.device.handle, 1, &frame.fence))

	image_index: u32 = ---
	result := vk.AcquireNextImageKHR(
		backend.device.handle,
		backend.swapchain.handle,
		max(u64),
		frame.present_semaphore,
		0,
		&image_index,
	)

	vk_ok(vk.ResetCommandBuffer(frame.command_buffer, {}))

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	vk_ok(vk.BeginCommandBuffer(frame.command_buffer, &begin_info))

	image_transition(frame.command_buffer, frame.draw_image.handle, .UNDEFINED, .GENERAL)

	frame_draw_background(backend, frame)

	image_transition(frame.command_buffer, frame.draw_image.handle, .GENERAL, .TRANSFER_SRC_OPTIMAL)
	image_transition(frame.command_buffer, backend.swapchain.images[image_index], .UNDEFINED, .TRANSFER_DST_OPTIMAL)

	image_copy(
		frame.command_buffer,
		frame.draw_image.handle,
		backend.swapchain.images[image_index],
		{frame.draw_image.extent.width, frame.draw_image.extent.height},
		backend.swapchain.extent,
	)

	image_transition(
		frame.command_buffer,
		backend.swapchain.images[image_index],
		.TRANSFER_DST_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
	)

	frame_draw_imgui(backend, frame, image_index)

	image_transition(
		frame.command_buffer,
		backend.swapchain.images[image_index],
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
	)

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
		pImageIndices      = &image_index,
	}

	result = vk.QueuePresentKHR(backend.device.graphics_queue, &present_info)

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
		&frame.draw_image.descriptor.set,
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
		u32(math.ceil_f32(f32(frame.draw_image.extent.width) / 16.0)),
		u32(math.ceil_f32(f32(frame.draw_image.extent.height) / 16.0)),
		1,
	)
}

frame_draw_imgui :: proc(self: ^Vulkan, frame: ^Frame, image_index: u32) {

	color_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = self.swapchain.views[image_index],
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
