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

PipelineInfo :: union {
	ShaderStages,
	VertexInput,
	InputAssembly,
	Rasterization,
	ColorBlend,
	Multisample,
	DepthStencil,
	Tessellation,
	Viewport,
	Dynamic,
	Rendering,
	Layout,
}

PipelineInfoKind :: enum {
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

PipelinePatch :: union {
	VertexInputPatch,
	InputAssemblyPatch,
	RasterizationPatch,
	ColorBlendPatch,
	MultisamplePatch,
	DepthStencilPatch,
	TessellationPatch,
	ViewportPatch,
	DynamicPatch,
	RenderingPatch,
	LayoutPatch,
}

MAX_SHADER_STAGES :: #config(MAX_SHADER_STAGES, 8)
ShaderStages :: sa.Small_Array(MAX_SHADER_STAGES, vk.PipelineShaderStageCreateInfo)

VertexInput :: vk.PipelineVertexInputStateCreateInfo
VertexInputPatch :: struct {}

InputAssembly :: vk.PipelineInputAssemblyStateCreateInfo
InputAssemblyPatch :: struct {
	topology:          Maybe(vk.PrimitiveTopology),
	primitive_restart: Maybe(b32),
}

Rasterization :: vk.PipelineRasterizationStateCreateInfo
RasterizationPatch :: struct {
	polygon_mode: Maybe(vk.PolygonMode),
	line_width:   Maybe(f32),
	cull_mode:    Maybe(vk.CullModeFlags),
	front_face:   Maybe(vk.FrontFace),
}

ColorBlend :: vk.PipelineColorBlendStateCreateInfo
ColorBlendPatch :: struct {}

Multisample :: vk.PipelineMultisampleStateCreateInfo
MultisamplePatch :: struct {}

DepthStencil :: vk.PipelineDepthStencilStateCreateInfo
DepthStencilPatch :: struct {}

Tessellation :: vk.PipelineTessellationStateCreateInfo
TessellationPatch :: struct {}

Viewport :: vk.PipelineViewportStateCreateInfo
ViewportPatch :: struct {}

Dynamic :: vk.PipelineDynamicStateCreateInfo
DynamicPatch :: struct {}

Rendering :: vk.PipelineRenderingCreateInfo
RenderingPatch :: struct {
	color_attachment_count:   Maybe(u32),
	color_attachment_formats: Maybe([^]vk.Format),
	depth_attachment_format:  Maybe(vk.Format),
}

Layout :: vk.PipelineLayoutCreateInfo
LayoutPatch :: struct {
	set_layout_count:          Maybe(u32),
	p_set_layouts:             Maybe([^]vk.DescriptorSetLayout),
	push_constant_range_count: Maybe(u32),
	p_push_constant_ranges:    Maybe([^]vk.PushConstantRange),
}

pipeline_setup :: proc(self: ^Vulkan) {

	background_pipelines_setup(self)

	pipeline_info := pipeline_info_defaults()

	{ 	// MESH
		mesh_vert_shader := shader_module_make(
			self.device.handle,
			#load("../shaders/bin/colored_triangle_mesh.vert.spv"),
		)
		mesh_frag_shader := shader_module_make(self.device.handle, #load("../shaders/bin/colored_triangle.frag.spv"))
		defer vk.DestroyShaderModule(self.device.handle, mesh_vert_shader, nil)
		defer vk.DestroyShaderModule(self.device.handle, mesh_frag_shader, nil)

		shader_stages: ShaderStages
		sa.append(&shader_stages, shader_stage(.VERTEX, mesh_vert_shader), shader_stage(.FRAGMENT, mesh_frag_shader))
		pipeline_info[.SHADER_STAGES] = shader_stages

		pipeline_patches: [PipelineInfoKind]PipelinePatch
		pipeline_patches[.VERTEX_INPUT] = InputAssemblyPatch{}
		pipeline_patches[.INPUT_ASSEMBLY] = InputAssemblyPatch{}
		pipeline_patches[.RASTERIZATION] = RasterizationPatch{}
		pipeline_patches[.COLOR_BLEND] = ColorBlendPatch{}
		pipeline_patches[.MULTISAMPLE] = MultisamplePatch{}
		pipeline_patches[.DEPTH_STENCIL] = DepthStencilPatch{}
		pipeline_patches[.TESSELLATION] = TessellationPatch{}
		pipeline_patches[.VIEWPORT] = ViewportPatch{}
		pipeline_patches[.DYNAMIC] = DynamicPatch{}
		pipeline_patches[.RENDERING] = RenderingPatch {
			color_attachment_count   = 1,
			color_attachment_formats = &self.swapchain.format.format,
			depth_attachment_format  = .UNDEFINED,
		}

		buffer_range := vk.PushConstantRange {
			offset     = 0,
			size       = size_of(DrawPushConstants),
			stageFlags = {.VERTEX},
		}

		pipeline_patches[.LAYOUT] = LayoutPatch {
			set_layout_count          = 1,
			p_set_layouts             = &self.scene.descriptor_layout,
			push_constant_range_count = 1,
			p_push_constant_ranges    = &buffer_range,
		}

		pipeline_info_compose(self, &pipeline_info, &pipeline_patches, &self.pipelines[.MESH])
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
		pSetLayouts            = &self.draw.descriptor.layout,
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

pipeline_info_defaults :: proc() -> (infos: [PipelineInfoKind]PipelineInfo) {

	infos[.VERTEX_INPUT] = VertexInput {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}

	infos[.INPUT_ASSEMBLY] = InputAssembly {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	infos[.RASTERIZATION] = Rasterization {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		lineWidth   = 1.0,
		cullMode    = vk.CullModeFlags_NONE,
		frontFace   = .CLOCKWISE,
	}

	infos[.COLOR_BLEND] = ColorBlend {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = &vk.PipelineColorBlendAttachmentState {
			colorWriteMask = {.R, .G, .B, .A},
			blendEnable = false,
		},
	}

	min_sample_shading := f32(1.0)
	infos[.MULTISAMPLE] = Multisample {
		sType                 = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples  = {._1},
		minSampleShading      = min_sample_shading,
		sampleShadingEnable   = min_sample_shading < 1.0,
		pSampleMask           = nil,
		alphaToCoverageEnable = false,
		alphaToOneEnable      = false,
	}

	infos[.DEPTH_STENCIL] = DepthStencil {
		sType                 = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable       = false,
		depthWriteEnable      = false,
		depthCompareOp        = .NEVER,
		depthBoundsTestEnable = false,
		stencilTestEnable     = false,
		front                 = {},
		back                  = {},
		minDepthBounds        = 0.0,
		maxDepthBounds        = 1.0,
	}

	infos[.TESSELLATION] = Tessellation {
		sType = .PIPELINE_TESSELLATION_STATE_CREATE_INFO,
	}

	infos[.VIEWPORT] = Viewport {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	@(static) dynamic_states := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}
	infos[.DYNAMIC] = Dynamic {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		pDynamicStates    = raw_data(dynamic_states[:]),
		dynamicStateCount = u32(len(dynamic_states)),
	}

	infos[.RENDERING] = Rendering {
		sType = .PIPELINE_RENDERING_CREATE_INFO,
	}

	infos[.LAYOUT] = Layout {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
	}

	return infos
}

pipeline_info_compose :: proc(
	self: ^Vulkan,
	infos: ^[PipelineInfoKind]PipelineInfo,
	patches: ^[PipelineInfoKind]PipelinePatch,
	pipeline: ^GraphicsPipeline,
) {

	for kind in PipelineInfoKind {
		patch := patches[kind]
		if (patch != PipelinePatch{}) {
			pipeline_info_patch(kind, &infos[kind], &patch)
		}
	}

	vk_ok(vk.CreatePipelineLayout(self.device.handle, &infos[.LAYOUT].(Layout), nil, &pipeline.layout))
	resource_stack_push(&self.device.cleanup_stack, pipeline.layout)

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &infos[.RENDERING],
		flags               = nil,
		stageCount          = u32(sa.len(infos[.SHADER_STAGES].(ShaderStages))),
		pStages             = raw_data(sa.slice(&infos[.SHADER_STAGES].(ShaderStages))),
		pVertexInputState   = &infos[.VERTEX_INPUT].(VertexInput),
		pInputAssemblyState = &infos[.INPUT_ASSEMBLY].(InputAssembly),
		pTessellationState  = &infos[.TESSELLATION].(Tessellation),
		pViewportState      = &infos[.VIEWPORT].(Viewport),
		pRasterizationState = &infos[.RASTERIZATION].(Rasterization),
		pMultisampleState   = &infos[.MULTISAMPLE].(Multisample),
		pDepthStencilState  = &infos[.DEPTH_STENCIL].(DepthStencil),
		pColorBlendState    = &infos[.COLOR_BLEND].(ColorBlend),
		pDynamicState       = &infos[.DYNAMIC].(Dynamic),
		layout              = pipeline.layout,
		basePipelineHandle  = {},
		basePipelineIndex   = -1,
	}

	vk_ok(vk.CreateGraphicsPipelines(self.device.handle, 0, 1, &pipeline_info, nil, &pipeline.handle))
	resource_stack_push(&self.device.cleanup_stack, pipeline.handle)
}

pipeline_info_patch :: proc(kind: PipelineInfoKind, info: ^PipelineInfo, patch: ^PipelinePatch) {

	#partial switch kind {
	case .INPUT_ASSEMBLY:
		input_assembly_patch(&info.(InputAssembly), &patch.(InputAssemblyPatch))
	case .RASTERIZATION:
		rasterization_patch(&info.(Rasterization), &patch.(RasterizationPatch))
	case .LAYOUT:
		layout_patch(&info.(Layout), &patch.(LayoutPatch))
	// todo add cases as needed
	}
}

unwrap_and_patch :: proc(field: ^$T, maybe: Maybe(T)) {

	if maybe != nil {
		field^ = maybe.?
	}
}

input_assembly_patch :: proc(info: ^InputAssembly, patch: ^InputAssemblyPatch) {

	unwrap_and_patch(&info.topology, patch.topology)
	unwrap_and_patch(&info.primitiveRestartEnable, patch.primitive_restart)
}


rasterization_patch :: proc(info: ^Rasterization, patch: ^RasterizationPatch) {

	unwrap_and_patch(&info.polygonMode, patch.polygon_mode)
	unwrap_and_patch(&info.lineWidth, patch.line_width)
	unwrap_and_patch(&info.cullMode, patch.cull_mode)
	unwrap_and_patch(&info.frontFace, patch.front_face)
}

layout_patch :: proc(info: ^Layout, patch: ^LayoutPatch) {

	unwrap_and_patch(&info.setLayoutCount, patch.set_layout_count)
	unwrap_and_patch(&info.pSetLayouts, patch.p_set_layouts)
	unwrap_and_patch(&info.pushConstantRangeCount, patch.push_constant_range_count)
	unwrap_and_patch(&info.pPushConstantRanges, patch.p_push_constant_ranges)
}
