package vulkan_backend

import "bedbug:vendor/vma"
import sa "core:container/small_array"
import vk "vendor:vulkan"

Descriptor :: struct {
	set:    vk.DescriptorSet,
	layout: vk.DescriptorSetLayout,
}

AllocatedImage :: struct {
	handle:     vk.Image,
	view:       vk.ImageView,
	extent:     vk.Extent3D,
	format:     vk.Format,
	allocator:  vma.Allocator,
	allocation: vma.Allocation,
	descriptor: Descriptor,
}

Frame :: struct {
	fence:             vk.Fence,
	submit_semaphore:  vk.Semaphore,
	present_semaphore: vk.Semaphore,
	command_pool:      vk.CommandPool,
	command_buffer:    vk.CommandBuffer,
	draw_image:        AllocatedImage,
	ephemeral_stack:   ResourceStack,
}

g_descriptor_pool: vk.DescriptorPool
g_descriptor_set_layout: vk.DescriptorSetLayout

vulkan_frame_setup :: proc(self: ^Vulkan) {

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
	}

	draw_image_descriptor_bindings: DescriptorBindings
	sa.push_back_elems(
		&draw_image_descriptor_bindings,
		vk.DescriptorSetLayoutBinding{binding = 0, descriptorCount = 1, descriptorType = .STORAGE_IMAGE},
	)
	draw_image_descriptor_layout := descriptor_layout_make(
		self.device.handle,
		&draw_image_descriptor_bindings,
		{.COMPUTE},
	)
	resource_stack_push(&self.device.cleanup_stack, draw_image_descriptor_layout)

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

		{ 	// draw image
			frame.draw_image = AllocatedImage {
				format    = image_info.format,
				extent    = image_info.extent,
				allocator = self.device.vma_allocator,
			}

			vk_ok(
				vma.create_image(
					self.device.vma_allocator,
					image_info,
					image_alloc_info,
					&frame.draw_image.handle,
					&frame.draw_image.allocation,
					nil,
				),
			)

			image_view_info.image = frame.draw_image.handle

			vk_ok(vk.CreateImageView(self.device.handle, &image_view_info, nil, &frame.draw_image.view))
		}

		{ 	// descriptors
			frame.draw_image.descriptor.layout = draw_image_descriptor_layout
			frame.draw_image.descriptor.set = descriptor_set_allocate(
				self.device.handle,
				self.descriptor_pool,
				&frame.draw_image.descriptor.layout,
			)

			draw_image_descriptor_info := vk.DescriptorImageInfo {
				imageLayout = .GENERAL,
				imageView   = frame.draw_image.view,
			}

			draw_image_descriptor_write := vk.WriteDescriptorSet {
				sType           = .WRITE_DESCRIPTOR_SET,
				dstBinding      = 0,
				dstSet          = frame.draw_image.descriptor.set,
				descriptorCount = 1,
				descriptorType  = .STORAGE_IMAGE,
				pImageInfo      = &draw_image_descriptor_info,
			}

			vk.UpdateDescriptorSets(self.device.handle, 1, &draw_image_descriptor_write, 0, nil)
		}

		resource_stack_push(
			&self.device.cleanup_stack, // for permanent resources
			frame.fence,
			frame.submit_semaphore,
			frame.present_semaphore,
			frame.command_pool,
			frame.draw_image,
		)

		resource_stack_setup(
			&frame.ephemeral_stack, // for ephemeral resources
			self.device.handle,
		)
	}
}

vulkan_frame_cleanup :: proc(self: ^Vulkan) {

	for &frame in self.frames {
		resource_stack_cleanup(&frame.ephemeral_stack)
	}

	delete(self.frames)
}

allocated_image_cleanup :: proc(device: vk.Device, self: AllocatedImage) {

	vk.DestroyImageView(device, self.view, nil)
	vma.destroy_image(self.allocator, self.handle, self.allocation)
}
