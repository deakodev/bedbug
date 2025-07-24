package vulkan_backend

import sa "core:container/small_array"
import "core:log"
import vk "vendor:vulkan"

MAX_BOUND_DESCRIPTOR_SETS :: #config(MAX_BOUND_DESCRIPTOR_SETS, 16)
MAX_SIZES_DESCRIPTOR_POOL :: #config(MAX_BOUND_DESCRIPTOR_SETS, 16)

DescriptorBindings :: sa.Small_Array(MAX_BOUND_DESCRIPTOR_SETS, vk.DescriptorSetLayoutBinding)
DescriptorPoolSizes :: sa.Small_Array(MAX_SIZES_DESCRIPTOR_POOL, vk.DescriptorPoolSize)

PoolSizeRatio :: struct {
	type:  vk.DescriptorType,
	value: f32,
}

vulkan_descriptor_setup :: proc(self: ^Vulkan) {

	size_ratios := []PoolSizeRatio{{.STORAGE_IMAGE, 1}}

	self.descriptor_pool = descriptor_pool_make(self.device.handle, 10, size_ratios)
	resource_stack_push(&self.device.cleanup_stack, self.descriptor_pool)
}

descriptor_pool_make :: proc(
	device: vk.Device,
	max_sets: u32,
	size_ratios: []PoolSizeRatio,
) -> (
	pool: vk.DescriptorPool,
) {

	pool_sizes: DescriptorPoolSizes
	for &ratio in size_ratios {
		sa.push_back(
			&pool_sizes,
			vk.DescriptorPoolSize{type = ratio.type, descriptorCount = u32(ratio.value) * max_sets},
		)
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = max_sets,
		poolSizeCount = u32(sa.len(pool_sizes)),
		pPoolSizes    = raw_data(sa.slice(&pool_sizes)),
	}

	vk_ok(vk.CreateDescriptorPool(device, &pool_info, nil, &pool))

	return pool
}

descriptor_layout_make :: proc(
	device: vk.Device,
	bindings: ^DescriptorBindings,
	stage_flags: vk.ShaderStageFlags,
	layout_flags: vk.DescriptorSetLayoutCreateFlags = {},
	loc := #caller_location,
) -> (
	layout: vk.DescriptorSetLayout,
) {

	log.assert(stage_flags != {}, "failed to specify shader stages for descriptor set layout.", loc = loc)
	log.assert(sa.len(bindings^) > 0, "failed to specify bindings for descriptor set layout.", loc = loc)
	log.assert(sa.len(bindings^) < MAX_BOUND_DESCRIPTOR_SETS, loc = loc)

	for &binding in sa.slice(bindings) {
		binding.stageFlags += stage_flags
	}

	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		pNext        = nil,
		bindingCount = u32(sa.len(bindings^)),
		pBindings    = raw_data(sa.slice(bindings)),
		flags        = layout_flags,
	}

	vk_ok(vk.CreateDescriptorSetLayout(device, &layout_info, nil, &layout))

	return layout
}

descriptor_set_allocate :: proc(
	device: vk.Device,
	pool: vk.DescriptorPool,
	layout: ^vk.DescriptorSetLayout,
) -> (
	set: vk.DescriptorSet,
) {

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = pool,
		descriptorSetCount = 1,
		pSetLayouts        = layout,
	}

	vk_ok(vk.AllocateDescriptorSets(device, &alloc_info, &set))

	return set
}
