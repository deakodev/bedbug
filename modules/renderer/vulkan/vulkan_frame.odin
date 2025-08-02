package vulkan_backend

import "bedbug:vendor/vma"
import sa "core:container/small_array"
import "core:log"
import vk "vendor:vulkan"

Frame :: struct {
	fence:                vk.Fence,
	submit_semaphore:     vk.Semaphore,
	present_semaphore:    vk.Semaphore,
	command_pool:         vk.CommandPool,
	command_buffer:       vk.CommandBuffer,
	descriptor_allocator: DescriptorAllocator,
	ephemeral_stack:      ResourceStack,
	image_index:          u32,
}

frame_setup :: proc(self: ^Vulkan) {

	self.frames = make([]Frame, MAX_CONCURRENT_FRAMES, context.allocator)

	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	semaphore_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	command_pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = self.device.graphics_queue_index,
	}

	for &frame in self.frames {

		// permanent resources
		vk_ok(vk.CreateFence(self.device.handle, &fence_info, nil, &frame.fence))
		vk_ok(vk.CreateSemaphore(self.device.handle, &semaphore_info, nil, &frame.submit_semaphore))
		vk_ok(vk.CreateSemaphore(self.device.handle, &semaphore_info, nil, &frame.present_semaphore))
		vk_ok(vk.CreateCommandPool(self.device.handle, &command_pool_info, nil, &frame.command_pool))

		command_alloc_info := vk.CommandBufferAllocateInfo {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = frame.command_pool,
			level              = .PRIMARY,
			commandBufferCount = 1,
		}

		vk_ok(vk.AllocateCommandBuffers(self.device.handle, &command_alloc_info, &frame.command_buffer))

		{ 	// descriptors
			frame_sizes: DescriptorPoolSizeRatios
			sa.append(
				&frame_sizes,
				DescriptorPoolSizeRatio{.STORAGE_IMAGE, 3},
				DescriptorPoolSizeRatio{.STORAGE_BUFFER, 3},
				DescriptorPoolSizeRatio{.UNIFORM_BUFFER, 3},
				DescriptorPoolSizeRatio{.COMBINED_IMAGE_SAMPLER, 4},
			)

			descriptor_allocator_setup(&frame.descriptor_allocator, sa.slice(&frame_sizes), 1000, self.device.handle)
		}

		resource_stack_push(
			&self.device.cleanup_stack, // for per frame permanent resources
			frame.fence,
			frame.submit_semaphore,
			frame.present_semaphore,
			frame.command_pool,
			frame.descriptor_allocator,
		)

		resource_stack_setup(
			&frame.ephemeral_stack, // for per frame ephemeral resources
			self.device.handle,
		)
	}
}

frame_cleanup :: proc(self: ^Vulkan) {

	for &frame in self.frames {
		resource_stack_cleanup(&frame.ephemeral_stack)
	}

	delete(self.frames)
}
