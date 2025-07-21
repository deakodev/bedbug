package vulkan_backend

import "base:runtime"
import bb "bedbug:core"
import "core:c/libc"
import "core:log"
import "core:mem"
import "vendor:glfw"
import vk "vendor:vulkan"

@(private = "package")
g_foreign_context: runtime.Context

Vulkan :: struct {
	instance:  VulkanInstance,
	device:    VulkanDevice,
	swapchain: VulkanSwapchain,
	frames:    [MAX_CONCURRENT_FRAMES]VulkanFrame,
	pipelines: [PipelineType]GraphicsPipeline,
}

MAX_CONCURRENT_FRAMES :: 2

Vertex :: struct {
	position: bb.vec3,
	color:    bb.vec3,
}

g_vertex_buffer: DeviceBuffer
g_index_buffer: DeviceBuffer

setup :: proc(backend: ^Vulkan) -> (ok: bool) {

	g_foreign_context = context

	vulkan_instance_setup(&backend.instance) or_return
	backend.device = vulkan_device_setup(backend.instance)
	backend.swapchain = vulkan_swapchain_setup(backend.instance.surface, backend.device)
	backend.frames = vulkan_frame_setup(backend.device)
	backend.pipelines = vulkan_pipeline_setup(backend.instance, backend.device, backend.swapchain)

	vertex_buffer_setup(backend.device)

	return true
}

vertex_buffer_setup :: proc(device: VulkanDevice) {

	vertices := [3]Vertex {
		{{1.0, 1.0, 0.0}, {1.0, 0.0, 0.0}},
		{{-1.0, 1.0, 0.0}, {0.0, 1.0, 0.0}},
		{{0.0, -1.0, 0.0}, {0.0, 0.0, 1.0}},
	}

	indices := [3]u32{0, 1, 2}

	staging_buffer: DeviceBuffer
	staging_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size  = size_of(vertices) + size_of(indices),
		usage = {.TRANSFER_SRC},
	}

	vk_ok(vk.CreateBuffer(device.handle, &staging_info, nil, &staging_buffer.handle))

	memory_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device.handle, staging_buffer.handle, &memory_requirements)

	memory_type_index := device_memory_type_index(
		device.physical,
		memory_requirements.memoryTypeBits,
		{.HOST_VISIBLE, .HOST_COHERENT},
	)

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = memory_requirements.size,
		memoryTypeIndex = memory_type_index,
	}

	vk_ok(vk.AllocateMemory(device.handle, &alloc_info, nil, &staging_buffer.memory))
	vk_ok(vk.BindBufferMemory(device.handle, staging_buffer.handle, staging_buffer.memory, 0))

	buffer_data: rawptr
	vk_ok(vk.MapMemory(device.handle, staging_buffer.memory, 0, alloc_info.allocationSize, {}, &buffer_data))
	libc.memcpy(buffer_data, &vertices, size_of(vertices))
	libc.memcpy(mem.ptr_offset(transmute(^u8)buffer_data, size_of(vertices)), &indices, size_of(indices))

	vertex_buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size  = size_of(vertices),
		usage = {.VERTEX_BUFFER, .TRANSFER_DST},
	}

	vk_ok(vk.CreateBuffer(device.handle, &vertex_buffer_info, nil, &g_vertex_buffer.handle))
	vk.GetBufferMemoryRequirements(device.handle, g_vertex_buffer.handle, &memory_requirements)
	memory_type_index = device_memory_type_index(device.physical, memory_requirements.memoryTypeBits, {.DEVICE_LOCAL})
	alloc_info.allocationSize = memory_requirements.size
	alloc_info.memoryTypeIndex = memory_type_index
	vk_ok(vk.AllocateMemory(device.handle, &alloc_info, nil, &g_vertex_buffer.memory))
	vk_ok(vk.BindBufferMemory(device.handle, g_vertex_buffer.handle, g_vertex_buffer.memory, 0))

	index_buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size  = size_of(indices),
		usage = {.INDEX_BUFFER, .TRANSFER_DST},
	}

	vk_ok(vk.CreateBuffer(device.handle, &index_buffer_info, nil, &g_index_buffer.handle))
	vk.GetBufferMemoryRequirements(device.handle, g_index_buffer.handle, &memory_requirements)
	memory_type_index = device_memory_type_index(device.physical, memory_requirements.memoryTypeBits, {.DEVICE_LOCAL})
	alloc_info.allocationSize = memory_requirements.size
	alloc_info.memoryTypeIndex = memory_type_index
	vk_ok(vk.AllocateMemory(device.handle, &alloc_info, nil, &g_index_buffer.memory))
	vk_ok(vk.BindBufferMemory(device.handle, g_index_buffer.handle, g_index_buffer.memory, 0))

	copy_command: vk.CommandBuffer
	command_alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = device.command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}

	vk_ok(vk.AllocateCommandBuffers(device.handle, &command_alloc_info, &copy_command))

	command_begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}

	vk_ok(vk.BeginCommandBuffer(copy_command, &command_begin_info))

	copy_region: vk.BufferCopy
	copy_region.size = size_of(vertices)
	vk.CmdCopyBuffer(copy_command, staging_buffer.handle, g_vertex_buffer.handle, 1, &copy_region)
	copy_region.srcOffset = copy_region.size
	copy_region.size = size_of(indices)
	vk.CmdCopyBuffer(copy_command, staging_buffer.handle, g_index_buffer.handle, 1, &copy_region)

	vk_ok(vk.EndCommandBuffer(copy_command))

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &copy_command,
	}

	fence: vk.Fence
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
	}
	vk_ok(vk.CreateFence(device.handle, &fence_info, nil, &fence))

	vk_ok(vk.QueueSubmit(device.queue.graphics, 1, &submit_info, fence))

	vk_ok(vk.WaitForFences(device.handle, 1, &fence, true, max(u64)))
	vk.DestroyFence(device.handle, fence, nil)
	vk.FreeCommandBuffers(device.handle, device.command_pool, 1, &copy_command)
	vk.DestroyBuffer(device.handle, staging_buffer.handle, nil)
	vk.FreeMemory(device.handle, staging_buffer.memory, nil)
}

