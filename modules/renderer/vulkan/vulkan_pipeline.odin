package vulkan_backend

import bb "bedbug:core"
import "core:log"
import "core:slice"
import vk "vendor:vulkan"

PipelineType :: enum {
	TRIANGLE = 0,
	BACKGROUND,
}

Pipeline :: struct {
	handle: vk.Pipeline,
	layout: vk.PipelineLayout,
}

// PBR_VERTEX :: #load("../triangle.vert.spv")
// PBR_FRAGMENT :: #load("../triangle.frag.spv")

ShaderData :: struct {
	projection: bb.mat4,
	model:      bb.mat4,
	view:       bb.mat4,
}

PipelineStates :: struct {
	vertex_input:   vk.PipelineVertexInputStateCreateInfo,
	input_assembly: vk.PipelineInputAssemblyStateCreateInfo,
	rasterization:  vk.PipelineRasterizationStateCreateInfo,
	color_blend:    vk.PipelineColorBlendStateCreateInfo,
	multisample:    vk.PipelineMultisampleStateCreateInfo,
	depth_stencil:  vk.PipelineDepthStencilStateCreateInfo,
}

g_pipeline_cache: vk.PipelineCache
g_pipeline_layout: vk.PipelineLayout

vulkan_pipeline_setup :: proc(
	instance: Instance,
	device: Device,
	swapchain: Swapchain,
) -> (
	pipelines: [PipelineType]Pipeline,
) {

	// cache_info := vk.PipelineCacheCreateInfo {
	// 	sType = .PIPELINE_CACHE_CREATE_INFO,
	// }

	// vk_ok(vk.CreatePipelineCache(device.handle, &cache_info, nil, &g_pipeline_cache))

	// pipeline_layout_info := vk.PipelineLayoutCreateInfo {
	// 	sType          = .PIPELINE_LAYOUT_CREATE_INFO,
	// 	setLayoutCount = 1,
	// 	pSetLayouts    = &g_descriptor_set_layout,
	// }
	// vk_ok(vk.CreatePipelineLayout(device.handle, &pipeline_layout_info, nil, &g_pipeline_layout))

	// triangle_vertex_shader := shader_module_make(device.handle, PBR_VERTEX)
	// triangle_fragment_shader := shader_module_make(device.handle, PBR_FRAGMENT)

	// triangle_stages := make([]vk.PipelineShaderStageCreateInfo, 2)
	// triangle_stages[0] = shader_stage(.VERTEX, triangle_vertex_shader)
	// triangle_stages[1] = shader_stage(.FRAGMENT, triangle_fragment_shader)

	// vertex_input_bindings := make([]vk.VertexInputBindingDescription, 1)
	// vertex_input_bindings[0] = {
	// 	binding   = 0,
	// 	stride    = size_of(Vertex),
	// 	inputRate = .VERTEX,
	// }

	// triangle_vertex_input_attributes := make([]vk.VertexInputAttributeDescription, 2)
	// triangle_vertex_input_attributes[0] = {
	// 	location = 0,
	// 	binding  = 0,
	// 	format   = .R32G32B32_SFLOAT,
	// 	offset   = u32(offset_of(Vertex, position)),
	// }
	// triangle_vertex_input_attributes[1] = {
	// 	location = 1,
	// 	binding  = 0,
	// 	format   = .R32G32B32_SFLOAT,
	// 	offset   = u32(offset_of(Vertex, color)),
	// }

	// triangle_states := PipelineStates {
	// 	vertex_input   = vertex_input(vertex_input_bindings, triangle_vertex_input_attributes),
	// 	input_assembly = input_assembly(),
	// 	rasterization  = rasterization(),
	// 	color_blend    = color_blend(.DISABLED),
	// 	multisample    = multisample({._1}),
	// 	depth_stencil  = depth_stencil(.DEPTH_TEST_ENABLED),
	// }

	// pipelines[.TRIANGLE] = pipeline_compose(
	// 	device.handle,
	// 	swapchain,
	// 	triangle_states,
	// 	triangle_stages,
	// 	g_pipeline_layout,
	// )

	// vk.DestroyShaderModule(device.handle, triangle_vertex_shader, nil)
	// vk.DestroyShaderModule(device.handle, triangle_fragment_shader, nil)

	return pipelines
}

pipeline_compose :: proc(
	device: vk.Device,
	swapchain: Swapchain,
	states: PipelineStates,
	stages: []vk.PipelineShaderStageCreateInfo,
	layout: vk.PipelineLayout,
) -> (
	pipeline: Pipeline,
) {

	vertex_input_state := states.vertex_input
	input_assembly_state := states.input_assembly
	rasterization_state := states.rasterization
	multisample_state := states.multisample
	color_blend_state := states.color_blend
	depth_stencil_state := states.depth_stencil

	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	enabled_dynamic := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(enabled_dynamic)),
		pDynamicStates    = &enabled_dynamic[0],
	}

	color_format := swapchain.format.format
	rendering_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &color_format,
		// depthAttachmentFormat   = swapchain.target.depth.format,
		// stencilAttachmentFormat = swapchain.target.depth.format,
	}

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &rendering_info,
		stageCount          = u32(len(stages)),
		pStages             = raw_data(stages),
		pVertexInputState   = &vertex_input_state,
		pInputAssemblyState = &input_assembly_state,
		pRasterizationState = &rasterization_state,
		pMultisampleState   = &multisample_state,
		pColorBlendState    = &color_blend_state,
		pDepthStencilState  = &depth_stencil_state,
		pViewportState      = &viewport_state,
		pDynamicState       = &dynamic_state,
		layout              = layout,
	}

	vk_ok(vk.CreateGraphicsPipelines(device, g_pipeline_cache, 1, &pipeline_info, nil, &pipeline.handle))

	return pipeline
}

