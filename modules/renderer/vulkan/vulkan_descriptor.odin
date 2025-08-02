package vulkan_backend

import "bedbug:vendor/vma"
import sa "core:container/small_array"
import "core:log"
import vk "vendor:vulkan"

Descriptor :: struct {
	set:    vk.DescriptorSet,
	layout: vk.DescriptorSetLayout,
	pool:   vk.DescriptorPool,
}

descriptor_setup :: proc(self: ^Vulkan) {

	{ // scene
		descriptor_bindings: DescriptorBindings
		sa.append(
			&descriptor_bindings,
			vk.DescriptorSetLayoutBinding{binding = 0, descriptorCount = 1, descriptorType = .UNIFORM_BUFFER},
		)
		self.scene.descriptor_layout = descriptor_set_new_layout(
			self.device.handle,
			&descriptor_bindings,
			{.VERTEX, .FRAGMENT},
		)
	}

	// todo: move the draw image creation to proper location
	{ // draw
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

		vk_ok(vk.CreateDescriptorPool(self.device.handle, &pool_info, nil, &self.draw.descriptor.pool))

		image_info := vk.ImageCreateInfo {
			sType       = .IMAGE_CREATE_INFO,
			imageType   = .D2,
			format      = .R16G16B16A16_SFLOAT,
			extent      = {self.swapchain.extent.width, self.swapchain.extent.height, 1},
			mipLevels   = 1,
			arrayLayers = 1,
			samples     = {._1},
			tiling      = .OPTIMAL,
			usage       = {.TRANSFER_SRC, .TRANSFER_DST, .STORAGE, .COLOR_ATTACHMENT},
		}

		image_alloc_info := vma.Allocation_Create_Info {
			usage          = .Gpu_Only,
			required_flags = {.DEVICE_LOCAL},
		}

		image_view_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			viewType = .D2,
			format = image_info.format,
			subresourceRange = {levelCount = 1, layerCount = 1, aspectMask = {.COLOR}},
			image = self.draw.image.handle,
		}

		descriptor_bindings: DescriptorBindings
		sa.append(
			&descriptor_bindings,
			vk.DescriptorSetLayoutBinding{binding = 0, descriptorCount = 1, descriptorType = .STORAGE_IMAGE},
		)
		self.draw.descriptor.layout = descriptor_set_new_layout(self.device.handle, &descriptor_bindings, {.COMPUTE})

		{ 	// draw image
			self.draw.image = AllocatedImage {
				format    = image_info.format,
				extent    = image_info.extent,
				allocator = self.device.vma_allocator,
			}

			vk_ok(
				vma.create_image(
					self.device.vma_allocator,
					image_info,
					image_alloc_info,
					&self.draw.image.handle,
					&self.draw.image.allocation,
					nil,
				),
			)

			image_view_info.image = self.draw.image.handle

			vk_ok(vk.CreateImageView(self.device.handle, &image_view_info, nil, &self.draw.image.view))
		}

		alloc_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool     = self.draw.descriptor.pool,
			descriptorSetCount = 1,
			pSetLayouts        = &self.draw.descriptor.layout,
		}

		vk_ok(vk.AllocateDescriptorSets(self.device.handle, &alloc_info, &self.draw.descriptor.set))

		writer: DescriptorWriter
		descriptor_writer_setup(&writer, self.device.handle)

		descriptor_writer_write_image(
			&writer,
			binding = 0,
			image = self.draw.image.view,
			sampler = 0,
			layout = .GENERAL,
			type = .STORAGE_IMAGE,
		)

		descriptor_writer_update_set(&writer, self.draw.descriptor.set)
	}

	resource_stack_push(
		&self.device.cleanup_stack,
		self.scene.descriptor_layout,
		self.draw.descriptor.layout,
		self.draw.descriptor.pool,
		self.draw.image,
	)
}

MAX_DESCRIPTOR_POOLS :: #config(MAX_DESCRIPTOR_POOLS, 32)
MAX_DESCRIPTOR_POOL_SIZES :: #config(MAX_DESCRIPTOR_SETS_BOUND, 16)
MAX_DESCRIPTOR_SETS_BOUND :: #config(MAX_DESCRIPTOR_SETS_BOUND, 16)

