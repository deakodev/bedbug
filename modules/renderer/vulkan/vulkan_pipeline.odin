package vulkan_backend

import bb "bedbug:core"
import sa "core:container/small_array"
import "core:log"
import "core:slice"
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

ComputeEffect :: enum {
	GRADIENT,
	SKY,
}

GraphicsPipeline :: struct {
	handle: vk.Pipeline,
	layout: vk.PipelineLayout,
}

GraphicsEffect :: enum {
	MESH,
}

Pipeline :: union {
	GraphicsPipeline,
	ComputePipeline,
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

pipeline_setup :: proc(self: ^Vulkan) {

	background_pipelines_setup(self)

	{ 	// MESH
		info := pipeline_info_default()

		mesh_vert_shader := shader_module_make(
			self.device.handle,
			#load("../shaders/bin/colored_triangle_mesh.vert.spv"),
		)
		mesh_frag_shader := shader_module_make(self.device.handle, #load("../shaders/bin/colored_triangle.frag.spv"))
		defer vk.DestroyShaderModule(self.device.handle, mesh_vert_shader, nil)
		defer vk.DestroyShaderModule(self.device.handle, mesh_frag_shader, nil)

		shader_stages: PipelineShaderStagesInfo
		sa.append(&shader_stages, shader_stage(.VERTEX, mesh_vert_shader), shader_stage(.FRAGMENT, mesh_frag_shader))
		info[.SHADER_STAGES] = PipelineInfo(shader_stages)

		// vertex_input_info := &info[.VERTEX_INPUT].(PipelineVertexInputInfo)
		// input_assembly_info := &info[.INPUT_ASSEMBLY].(PipelineInputAssemblyInfo)
		// rasterization_info := &info[.RASTERIZATION].(PipelineRasterizationInfo)

		color_blend_info := &info[.COLOR_BLEND].(PipelineColorBlendInfo)
		blend_attachment := vk.PipelineColorBlendAttachmentState {
			colorWriteMask      = {.R, .G, .B, .A},
			blendEnable         = true,
			srcColorBlendFactor = .SRC_ALPHA,
			dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
			colorBlendOp        = .ADD,
			srcAlphaBlendFactor = .ONE,
			dstAlphaBlendFactor = .ZERO,
			alphaBlendOp        = .ADD,
		}
		color_blend_info.pAttachments = &blend_attachment

		// multisample_info := &info[.MULTISAMPLE].(PipelineMultisampleInfo)

		depth_stencil_info := &info[.DEPTH_STENCIL].(PipelineDepthStencilInfo)
		depth_stencil_info.depthTestEnable = true
		depth_stencil_info.depthWriteEnable = true
		depth_stencil_info.depthCompareOp = .GREATER_OR_EQUAL
		depth_stencil_info.minDepthBounds = 0.0
		depth_stencil_info.maxDepthBounds = 1.0

		// tessellation_info := &info[.TESSELLATION].(PipelineTessellationInfo)
		// viewport_info := &info[.VIEWPORT].(PipelineViewportInfo)
		// dynamic_info := &info[.DYNAMIC].(PipelineDynamicInfo)

		rendering_info := &info[.RENDERING].(PipelineRenderingInfo)
		rendering_info.colorAttachmentCount = 1
		rendering_info.pColorAttachmentFormats = &self.render_target.color_image.format
		rendering_info.depthAttachmentFormat = self.render_target.depth_image.format

		layout_info := &info[.LAYOUT].(PipelineLayoutInfo)
		layout_info.setLayoutCount = 1
		layout_info.pSetLayouts = &self.scene.descriptor_layout
		layout_info.pushConstantRangeCount = 1
		buffer_range := vk.PushConstantRange {
			offset     = 0,
			size       = size_of(DrawPushConstants),
			stageFlags = {.VERTEX},
		}
		layout_info.pPushConstantRanges = &buffer_range

		pipeline_create(self, &info, &self.pipelines[.MESH])
	}
}

background_pipelines_setup :: proc(self: ^Vulkan) {

	push_constant := vk.PushConstantRange {
		offset     = 0,
		size       = size_of(ComputePushConstants),
		stageFlags = {.COMPUTE},
	}

	layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &self.render_target.descriptor.layout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &push_constant,
	}

	pipeline_layout: vk.PipelineLayout
	vk_ok(vk.CreatePipelineLayout(self.device.handle, &layout_info, nil, &pipeline_layout))

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

	{ 	// GRADIENT
		GRADIENT_COLOR_SPV :: #load("../shaders/bin/gradient_color.comp.spv")
		gradient_shader := shader_module_make(self.device.handle, GRADIENT_COLOR_SPV)
		defer vk.DestroyShaderModule(self.device.handle, gradient_shader, nil)

		compute_info.stage.module = gradient_shader

		pipeline := ComputePipeline {
			layout = pipeline_layout,
			push_constants = {_1 = {1, 0, 0, 1}, _2 = {0, 0, 1, 1}, _3 = {}, _4 = {}},
			name = "Gradient",
		}

		vk_ok(vk.CreateComputePipelines(self.device.handle, 0, 1, &compute_info, nil, &pipeline.handle))

		self.background.effects[.GRADIENT] = pipeline
	}

	{ 	// SKY
		SKY_SPV :: #load("../shaders/bin/sky.comp.spv")
		sky_shader := shader_module_make(self.device.handle, SKY_SPV)
		defer vk.DestroyShaderModule(self.device.handle, sky_shader, nil)

		compute_info.stage.module = sky_shader

		pipeline := ComputePipeline {
			layout = pipeline_layout,
			push_constants = {_1 = {0.1, 0.2, 0.4, 0.97}, _2 = {}, _3 = {}, _4 = {}},
			name = "Sky",
		}

		vk_ok(vk.CreateComputePipelines(self.device.handle, 0, 1, &compute_info, nil, &pipeline.handle))

		self.background.effects[.SKY] = pipeline
	}

	resource_stack_push(
		&self.device.cleanup_stack,
		self.background.effects[.GRADIENT].layout, // todo: shared
		self.background.effects[.GRADIENT].handle,
		self.background.effects[.SKY].handle,
	)
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

	info[.COLOR_BLEND] = PipelineColorBlendInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = &vk.PipelineColorBlendAttachmentState{colorWriteMask = {.R, .G, .B, .A}},
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

pipeline_create :: proc(self: ^Vulkan, info: ^[PipelineInfoType]PipelineInfo, pipeline: ^GraphicsPipeline) {

	vk_ok(vk.CreatePipelineLayout(self.device.handle, &info[.LAYOUT].(PipelineLayoutInfo), nil, &pipeline.layout))
	resource_stack_push(&self.device.cleanup_stack, pipeline.layout)

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

	vk_ok(vk.CreateGraphicsPipelines(self.device.handle, 0, 1, &pipeline_info, nil, &pipeline.handle))
	resource_stack_push(&self.device.cleanup_stack, pipeline.handle)
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
