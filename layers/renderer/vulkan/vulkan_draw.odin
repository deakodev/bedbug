package vulkan_backend

import bb "bedbug:core"
import im "bedbug:vendor/imgui"
import im_vk "bedbug:vendor/imgui/imgui_impl_vulkan"
import sa "core:container/small_array"
import "core:log"
import vk "vendor:vulkan"

ComputePushConstants :: struct {
	_1: bb.vec4,
	_2: bb.vec4,
	_3: bb.vec4,
	_4: bb.vec4,
}

ComputePipeline :: struct {
	handle:         vk.Pipeline,
	layout:         vk.PipelineLayout,
	push_constants: ComputePushConstants,
	name:           cstring,
}

DrawTarget :: struct {
	color_image: AllocatedImage,
	depth_image: AllocatedImage,
	descriptor:  Descriptor,
	pipeline:    ComputePipeline,
	scale:       f32,
}

draw_target_setup :: proc(backend: ^Vulkan) -> (ok: bool) {

	width, height := bb.monitor_resolution()
	draw_extent := vk.Extent3D {
		width  = width,
		height = height,
		depth  = 1,
	}

	color_image := allocated_image_create(
		backend,
		draw_extent,
		vk.Format.R16G16B16A16_SFLOAT,
		vk.ImageUsageFlags{.TRANSFER_SRC, .TRANSFER_DST, .STORAGE, .COLOR_ATTACHMENT},
	)

	depth_image := allocated_image_create(
		backend,
		draw_extent,
		vk.Format.D32_SFLOAT,
		vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT},
	)

	descriptor: Descriptor
	{
		pool_ratios: DescriptorPoolSizeRatios
		sa.append(
			&pool_ratios,
			DescriptorPoolSizeRatio{.STORAGE_IMAGE, 1},
			DescriptorPoolSizeRatio{.UNIFORM_BUFFER, 1},
			DescriptorPoolSizeRatio{.COMBINED_IMAGE_SAMPLER, 1},
		)

		pool_sizes: [MAX_DESCRIPTOR_POOL_SIZES]vk.DescriptorPoolSize
		for index in 0 ..< sa.len(pool_ratios) {
			ratio := sa.get_ptr(&pool_ratios, index)
			pool_sizes[index] = vk.DescriptorPoolSize {
				type            = ratio.type,
				descriptorCount = u32(ratio.value) * 10,
			}
		}

		pool_info := vk.DescriptorPoolCreateInfo {
			sType         = .DESCRIPTOR_POOL_CREATE_INFO,
			maxSets       = 10,
			poolSizeCount = u32(sa.len(pool_ratios)),
			pPoolSizes    = &pool_sizes[0],
		}

		vk_ok(vk.CreateDescriptorPool(backend.device.handle, &pool_info, nil, &descriptor.pool)) or_return

		descriptor_bindings: DescriptorBindings
		sa.append(
			&descriptor_bindings,
			vk.DescriptorSetLayoutBinding{binding = 0, descriptorCount = 1, descriptorType = .STORAGE_IMAGE},
		)
		descriptor.layout = descriptor_set_new_layout(backend.device.handle, &descriptor_bindings, {.COMPUTE})

		alloc_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool     = descriptor.pool,
			descriptorSetCount = 1,
			pSetLayouts        = &descriptor.layout,
		}

		vk_ok(vk.AllocateDescriptorSets(backend.device.handle, &alloc_info, &descriptor.set)) or_return

		writer: DescriptorWriter
		descriptor_writer_setup(&writer, backend.device.handle)

		descriptor_writer_write_image(
			&writer,
			binding = 0,
			image = color_image.view,
			sampler = 0,
			layout = .GENERAL,
			type = .STORAGE_IMAGE,
		)

		descriptor_writer_update_set(&writer, descriptor.set)
	}

	pipeline: ComputePipeline
	{
		push_constant := vk.PushConstantRange {
			offset     = 0,
			size       = size_of(ComputePushConstants),
			stageFlags = {.COMPUTE},
		}

		layout_info := vk.PipelineLayoutCreateInfo {
			sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
			setLayoutCount         = 1,
			pSetLayouts            = &descriptor.layout,
			pushConstantRangeCount = 1,
			pPushConstantRanges    = &push_constant,
		}

		pipeline_layout: vk.PipelineLayout
		vk_ok(vk.CreatePipelineLayout(backend.device.handle, &layout_info, nil, &pipeline_layout)) or_return

		stage_info := vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.COMPUTE},
			pName = "main",
		}

		compute_info := vk.ComputePipelineCreateInfo {
			sType  = .COMPUTE_PIPELINE_CREATE_INFO,
			layout = pipeline_layout,
			stage  = stage_info,
		}

		BACKGROUND_SPV :: #load("../shaders/bin/background.comp.spv")
		gradient_shader := shader_module_make(backend.device.handle, BACKGROUND_SPV)
		defer vk.DestroyShaderModule(backend.device.handle, gradient_shader, nil)

		compute_info.stage.module = gradient_shader

		pipeline = ComputePipeline {
			layout = pipeline_layout,
			push_constants = {
				// data1: skyTop + horizonSoftness
				_1 = {0.14, 0.16, 0.20, 0.01}, // a = softness (~0.02–0.08)
				// data2: skyHorizon + horizonHeight
				_2 = {0.08, 0.09, 0.12, 0.48}, // a = horizon height (0 bottom..1 top)
				// data3: ground + vignetteStrength
				_3 = {0.10, 0.10, 0.10, 0.25}, // a = vignette strength (0..1)
				_4 = {}, // unused
			},
			name = "Background",
		}

		vk_ok(vk.CreateComputePipelines(backend.device.handle, 0, 1, &compute_info, nil, &pipeline.handle)) or_return
	}

	backend.draw_target = DrawTarget {
		color_image = color_image,
		depth_image = depth_image,
		descriptor  = descriptor,
		pipeline    = pipeline,
		scale       = 1.0,
	}

	resource_stack_push(
		&backend.device.cleanup_stack,
		color_image,
		depth_image,
		descriptor.layout,
		descriptor.pool,
		pipeline.handle,
		pipeline.layout,
	)

	return true
}