frame_draw :: proc(backend: ^Vulkan, shader_data: ^ShaderData, current_frame: u32) -> u32 {

	frame := &backend.frames[current_frame]
	vk_ok(vk.WaitForFences(backend.device.handle, 1, &frame.wait_fence, true, max(u64)))
	vk_ok(vk.ResetFences(backend.device.handle, 1, &frame.wait_fence))

	image_index: u32
	result := vk.AcquireNextImageKHR(
		backend.device.handle,
		backend.swapchain.handle,
		max(u64),
		frame.present_complete_semaphore,
		0,
		&image_index,
	)

	libc.memcpy(frame.uniform_buffer.mapped, shader_data, size_of(ShaderData))

	vk_ok(vk.ResetCommandBuffer(frame.command_buffer, {}))

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	vk_ok(vk.BeginCommandBuffer(frame.command_buffer, &begin_info))

	color_image_barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		image = backend.swapchain.images[image_index],
		srcAccessMask = {},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
		oldLayout = .UNDEFINED,
		newLayout = .ATTACHMENT_OPTIMAL,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	vk.CmdPipelineBarrier(
		frame.command_buffer,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_OUTPUT},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&color_image_barrier,
	)

	depth_image_barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		image = backend.swapchain.target.depth.image,
		srcAccessMask = {},
		dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
		oldLayout = .UNDEFINED,
		newLayout = .ATTACHMENT_OPTIMAL,
		subresourceRange = {
			aspectMask = {.DEPTH, .STENCIL},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	vk.CmdPipelineBarrier(
		frame.command_buffer,
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&depth_image_barrier,
	)

	color_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = backend.swapchain.views[image_index],
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
	}
	color_attachment.clearValue.color.float32 = {0.0, 0.0, 0.0, 1.0}

	depth_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = backend.swapchain.target.depth.view,
		imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .DONT_CARE,
	}
	depth_attachment.clearValue.depthStencil = {1.0, 0.0}

	render_info := vk.RenderingInfo {
		sType                = .RENDERING_INFO,
		renderArea           = vk.Rect2D{vk.Offset2D{0, 0}, backend.swapchain.extent},
		layerCount           = 1,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_attachment,
		pDepthAttachment     = &depth_attachment,
		pStencilAttachment   = &depth_attachment,
	}

	vk.CmdBeginRendering(frame.command_buffer, &render_info)

	viewport := vk.Viewport {
		x        = 0.0,
		y        = 0.0,
		width    = f32(backend.swapchain.extent.width),
		height   = f32(backend.swapchain.extent.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}
	vk.CmdSetViewport(frame.command_buffer, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = backend.swapchain.extent,
	}
	vk.CmdSetScissor(frame.command_buffer, 0, 1, &scissor)

	vk.CmdBindDescriptorSets(
		frame.command_buffer,
		.GRAPHICS,
		g_pipeline_layout,
		0,
		1,
		&frame.uniform_buffer.descriptor_set,
		0,
		nil,
	)

	vk.CmdBindPipeline(frame.command_buffer, .GRAPHICS, backend.pipelines[.TRIANGLE].handle)

	offset := vk.DeviceSize(0)
	vk.CmdBindVertexBuffers(frame.command_buffer, 0, 1, &g_vertex_buffer.handle, &offset)

	vk.CmdBindIndexBuffer(frame.command_buffer, g_index_buffer.handle, 0, .UINT32)

	// vk.CmdDrawIndexed(frame.command_buffer, 3, 1, 0, 0, 0)
	vk.CmdDraw(frame.command_buffer, 3, 1, 0, 0)


	vk.CmdEndRendering(frame.command_buffer)

	color_image_barrier.srcAccessMask = {.COLOR_ATTACHMENT_WRITE}
	color_image_barrier.dstAccessMask = {}
	color_image_barrier.oldLayout = .ATTACHMENT_OPTIMAL
	color_image_barrier.newLayout = .PRESENT_SRC_KHR

	vk.CmdPipelineBarrier(
		frame.command_buffer,
		{.COLOR_ATTACHMENT_OUTPUT},
		{},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&color_image_barrier,
	)

	vk_ok(vk.EndCommandBuffer(frame.command_buffer))

	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &frame.present_complete_semaphore,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &frame.submit_complete_semaphore,
		pWaitDstStageMask    = &vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
		commandBufferCount   = 1,
		pCommandBuffers      = &frame.command_buffer,
	}

	vk_ok(vk.QueueSubmit(backend.device.queue.graphics, 1, &submit_info, frame.wait_fence))

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &frame.submit_complete_semaphore,
		swapchainCount     = 1,
		pSwapchains        = &backend.swapchain.handle,
		pImageIndices      = &image_index,
	}

	result = vk.QueuePresentKHR(backend.device.queue.graphics, &present_info)
	// todo: handle result

	return (current_frame + 1) % MAX_CONCURRENT_FRAMES
}
