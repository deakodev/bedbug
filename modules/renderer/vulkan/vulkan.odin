package vulkan_backend

import "base:runtime"
import bb "bedbug:core"
import "core:c/libc"
import "core:log"
import "core:mem"
import "vendor:glfw"
import vk "vendor:vulkan"

//temp
import "core:math"

@(private = "package")
g_foreign_context: runtime.Context

Vulkan :: struct {
	instance:         Instance,
	device:           Device,
	swapchain:        Swapchain,
	descriptor_pool:  vk.DescriptorPool,
	pipelines:        [PipelineType]Pipeline,
	frames:           []Frame,
	next_frame_index: u32,
}

MAX_CONCURRENT_FRAMES :: 2

Vertex :: struct {
	position: bb.vec3,
	color:    bb.vec3,
}

g_vertex_buffer: DeviceBuffer
g_index_buffer: DeviceBuffer

setup :: proc(self: ^Vulkan) -> (ok: bool) {

	g_foreign_context = context

	vulkan_instance_setup(self)
	vulkan_device_setup(self)
	vulkan_swapchain_setup(self)
	vulkan_descriptor_setup(self)
	vulkan_frame_setup(self)

	background_pipelines_setup(self)
	// backend.pipelines = vulkan_pipeline_setup(backend.instance, backend.device, backend.swapchain)

	// vertex_buffer_setup(backend.device)

	return true
}

cleanup :: proc(self: ^Vulkan) {

	ensure(vk.DeviceWaitIdle(self.device.handle) == .SUCCESS)
	vulkan_frame_cleanup(self)
	vulkan_swapchain_cleanup(self)
	vulkan_device_cleanup(self)
	vulkan_instance_cleanup(self)
}

