package vulkan_backend

import vk "vendor:vulkan"

UniformBuffer :: struct {
	using DeviceBuffer: DeviceBuffer,
	mapped:             rawptr,
	descriptor_set:     vk.DescriptorSet,
}

VulkanFrame :: struct {
	command_buffer:             vk.CommandBuffer,
	uniform_buffer:             UniformBuffer,
	wait_fence:                 vk.Fence,
	submit_complete_semaphore:  vk.Semaphore,
	present_complete_semaphore: vk.Semaphore,
}

g_descriptor_pool: vk.DescriptorPool
g_descriptor_set_layout: vk.DescriptorSetLayout

vulkan_frame_setup :: proc(device: VulkanDevice) -> (frames: [MAX_CONCURRENT_FRAMES]VulkanFrame) {

	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	semaphore_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	for i := 0; i < MAX_CONCURRENT_FRAMES; i += 1 {
		vk_ok(vk.CreateFence(device.handle, &fence_info, nil, &frames[i].wait_fence))
		vk_ok(vk.CreateSemaphore(device.handle, &semaphore_info, nil, &frames[i].submit_complete_semaphore))
		vk_ok(vk.CreateSemaphore(device.handle, &semaphore_info, nil, &frames[i].present_complete_semaphore))
	}

	command_buffers: [MAX_CONCURRENT_FRAMES]vk.CommandBuffer

	command_alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = device.command_pool,
		level              = .PRIMARY,
		commandBufferCount = u32(len(command_buffers)),
	}

	vk_ok(vk.AllocateCommandBuffers(device.handle, &command_alloc_info, &command_buffers[0]))

	for i := 0; i < MAX_CONCURRENT_FRAMES; i += 1 {
		frames[i].command_buffer = command_buffers[i]
	}

	uniform_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size  = size_of(ShaderData),
		usage = {.UNIFORM_BUFFER},
	}

	for i := 0; i < MAX_CONCURRENT_FRAMES; i += 1 {
		uniform_buffer := &frames[i].uniform_buffer
		vk_ok(vk.CreateBuffer(device.handle, &uniform_info, nil, &uniform_buffer.handle))

		memory_requirements: vk.MemoryRequirements
		vk.GetBufferMemoryRequirements(device.handle, uniform_buffer.handle, &memory_requirements)

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

		vk_ok(vk.AllocateMemory(device.handle, &alloc_info, nil, &uniform_buffer.memory))
		vk_ok(vk.BindBufferMemory(device.handle, uniform_buffer.handle, uniform_buffer.memory, 0))

		buffer_data: rawptr
		vk_ok(
			vk.MapMemory(
				device.handle,
				uniform_buffer.memory,
				0,
				alloc_info.allocationSize,
				{},
				&uniform_buffer.mapped,
			),
		)
	}

	descriptor_sizes := vk.DescriptorPoolSize {
		type            = .UNIFORM_BUFFER,
		descriptorCount = MAX_CONCURRENT_FRAMES,
	}
	descriptor_pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = 1,
		pPoolSizes    = &descriptor_sizes,
		maxSets       = MAX_CONCURRENT_FRAMES,
	}

	vk_ok(vk.CreateDescriptorPool(device.handle, &descriptor_pool_info, nil, &g_descriptor_pool))

	descriptor_layout_binding := vk.DescriptorSetLayoutBinding {
		descriptorType  = .UNIFORM_BUFFER,
		descriptorCount = 1,
		stageFlags      = {.VERTEX},
	}

	descriptor_layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &descriptor_layout_binding,
	}

	vk_ok(vk.CreateDescriptorSetLayout(device.handle, &descriptor_layout_info, nil, &g_descriptor_set_layout))

	for i := 0; i < MAX_CONCURRENT_FRAMES; i += 1 {
		uniform_buffer := &frames[i].uniform_buffer

		alloc_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool     = g_descriptor_pool,
			descriptorSetCount = 1,
			pSetLayouts        = &g_descriptor_set_layout,
		}

		vk_ok(vk.AllocateDescriptorSets(device.handle, &alloc_info, &uniform_buffer.descriptor_set))

		buffer_info := vk.DescriptorBufferInfo {
			buffer = uniform_buffer.handle,
			range  = size_of(ShaderData),
		}

		write := vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstSet          = uniform_buffer.descriptor_set,
			descriptorCount = 1,
			descriptorType  = .UNIFORM_BUFFER,
			pBufferInfo     = &buffer_info,
			dstBinding      = 0,
		}

		vk.UpdateDescriptorSets(device.handle, 1, &write, 0, nil)
	}

	return frames
}