draw :: proc(backend: ^Vulkan) -> (ok: bool) {

	frame := get_next_frame(backend)
	swapchain_image := backend.swapchain.images[frame.image_index]

	draw_target := &backend.draw_target
	color_image := draw_target.color_image
	depth_image := draw_target.depth_image

	vk_ok(vk.ResetCommandBuffer(frame.command_buffer, {})) or_return

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	vk_ok(vk.BeginCommandBuffer(frame.command_buffer, &begin_info)) or_return

	image_transition(frame.command_buffer, color_image.handle, .UNDEFINED, .GENERAL)

	draw_background(backend, frame)

	image_transition(frame.command_buffer, color_image.handle, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL)
	image_transition(frame.command_buffer, depth_image.handle, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)

	draw_geometry(backend, frame)

	image_transition(frame.command_buffer, color_image.handle, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
	image_transition(frame.command_buffer, swapchain_image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

	image_copy(
		frame.command_buffer,
		color_image.handle,
		swapchain_image,
		{color_image.extent.width, color_image.extent.height},
		backend.swapchain.extent,
	)

	image_transition(frame.command_buffer, swapchain_image, .TRANSFER_DST_OPTIMAL, .COLOR_ATTACHMENT_OPTIMAL)

	draw_imgui(backend, frame)

	image_transition(frame.command_buffer, swapchain_image, .COLOR_ATTACHMENT_OPTIMAL, .PRESENT_SRC_KHR)

	vk_ok(vk.EndCommandBuffer(frame.command_buffer)) or_return

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

	vk_ok(vk.QueueSubmit2(backend.device.graphics_queue.handle, 1, &submit_info, frame.fence)) or_return

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &frame.submit_semaphore,
		swapchainCount     = 1,
		pSwapchains        = &backend.swapchain.handle,
		pImageIndices      = &frame.image_index,
	}

	result := vk.QueuePresentKHR(backend.device.graphics_queue.handle, &present_info)

	if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR {
		swapchain_resize(backend)
	} else {
		vk_ok(result) or_return
	}

	set_next_frame(backend)

	return true
}

draw_background :: proc(backend: ^Vulkan, frame: ^Frame) {

	draw_target := &backend.draw_target
	draw_pipeline := draw_target.pipeline

	vk.CmdBindPipeline(frame.command_buffer, .COMPUTE, draw_pipeline.handle)

	vk.CmdBindDescriptorSets(
		frame.command_buffer,
		.COMPUTE,
		draw_pipeline.layout,
		0,
		1,
		&draw_target.descriptor.set,
		0,
		nil,
	)

	vk.CmdPushConstants(
		frame.command_buffer,
		draw_pipeline.layout,
		{.COMPUTE},
		0,
		size_of(ComputePushConstants),
		&draw_pipeline.push_constants,
	)

	vk.CmdDispatch(
		frame.command_buffer,
		u32(bb.ceil(f32(draw_target.color_image.extent.width) / 16.0)),
		u32(bb.ceil(f32(draw_target.color_image.extent.height) / 16.0)),
		1,
	)
}

draw_geometry :: proc(backend: ^Vulkan, frame: ^Frame) {

	image_width := backend.draw_target.color_image.extent.width
	image_height := backend.draw_target.color_image.extent.height

	color_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = backend.draw_target.color_image.view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .LOAD,
		storeOp     = .STORE,
	}

	depth_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = backend.draw_target.depth_image.view,
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

	vk.CmdBindPipeline(frame.command_buffer, .GRAPHICS, backend.metal_rough.opaque_pipeline.handle)

	aspect := image_width / image_height
	backend.scene.data.view = bb.mat4_translate(bb.vec3{0, 0, -2})

	backend.scene.data.proj = bb.mat4_perspective_reverse_z(
		f32(bb.to_radians(f32(70.0))),
		f32(image_width) / f32(image_height),
		0.1,
		true,
	)

	backend.scene.data.viewproj = bb.mat_mul(backend.scene.data.proj, backend.scene.data.view)

	backend.scene.data.ambient_color = {0.1, 0.1, 0.1, 1.0}
	backend.scene.data.sunlight_color = {1.0, 1.0, 1.0, 1.0}
	backend.scene.data.sunlight_direction = {0, 1, 0.5, 1.0}

	scene_uniform_buffer := allocated_buffer_create(backend, size_of(SceneUniformData), {.UNIFORM_BUFFER}, .Cpu_To_Gpu)

	resource_stack_push(&frame.ephemeral_stack, scene_uniform_buffer)

	scene_uniform_data := cast(^SceneUniformData)scene_uniform_buffer.alloc_info.mapped_data
	scene_uniform_data^ = backend.scene.data


	vertex_descriptor_set := descriptor_allocator_new_set(
		&frame.descriptor_allocator,
		&backend.vertex_descriptor_layout,
	)

	{
		writer: DescriptorWriter
		descriptor_writer_setup(&writer, backend.device.handle)
		descriptor_writer_write_buffer(
			&writer,
			binding = 0,
			buffer = backend.scene.test_meshes[2].buffers.vertex_buffer.handle,
			size = backend.scene.test_meshes[2].buffers.vertex_buffer.alloc_info.size,
			offset = 0,
			type = .STORAGE_BUFFER,
		)
		descriptor_writer_update_set(&writer, vertex_descriptor_set)
	}

	scene_descriptor_set := descriptor_allocator_new_set(&frame.descriptor_allocator, &backend.scene.descriptor_layout)

	{
		writer: DescriptorWriter
		descriptor_writer_setup(&writer, backend.device.handle)
		descriptor_writer_write_buffer(
			&writer,
			binding = 0,
			buffer = scene_uniform_buffer.handle,
			size = size_of(SceneUniformData),
			offset = 0,
			type = .UNIFORM_BUFFER,
		)
		descriptor_writer_update_set(&writer, scene_descriptor_set)
	}

	descriptor_sets := []vk.DescriptorSet {
		vertex_descriptor_set,
		scene_descriptor_set,
		backend.metal_rough.descriptor_set,
	}

	vk.CmdBindDescriptorSets(
		frame.command_buffer,
		.GRAPHICS,
		backend.metal_rough.opaque_pipeline.layout,
		0,
		u32(len(descriptor_sets)),
		raw_data(descriptor_sets),
		0,
		nil,
	)

	vk.CmdBindIndexBuffer(frame.command_buffer, backend.scene.test_meshes[2].buffers.index_buffer.handle, 0, .UINT32)

	push_constants := DrawPushConstants {
		world_matrix = bb.mat4(1.0),
	}

	vk.CmdPushConstants(
		frame.command_buffer,
		backend.metal_rough.opaque_pipeline.layout,
		{.VERTEX},
		0,
		size_of(DrawPushConstants),
		&push_constants,
	)

	vk.CmdDrawIndexed(
		frame.command_buffer,
		backend.scene.test_meshes[2].surfaces[0].count,
		1,
		backend.scene.test_meshes[2].surfaces[0].start_index,
		0,
		0,
	)

	vk.CmdEndRendering(frame.command_buffer)
}

draw_imgui :: proc(backend: ^Vulkan, frame: ^Frame) {

	color_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = backend.swapchain.views[frame.image_index],
		imageLayout = .GENERAL,
		loadOp      = .LOAD,
		storeOp     = .STORE,
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {offset = {0, 0}, extent = {backend.swapchain.extent.width, backend.swapchain.extent.height}},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
	}

	vk.CmdBeginRendering(frame.command_buffer, &rendering_info)

	im_vk.render_draw_data(im.get_draw_data(), frame.command_buffer)

	vk.CmdEndRendering(frame.command_buffer)

}

get_next_frame :: #force_inline proc(backend: ^Vulkan) -> (frame: ^Frame) #no_bounds_check {
	return &backend.frames[backend.next_frame_index % MAX_CONCURRENT_FRAMES]
}

set_next_frame :: #force_inline proc(backend: ^Vulkan) {
	backend.next_frame_index = (backend.next_frame_index + 1) % MAX_CONCURRENT_FRAMES
}
