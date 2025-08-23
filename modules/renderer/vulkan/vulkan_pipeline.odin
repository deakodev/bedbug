package vulkan_backend

import bb "bedbug:core"
import sa "core:container/small_array"
import "core:log"
import "core:slice"
import vk "vendor:vulkan"

Pipeline :: struct {
	handle: vk.Pipeline,
	layout: vk.PipelineLayout,
}

PipelineType :: enum {
	MESH,
	MATERIAL,
}

MAX_SHADER_STAGES :: #config(MAX_SHADER_STAGES, 8)

PipelineShaderStagesInfo :: sa.Small_Array(MAX_SHADER_STAGES, vk.PipelineShaderStageCreateInfo)
PipelineVertexInputInfo :: vk.PipelineVertexInputStateCreateInfo
PipelineInputAssemblyInfo :: vk.PipelineInputAssemblyStateCreateInfo
PipelineRasterizationInfo :: vk.PipelineRasterizationStateCreateInfo
PipelineColorBlendInfo :: vk.PipelineColorBlendStateCreateInfo
PipelineMultisampleInfo :: vk.PipelineMultisampleStateCreateInfo
PipelineDepthStencilInfo :: vk.PipelineDepthStencilStateCreateInfo
PipelineTessellationInfo :: vk.PipelineTessellationStateCreateInfo
PipelineViewportInfo :: vk.PipelineViewportStateCreateInfo
PipelineDynamicInfo :: vk.PipelineDynamicStateCreateInfo
PipelineRenderingInfo :: vk.PipelineRenderingCreateInfo
PipelineLayoutInfo :: vk.PipelineLayoutCreateInfo

PipelineInfo :: union {
	PipelineShaderStagesInfo,
	PipelineVertexInputInfo,
	PipelineInputAssemblyInfo,
	PipelineRasterizationInfo,
	PipelineColorBlendInfo,
	PipelineMultisampleInfo,
	PipelineDepthStencilInfo,
	PipelineTessellationInfo,
	PipelineViewportInfo,
	PipelineDynamicInfo,
	PipelineRenderingInfo,
	PipelineLayoutInfo,
}

PipelineInfoType :: enum {
	SHADER_STAGES,
	VERTEX_INPUT,
	INPUT_ASSEMBLY,
	RASTERIZATION,
	COLOR_BLEND,
	MULTISAMPLE,
	DEPTH_STENCIL,
	TESSELLATION,
	VIEWPORT,
	DYNAMIC,
	RENDERING,
	LAYOUT,
}

/* Pipeline Template 
	-----------------
	info := pipeline_info_default()

	mesh_vert_shader := shader_module_make(backend.device.handle, #load("..."))
	mesh_frag_shader := shader_module_make(backend.device.handle, #load("..."))
	defer vk.DestroyShaderModule(backend.device.handle, mesh_vert_shader, nil)
	defer vk.DestroyShaderModule(backend.device.handle, mesh_frag_shader, nil)

	shader_stages: PipelineShaderStagesInfo
	sa.append(&shader_stages, shader_stage(.VERTEX, mesh_vert_shader), shader_stage(.FRAGMENT, mesh_frag_shader))
	info[.SHADER_STAGES] = PipelineInfo(shader_stages)

	layouts := []vk.DescriptorSetLayout{...}
	layout_info := &info[.LAYOUT].(PipelineLayoutInfo)
	vertex_input_info := &info[.VERTEX_INPUT].(PipelineVertexInputInfo)
	input_assembly_info := &info[.INPUT_ASSEMBLY].(PipelineInputAssemblyInfo)
	rasterization_info := &info[.RASTERIZATION].(PipelineRasterizationInfo)
	color_blend_info := &info[.COLOR_BLEND].(PipelineColorBlendInfo)
	multisample_info := &info[.MULTISAMPLE].(PipelineMultisampleInfo)
	depth_stencil_info := &info[.DEPTH_STENCIL].(PipelineDepthStencilInfo)
	tessellation_info := &info[.TESSELLATION].(PipelineTessellationInfo)
	viewport_info := &info[.VIEWPORT].(PipelineViewportInfo)
	dynamic_info := &info[.DYNAMIC].(PipelineDynamicInfo)
	rendering_info := &info[.RENDERING].(PipelineRenderingInfo)

	pipeline_create(backend, &info, &backend.pipelines[...])
	-----------------
*/