DescriptorBindings :: sa.Small_Array(MAX_DESCRIPTOR_SETS_BOUND, vk.DescriptorSetLayoutBinding)

DescriptorPoolState :: enum {
	READY,
	FULL,
}

DescriptorPools :: sa.Small_Array(MAX_DESCRIPTOR_POOLS, DescriptorPool)
DescriptorPool :: struct {
	handle: vk.DescriptorPool,
	state:  DescriptorPoolState,
}

DescriptorPoolSizeRatios :: sa.Small_Array(MAX_DESCRIPTOR_POOL_SIZES, DescriptorPoolSizeRatio)
DescriptorPoolSizeRatio :: struct {
	type:  vk.DescriptorType,
	value: f32,
}

DescriptorAllocator :: struct {
	pools:    DescriptorPools,
	ratios:   DescriptorPoolSizeRatios,
	max_sets: u32,
	device:   vk.Device,
}

descriptor_allocator_setup :: proc(
	self: ^DescriptorAllocator,
	ratios: []DescriptorPoolSizeRatio,
	max_sets: u32,
	device: vk.Device,
) {

	sa.clear(&self.pools)
	sa.clear(&self.ratios)

	for &ratio in ratios {
		sa.append(&self.ratios, ratio)
	}

	self.max_sets = max_sets
	self.device = device

	pool := descriptor_allocator_get_pool(self)
}

descriptor_allocator_cleanup :: proc(self: ^DescriptorAllocator) {

	for &pool in sa.slice(&self.pools) {
		vk.DestroyDescriptorPool(self.device, pool.handle, nil)
	}
}

descriptor_allocator_new_pool :: proc(self: ^DescriptorAllocator) -> ^DescriptorPool {

	pool_sizes: [MAX_DESCRIPTOR_POOL_SIZES]vk.DescriptorPoolSize
	for index in 0 ..< sa.len(self.ratios) {
		ratio := sa.get_ptr(&self.ratios, index)
		pool_sizes[index] = vk.DescriptorPoolSize {
			type            = ratio.type,
			descriptorCount = u32(ratio.value) * self.max_sets,
		}
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = self.max_sets,
		poolSizeCount = u32(sa.len(self.ratios)),
		pPoolSizes    = &pool_sizes[0],
	}

	pool: DescriptorPool
	pool.state = .READY
	vk_ok(vk.CreateDescriptorPool(self.device, &pool_info, nil, &pool.handle))

	sa.append(&self.pools, pool)
	return sa.get_ptr(&self.pools, sa.len(self.pools) - 1)
}

descriptor_allocator_get_pool :: proc(self: ^DescriptorAllocator) -> (pool: ^DescriptorPool) {

	for index in 0 ..< sa.len(self.pools) {
		pool = sa.get_ptr(&self.pools, index)
		if pool.state == .READY {
			return pool
		}
	}

	pool = descriptor_allocator_new_pool(self)

	self.max_sets = u32(f32(self.max_sets) * 1.5) // grow size by 50% each time
	if self.max_sets > 4092 { 	// 4096 is max descriptor sets per pool supported by most vk implementations
		self.max_sets = 4092 // 4092 for alignment/padding safety
	}

	return pool
}

descriptor_allocator_clear_pools :: proc(self: ^DescriptorAllocator) {

	for &pool in sa.slice(&self.pools) {
		pool.state = .READY
		vk_ok(vk.ResetDescriptorPool(self.device, pool.handle, {}))
	}
}

descriptor_set_new_layout :: proc(
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
	log.assert(sa.len(bindings^) < MAX_DESCRIPTOR_SETS_BOUND, loc = loc)

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

descriptor_allocator_new_set :: proc(
	self: ^DescriptorAllocator,
	layout: ^vk.DescriptorSetLayout,
) -> (
	set: vk.DescriptorSet,
) {
	pool := descriptor_allocator_get_pool(self)

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = pool.handle,
		descriptorSetCount = 1,
		pSetLayouts        = layout,
	}

	result := vk.AllocateDescriptorSets(self.device, &alloc_info, &set)

	if result == .ERROR_OUT_OF_POOL_MEMORY || result == .ERROR_FRAGMENTED_POOL {
		pool.state = .FULL

		// try once more
		pool = descriptor_allocator_get_pool(self)
		alloc_info.descriptorPool = pool.handle
		vk_ok(vk.AllocateDescriptorSets(self.device, &alloc_info, &set))
	}

	sa.append(&self.pools, pool^)
	return set
}