vertex_buffer_setup :: proc(device: Device) {

	// vertices := [3]Vertex {
	// 	{{1.0, 1.0, 0.0}, {1.0, 0.0, 0.0}},
	// 	{{-1.0, 1.0, 0.0}, {0.0, 1.0, 0.0}},
	// 	{{0.0, -1.0, 0.0}, {0.0, 0.0, 1.0}},
	// }

	// indices := [3]u32{0, 1, 2}

	// staging_buffer: DeviceBuffer
	// staging_info := vk.BufferCreateInfo {
	// 	sType = .BUFFER_CREATE_INFO,
	// 	size  = size_of(vertices) + size_of(indices),
	// 	usage = {.TRANSFER_SRC},
	// }

	// vk_ok(vk.CreateBuffer(device.handle, &staging_info, nil, &staging_buffer.handle))

	// memory_requirements: vk.MemoryRequirements
	// vk.GetBufferMemoryRequirements(device.handle, staging_buffer.handle, &memory_requirements)

	// memory_type_index := device_memory_type_index(
	// 	device.physical,
	// 	memory_requirements.memoryTypeBits,
	// 	{.HOST_VISIBLE, .HOST_COHERENT},
	// )

	// alloc_info := vk.MemoryAllocateInfo {
	// 	sType           = .MEMORY_ALLOCATE_INFO,
	// 	allocationSize  = memory_requirements.size,
	// 	memoryTypeIndex = memory_type_index,
	// }

	// vk_ok(vk.AllocateMemory(device.handle, &alloc_info, nil, &staging_buffer.memory))
	// vk_ok(vk.BindBufferMemory(device.handle, staging_buffer.handle, staging_buffer.memory, 0))

	// buffer_data: rawptr
	// vk_ok(vk.MapMemory(device.handle, staging_buffer.memory, 0, alloc_info.allocationSize, {}, &buffer_data))
	// libc.memcpy(buffer_data, &vertices, size_of(vertices))
	// libc.memcpy(mem.ptr_offset(transmute(^u8)buffer_data, size_of(vertices)), &indices, size_of(indices))

	// vertex_buffer_info := vk.BufferCreateInfo {
	// 	sType = .BUFFER_CREATE_INFO,
	// 	size  = size_of(vertices),
	// 	usage = {.VERTEX_BUFFER, .TRANSFER_DST},
	// }

	// vk_ok(vk.CreateBuffer(device.handle, &vertex_buffer_info, nil, &g_vertex_buffer.handle))
	// vk.GetBufferMemoryRequirements(device.handle, g_vertex_buffer.handle, &memory_requirements)
	// memory_type_index = device_memory_type_index(device.physical, memory_requirements.memoryTypeBits, {.DEVICE_LOCAL})
	// alloc_info.allocationSize = memory_requirements.size
	// alloc_info.memoryTypeIndex = memory_type_index
	// vk_ok(vk.AllocateMemory(device.handle, &alloc_info, nil, &g_vertex_buffer.memory))
	// vk_ok(vk.BindBufferMemory(device.handle, g_vertex_buffer.handle, g_vertex_buffer.memory, 0))

	// index_buffer_info := vk.BufferCreateInfo {
	// 	sType = .BUFFER_CREATE_INFO,
	// 	size  = size_of(indices),
	// 	usage = {.INDEX_BUFFER, .TRANSFER_DST},
	// }

	// vk_ok(vk.CreateBuffer(device.handle, &index_buffer_info, nil, &g_index_buffer.handle))
	// vk.GetBufferMemoryRequirements(device.handle, g_index_buffer.handle, &memory_requirements)
	// memory_type_index = device_memory_type_index(device.physical, memory_requirements.memoryTypeBits, {.DEVICE_LOCAL})
	// alloc_info.allocationSize = memory_requirements.size
	// alloc_info.memoryTypeIndex = memory_type_index
	// vk_ok(vk.AllocateMemory(device.handle, &alloc_info, nil, &g_index_buffer.memory))
	// vk_ok(vk.BindBufferMemory(device.handle, g_index_buffer.handle, g_index_buffer.memory, 0))

	// copy_command: vk.CommandBuffer
	// command_alloc_info := vk.CommandBufferAllocateInfo {
	// 	sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
	// 	commandPool        = frame.command_pool,
	// 	level              = .PRIMARY,
	// 	commandBufferCount = 1,
	// }

	// vk_ok(vk.AllocateCommandBuffers(device.handle, &command_alloc_info, &copy_command))

	// command_begin_info := vk.CommandBufferBeginInfo {
	// 	sType = .COMMAND_BUFFER_BEGIN_INFO,
	// }

	// vk_ok(vk.BeginCommandBuffer(copy_command, &command_begin_info))

	// copy_region: vk.BufferCopy
	// copy_region.size = size_of(vertices)
	// vk.CmdCopyBuffer(copy_command, staging_buffer.handle, g_vertex_buffer.handle, 1, &copy_region)
	// copy_region.srcOffset = copy_region.size
	// copy_region.size = size_of(indices)
	// vk.CmdCopyBuffer(copy_command, staging_buffer.handle, g_index_buffer.handle, 1, &copy_region)

	// vk_ok(vk.EndCommandBuffer(copy_command))

	// submit_info := vk.SubmitInfo {
	// 	sType              = .SUBMIT_INFO,
	// 	commandBufferCount = 1,
	// 	pCommandBuffers    = &copy_command,
	// }

	// fence: vk.Fence
	// fence_info := vk.FenceCreateInfo {
	// 	sType = .FENCE_CREATE_INFO,
	// }
	// vk_ok(vk.CreateFence(device.handle, &fence_info, nil, &fence))

	// vk_ok(vk.QueueSubmit(device.graphics_queue, 1, &submit_info, fence))

	// vk_ok(vk.WaitForFences(device.handle, 1, &fence, true, max(u64)))
	// vk.DestroyFence(device.handle, fence, nil)
	// vk.FreeCommandBuffers(device.handle, frame.command_pool, 1, &copy_command)
	// vk.DestroyBuffer(device.handle, staging_buffer.handle, nil)
	// vk.FreeMemory(device.handle, staging_buffer.memory, nil)
}

frame_draw :: proc(backend: ^Vulkan, shader_data: ^ShaderData) {

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

	frame_draw_background(frame.command_buffer, &frame.draw_image, &backend.pipelines[.BACKGROUND])

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

frame_draw_background :: proc(command: vk.CommandBuffer, image: ^AllocatedImage, pipeline: ^Pipeline) {

	vk.CmdBindPipeline(command, .COMPUTE, pipeline.handle)

	// Bind the descriptor set containing the draw image for the compute pipeline
	vk.CmdBindDescriptorSets(command, .COMPUTE, pipeline.layout, 0, 1, &image.descriptor.set, 0, nil)

	// Execute the compute pipeline dispatch. We are using 16x16 workgroup size so
	// we need to divide by it
	vk.CmdDispatch(
		command,
		u32(math.ceil_f32(f32(image.extent.width) / 16.0)),
		u32(math.ceil_f32(f32(image.extent.height) / 16.0)),
		1,
	)
}

@(private = "file")
_get_next_frame :: #force_inline proc(backend: ^Vulkan) -> (frame: ^Frame) #no_bounds_check {
	return &backend.frames[backend.next_frame_index % MAX_CONCURRENT_FRAMES]
}

@(private = "file")
_set_next_frame :: #force_inline proc(backend: ^Vulkan) {
	backend.next_frame_index = (backend.next_frame_index + 1) % MAX_CONCURRENT_FRAMES
}