pipeline_setup :: proc(backend: ^Vulkan) {

}

pipeline_info_default :: proc() -> (info: [PipelineInfoType]PipelineInfo) {

	info[.VERTEX_INPUT] = PipelineVertexInputInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}

	info[.INPUT_ASSEMBLY] = PipelineInputAssemblyInfo {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}

	info[.RASTERIZATION] = PipelineRasterizationInfo {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		lineWidth   = 1.0,
		cullMode    = vk.CullModeFlags_NONE,
		frontFace   = .CLOCKWISE,
	}

	@(static) color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
	}
	info[.COLOR_BLEND] = PipelineColorBlendInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}

	min_sample_shading := f32(1.0)
	info[.MULTISAMPLE] = PipelineMultisampleInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
		minSampleShading     = min_sample_shading,
		sampleShadingEnable  = min_sample_shading < 1.0,
	}

	info[.DEPTH_STENCIL] = PipelineDepthStencilInfo {
		sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
	}

	info[.TESSELLATION] = PipelineTessellationInfo {
		sType = .PIPELINE_TESSELLATION_STATE_CREATE_INFO,
	}

	info[.VIEWPORT] = PipelineViewportInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	@(static) dynamic_states := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}
	info[.DYNAMIC] = PipelineDynamicInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		pDynamicStates    = raw_data(dynamic_states[:]),
		dynamicStateCount = u32(len(dynamic_states)),
	}

	info[.RENDERING] = PipelineRenderingInfo {
		sType = .PIPELINE_RENDERING_CREATE_INFO,
	}

	info[.LAYOUT] = PipelineLayoutInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
	}

	return info
}

pipeline_create :: proc(backend: ^Vulkan, info: ^[PipelineInfoType]PipelineInfo, pipeline: ^Pipeline) {

	vk_ok(vk.CreatePipelineLayout(backend.device.handle, &info[.LAYOUT].(PipelineLayoutInfo), nil, &pipeline.layout))
	resource_stack_push(&backend.device.cleanup_stack, pipeline.layout)

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &info[.RENDERING],
		flags               = nil,
		stageCount          = u32(sa.len(info[.SHADER_STAGES].(PipelineShaderStagesInfo))),
		pStages             = raw_data(sa.slice(&info[.SHADER_STAGES].(PipelineShaderStagesInfo))),
		pVertexInputState   = &info[.VERTEX_INPUT].(PipelineVertexInputInfo),
		pInputAssemblyState = &info[.INPUT_ASSEMBLY].(PipelineInputAssemblyInfo),
		pTessellationState  = &info[.TESSELLATION].(PipelineTessellationInfo),
		pViewportState      = &info[.VIEWPORT].(PipelineViewportInfo),
		pRasterizationState = &info[.RASTERIZATION].(PipelineRasterizationInfo),
		pMultisampleState   = &info[.MULTISAMPLE].(PipelineMultisampleInfo),
		pDepthStencilState  = &info[.DEPTH_STENCIL].(PipelineDepthStencilInfo),
		pColorBlendState    = &info[.COLOR_BLEND].(PipelineColorBlendInfo),
		pDynamicState       = &info[.DYNAMIC].(PipelineDynamicInfo),
		layout              = pipeline.layout,
		basePipelineHandle  = {},
		basePipelineIndex   = -1,
	}

	vk_ok(vk.CreateGraphicsPipelines(backend.device.handle, 0, 1, &pipeline_info, nil, &pipeline.handle))
	resource_stack_push(&backend.device.cleanup_stack, pipeline.handle)
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

shader_stage :: proc(stage: vk.ShaderStageFlag, module: vk.ShaderModule) -> vk.PipelineShaderStageCreateInfo {

	return vk.PipelineShaderStageCreateInfo {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage = {stage},
		module = module,
		pName = "main",
	}
}