MAX_DESCRIPTOR_IMAGE_INFOS :: #config(MAX_DESCRIPTOR_IMAGE_INFOS, 64)
MAX_DESCRIPTOR_BUFFER_INFOS :: #config(MAX_DESCRIPTOR_BUFFER_INFOS, 64)
MAX_DESCRIPTOR_SET_WRITES :: #config(MAX_DESCRIPTOR_SET_WRITES, 128)

DescriptorImageInfos :: sa.Small_Array(MAX_DESCRIPTOR_IMAGE_INFOS, vk.DescriptorImageInfo)
DescriptorBufferInfos :: sa.Small_Array(MAX_DESCRIPTOR_BUFFER_INFOS, vk.DescriptorBufferInfo)
DescriptorSetWrites :: sa.Small_Array(MAX_DESCRIPTOR_SET_WRITES, vk.WriteDescriptorSet)

DescriptorWriter :: struct {
	image_infos:  DescriptorImageInfos,
	buffer_infos: DescriptorBufferInfos,
	writes:       DescriptorSetWrites,
	device:       vk.Device,
}

descriptor_writer_setup :: proc(self: ^DescriptorWriter, device: vk.Device) {

	self.device = device
}

descriptor_writer_write_buffer :: proc(
	self: ^DescriptorWriter,
	binding: int,
	buffer: vk.Buffer,
	size: vk.DeviceSize,
	offset: vk.DeviceSize,
	type: vk.DescriptorType,
	loc := #caller_location,
) {

	log.assert(sa.space(self.buffer_infos) != 0, "no space left in buffer_infos array", loc)
	log.assert(sa.space(self.writes) != 0, "no space left in writes array", loc)

	sa.append(&self.buffer_infos, vk.DescriptorBufferInfo{buffer = buffer, offset = offset, range = size})

	info_ptr := sa.get_ptr(&self.buffer_infos, sa.len(self.buffer_infos) - 1)

	sa.append(
		&self.writes,
		vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstBinding      = u32(binding),
			dstSet          = 0, // Left empty for now until we need to write it
			descriptorCount = 1,
			descriptorType  = type,
			pBufferInfo     = info_ptr,
		},
	)
}

descriptor_writer_write_image :: proc(
	self: ^DescriptorWriter,
	binding: int,
	image: vk.ImageView,
	sampler: vk.Sampler,
	layout: vk.ImageLayout,
	type: vk.DescriptorType,
	loc := #caller_location,
) {

	log.assert(sa.space(self.image_infos) != 0, "no space left in image_infos array", loc)
	log.assert(sa.space(self.writes) != 0, "no space left in writes array", loc)

	sa.append(&self.image_infos, vk.DescriptorImageInfo{sampler = sampler, imageView = image, imageLayout = layout})

	info_ptr := sa.get_ptr(&self.image_infos, sa.len(self.image_infos) - 1)

	sa.append(
		&self.writes,
		vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstBinding      = u32(binding),
			dstSet          = 0, // Left empty for now until we need to write it
			descriptorCount = 1,
			descriptorType  = type,
			pImageInfo      = info_ptr,
		},
	)
}

descriptor_writer_clear_writes :: proc(self: ^DescriptorWriter) {

	sa.clear(&self.image_infos)
	sa.clear(&self.buffer_infos)
	sa.clear(&self.writes)
}

descriptor_writer_update_set :: proc(self: ^DescriptorWriter, set: vk.DescriptorSet, loc := #caller_location) {

	log.assert(self.device != nil, "invalid 'Device'", loc)

	for &write in sa.slice(&self.writes) {
		write.dstSet = set
	}

	if sa.len(self.writes) > 0 {
		vk.UpdateDescriptorSets(self.device, u32(sa.len(self.writes)), raw_data(sa.slice(&self.writes)), 0, nil)
	}
}
