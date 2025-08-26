package vulkan_backend

import bb "bedbug:core"
import sa "core:container/small_array"
import "core:log"
import vk "vendor:vulkan"


MetalRough :: struct {
	params:               struct {
		color:               bb.vec4,
		metal_rough_factors: bb.vec4,
		// // Padding, we need it anyway for uniform buffers
		extra:               [14]bb.vec4,
	},
	resources:            struct {
		color_image:          AllocatedImage,
		color_sampler:        vk.Sampler,
		metal_rough_image:    AllocatedImage,
		metal_rough_sampler:  vk.Sampler,
		params_buffer:        vk.Buffer,
		params_buffer_offset: u32,
	},
	descriptor_set:       vk.DescriptorSet,
	opaque_pipeline:      Pipeline,
	transparent_pipeline: Pipeline,
}

MaterialScheme :: union {
	MetalRough,
}

Material :: struct($T: typeid) {
	scheme:   T,
	pipeline: ^Pipeline,
}

material_setup :: proc(backend: ^Vulkan) -> (ok: bool) {

	descriptor_bindings: DescriptorBindings
	sa.append(
		&descriptor_bindings,
		vk.DescriptorSetLayoutBinding{binding = 0, descriptorCount = 1, descriptorType = .UNIFORM_BUFFER},
		vk.DescriptorSetLayoutBinding{binding = 1, descriptorCount = 1, descriptorType = .COMBINED_IMAGE_SAMPLER},
		vk.DescriptorSetLayoutBinding{binding = 2, descriptorCount = 1, descriptorType = .COMBINED_IMAGE_SAMPLER},
	)
	backend.material_descriptor_layout = descriptor_set_new_layout(
		backend.device.handle,
		&descriptor_bindings,
		{.VERTEX, .FRAGMENT},
	)

	resource_stack_push(&backend.device.cleanup_stack, backend.material_descriptor_layout)

	metal_rough_setup(backend) or_return

	return true
}

metal_rough_setup :: proc(backend: ^Vulkan) -> (ok: bool) {

	mesh_vert_shader := shader_module_make(backend.device.handle, #load("../shaders/bin/simple_mesh.vert.spv"))
	mesh_frag_shader := shader_module_make(backend.device.handle, #load("../shaders/bin/simple_mesh.frag.spv"))
	defer vk.DestroyShaderModule(backend.device.handle, mesh_vert_shader, nil)
	defer vk.DestroyShaderModule(backend.device.handle, mesh_frag_shader, nil)

	shader_stages: PipelineShaderStagesInfo
	sa.append(&shader_stages, shader_stage(.VERTEX, mesh_vert_shader), shader_stage(.FRAGMENT, mesh_frag_shader))

	info := pipeline_info_default()
	info[.SHADER_STAGES] = PipelineInfo(shader_stages)

	layouts := []vk.DescriptorSetLayout {
		backend.vertex_descriptor_layout,
		backend.scene.descriptor_layout,
		backend.material_descriptor_layout,
	}

	layout_info := &info[.LAYOUT].(PipelineLayoutInfo)
	layout_info.setLayoutCount = u32(len(layouts))
	layout_info.pSetLayouts = raw_data(layouts[:])
	layout_info.pushConstantRangeCount = 1
	buffer_range := vk.PushConstantRange {
		offset     = 0,
		size       = size_of(DrawPushConstants),
		stageFlags = {.VERTEX},
	}
	layout_info.pPushConstantRanges = &buffer_range

	depth_stencil_info := &info[.DEPTH_STENCIL].(PipelineDepthStencilInfo)
	depth_stencil_info.depthTestEnable = true
	depth_stencil_info.depthWriteEnable = true
	depth_stencil_info.depthCompareOp = .GREATER_OR_EQUAL
	depth_stencil_info.minDepthBounds = 0.0
	depth_stencil_info.maxDepthBounds = 1.0

	rendering_info := &info[.RENDERING].(PipelineRenderingInfo)
	rendering_info.colorAttachmentCount = 1
	rendering_info.pColorAttachmentFormats = &backend.draw_target.color_image.format
	rendering_info.depthAttachmentFormat = backend.draw_target.depth_image.format

	pipeline_create(backend, &info, &backend.metal_rough.opaque_pipeline)

	blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask      = {.R, .G, .B, .A},
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ZERO,
		alphaBlendOp        = .ADD,
	}
	color_blend_info := &info[.COLOR_BLEND].(PipelineColorBlendInfo)
	color_blend_info.attachmentCount = 1
	color_blend_info.pAttachments = &blend_attachment

	depth_stencil_info.depthWriteEnable = false

	// pipeline_create(backend, &info, &backend.metal_rough.transparent_pipeline)

	{
		alloc_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool     = backend.draw_target.descriptor.pool, // todo: temp
			descriptorSetCount = 1,
			pSetLayouts        = &backend.material_descriptor_layout,
		}

		vk_ok(
			vk.AllocateDescriptorSets(backend.device.handle, &alloc_info, &backend.metal_rough.descriptor_set),
		) or_return

		writer: DescriptorWriter
		descriptor_writer_setup(&writer, backend.device.handle)

		descriptor_writer_write_buffer(
			&writer,
			0,
			backend.metal_rough.resources.params_buffer,
			size_of(backend.metal_rough.params),
			vk.DeviceSize(backend.metal_rough.resources.params_buffer_offset),
			.UNIFORM_BUFFER,
		)
		descriptor_writer_write_image(
			&writer,
			1,
			backend.metal_rough.resources.color_image.view,
			backend.metal_rough.resources.color_sampler,
			.SHADER_READ_ONLY_OPTIMAL,
			.COMBINED_IMAGE_SAMPLER,
		)
		descriptor_writer_write_image(
			&writer,
			2,
			backend.metal_rough.resources.metal_rough_image.view,
			backend.metal_rough.resources.metal_rough_sampler,
			.SHADER_READ_ONLY_OPTIMAL,
			.COMBINED_IMAGE_SAMPLER,
		)

		descriptor_writer_update_set(&writer, backend.metal_rough.descriptor_set)
	}

	return true
}
