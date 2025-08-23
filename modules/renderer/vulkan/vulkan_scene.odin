package vulkan_backend

import bb "bedbug:core"
import sa "core:container/small_array"
import vk "vendor:vulkan"

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
	test_meshes:       Meshes,
}

scene_setup :: proc(backend: ^Vulkan) -> (ok: bool) {

	descriptor_bindings2: DescriptorBindings
	sa.append(
		&descriptor_bindings2,
		vk.DescriptorSetLayoutBinding{binding = 0, descriptorCount = 1, descriptorType = .STORAGE_BUFFER},
	)
	backend.vertex_descriptor_layout = descriptor_set_new_layout(
		backend.device.handle,
		&descriptor_bindings2,
		{.VERTEX, .FRAGMENT},
	)

	descriptor_bindings: DescriptorBindings
	sa.append(
		&descriptor_bindings,
		vk.DescriptorSetLayoutBinding{binding = 0, descriptorCount = 1, descriptorType = .UNIFORM_BUFFER},
	)
	backend.scene.descriptor_layout = descriptor_set_new_layout(
		backend.device.handle,
		&descriptor_bindings,
		{.VERTEX, .FRAGMENT},
	)

	resource_stack_push(
		&backend.device.cleanup_stack,
		backend.vertex_descriptor_layout,
		backend.scene.descriptor_layout,
	)

	backend.scene.test_meshes, _ = meshes_create_from_gtlf(backend, "modules/renderer/assets/basicmesh.glb")

	white := bb.pack_unorm_4x8({1, 1, 1, 1})
	backend.textures.white_image = allocated_image_create_from_data(
		backend,
		&white,
		{1, 1, 1},
		.R8G8B8A8_UNORM,
		{.SAMPLED},
	)

	grey := bb.pack_unorm_4x8({0.66, 0.66, 0.66, 1})
	backend.textures.grey_image = allocated_image_create_from_data(
		backend,
		&grey,
		{1, 1, 1},
		.R8G8B8A8_UNORM,
		{.SAMPLED},
	)

	black := bb.pack_unorm_4x8({0, 0, 0, 0})
	backend.textures.black_image = allocated_image_create_from_data(
		backend,
		&black,
		{1, 1, 1},
		.R8G8B8A8_UNORM,
		{.SAMPLED},
	)

	// Checkerboard image
	magenta := bb.pack_unorm_4x8({1, 0, 1, 1})
	pixels: [16 * 16]u32
	for x in 0 ..< 16 {
		for y in 0 ..< 16 {
			pixels[y * 16 + x] = ((x % 2) ~ (y % 2)) != 0 ? magenta : black
		}
	}
	backend.textures.error_checkerboard_image = allocated_image_create_from_data(
		backend,
		raw_data(pixels[:]),
		{16, 16, 1},
		.R8G8B8A8_UNORM,
		{.SAMPLED},
	)

	sampler_info := vk.SamplerCreateInfo {
		sType     = .SAMPLER_CREATE_INFO,
		magFilter = .NEAREST,
		minFilter = .NEAREST,
	}

	vk_ok(
		vk.CreateSampler(backend.device.handle, &sampler_info, nil, &backend.textures.default_sampler_nearest),
	) or_return

	sampler_info.magFilter = .LINEAR
	sampler_info.minFilter = .LINEAR

	vk_ok(
		vk.CreateSampler(backend.device.handle, &sampler_info, nil, &backend.textures.default_sampler_linear),
	) or_return

	MetalRoughResources :: type_of(backend.metal_rough.resources)
	backend.metal_rough.resources = MetalRoughResources {
		color_image         = backend.textures.white_image,
		color_sampler       = backend.textures.default_sampler_linear,
		metal_rough_image   = backend.textures.white_image,
		metal_rough_sampler = backend.textures.default_sampler_linear,
	}

	MetalRoughParams :: type_of(backend.metal_rough.params)

	material_constants := allocated_buffer_create(backend, size_of(MetalRoughParams), {.UNIFORM_BUFFER}, .Cpu_To_Gpu)

	resource_stack_push(&backend.device.cleanup_stack, material_constants)

	scene_data := cast(^MetalRoughParams)material_constants.alloc_info.mapped_data
	scene_data.color = {1.0, 1.0, 1.0, 1.0}
	scene_data.metal_rough_factors = {1.0, 0.5, 0.0, 0.0}

	backend.metal_rough.resources.params_buffer = material_constants.handle
	backend.metal_rough.resources.params_buffer_offset = 0

	material_setup(backend) or_return

	resource_stack_push(
		&backend.device.cleanup_stack,
		backend.textures.white_image,
		backend.textures.grey_image,
		backend.textures.black_image,
		backend.textures.error_checkerboard_image,
		backend.textures.default_sampler_nearest,
		backend.textures.default_sampler_linear,
	)

	return true
}