shader_stage :: proc(stage: vk.ShaderStageFlag, module: vk.ShaderModule) -> vk.PipelineShaderStageCreateInfo {

	return vk.PipelineShaderStageCreateInfo {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage = {stage},
		module = module,
		pName = "main",
	}
}

shader_module_make :: proc(device: vk.Device, code: []byte) -> (module: vk.ShaderModule) {

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = cast(^u32)raw_data(code),
	}

	vk_ok(vk.CreateShaderModule(device, &create_info, nil, &module))

	return module
}

vertex_input :: proc(
	bindings: []vk.VertexInputBindingDescription,
	attributes: []vk.VertexInputAttributeDescription,
) -> vk.PipelineVertexInputStateCreateInfo {

	return vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount = u32(len(bindings)),
		pVertexBindingDescriptions = raw_data(bindings),
		vertexAttributeDescriptionCount = u32(len(attributes)),
		pVertexAttributeDescriptions = raw_data(attributes),
	}

}

input_assembly :: proc() -> vk.PipelineInputAssemblyStateCreateInfo {

	return vk.PipelineInputAssemblyStateCreateInfo {
		sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}
}

rasterization :: proc() -> vk.PipelineRasterizationStateCreateInfo {

	return vk.PipelineRasterizationStateCreateInfo {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable = false,
		rasterizerDiscardEnable = false,
		polygonMode = .FILL,
		cullMode = {.BACK},
		frontFace = .CLOCKWISE,
		depthBiasEnable = false,
		lineWidth = 1.0,
	}
}

multisample :: proc(sample_count: vk.SampleCountFlags) -> vk.PipelineMultisampleStateCreateInfo {

	return vk.PipelineMultisampleStateCreateInfo {
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = sample_count,
		sampleShadingEnable = false,
		minSampleShading = 0.0,
		pSampleMask = nil,
		alphaToCoverageEnable = false,
		alphaToOneEnable = false,
	}
}

ColorBlendMode :: enum {
	DISABLED, // No blending (opaque)
	ALPHA_BLEND, // Standard alpha blending
}

color_blend :: proc(mode: ColorBlendMode) -> vk.PipelineColorBlendStateCreateInfo {
	attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
		colorBlendOp   = .ADD,
		alphaBlendOp   = .ADD,
	}

	switch mode {
	case .DISABLED:
		attachment.blendEnable = false
		attachment.srcColorBlendFactor = .ONE
		attachment.dstColorBlendFactor = .ZERO
		attachment.srcAlphaBlendFactor = .ONE
		attachment.dstAlphaBlendFactor = .ZERO

	case .ALPHA_BLEND:
		attachment.blendEnable = true
		attachment.srcColorBlendFactor = .SRC_ALPHA
		attachment.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA
		attachment.srcAlphaBlendFactor = .ONE
		attachment.dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA
	}

	return vk.PipelineColorBlendStateCreateInfo {
		sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments = &attachment,
	}
}

DepthStencilMode :: enum {
	DEPTH_TEST_ENABLED,
	DEPTH_TEST_DISABLED,
}

depth_stencil :: proc(mode: DepthStencilMode) -> vk.PipelineDepthStencilStateCreateInfo {
	stencil_default := vk.StencilOpState {
		failOp    = .KEEP,
		passOp    = .KEEP,
		compareOp = .ALWAYS,
	}

	switch mode {
	case .DEPTH_TEST_ENABLED:
		return vk.PipelineDepthStencilStateCreateInfo {
			sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
			depthTestEnable = true,
			depthWriteEnable = true,
			depthCompareOp = .LESS_OR_EQUAL,
			depthBoundsTestEnable = false,
			stencilTestEnable = false,
			front = stencil_default,
		}
	case .DEPTH_TEST_DISABLED:
		return vk.PipelineDepthStencilStateCreateInfo {
			sType                 = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
			depthTestEnable       = false,
			depthWriteEnable      = false,
			depthCompareOp        = .ALWAYS, // ignored, but set something legal
			depthBoundsTestEnable = false,
			stencilTestEnable     = false,
			front                 = stencil_default,
		}
	}

	return {} // fallback, shouldn't happen
}

background_pipelines_setup :: proc(self: ^Vulkan) {

	layout_info := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		pSetLayouts    = &self.frames[0].draw_image.descriptor.layout,
		setLayoutCount = 1,
	}

	vk_ok(vk.CreatePipelineLayout(self.device.handle, &layout_info, nil, &self.pipelines[.BACKGROUND].layout))

	GRADIENT_COMP_SPV :: #load("../shaders/bin/gradient.comp.spv")
	gradient_shader := shader_module_make(self.device.handle, GRADIENT_COMP_SPV)
	defer vk.DestroyShaderModule(self.device.handle, gradient_shader, nil)

	stage_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.COMPUTE},
		module = gradient_shader,
		pName  = "main",
	}

	pipeline_info := vk.ComputePipelineCreateInfo {
		sType  = .COMPUTE_PIPELINE_CREATE_INFO,
		layout = self.pipelines[.BACKGROUND].layout,
		stage  = stage_info,
	}

	vk_ok(
		vk.CreateComputePipelines(self.device.handle, 0, 1, &pipeline_info, nil, &self.pipelines[.BACKGROUND].handle),
	)

	resource_stack_push(
		&self.device.cleanup_stack,
		self.pipelines[.BACKGROUND].layout,
		self.pipelines[.BACKGROUND].handle,
	)
}

