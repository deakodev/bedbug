package vulkan_backend

import "base:intrinsics"
import "base:runtime"
import "bedbug:vendor/vma"
import "core:log"
import "core:strings"
import vk "vendor:vulkan"

AllocatedBuffer :: struct {
	handle:     vk.Buffer,
	alloc_info: vma.Allocation_Info,
	allocation: vma.Allocation,
	allocator:  vma.Allocator,
}

allocated_buffer_create :: proc(
	self: ^Vulkan,
	alloc_size: vk.DeviceSize,
	buffer_usage: vk.BufferUsageFlags,
	memory_usage: vma.Memory_Usage,
) -> (
	buffer: AllocatedBuffer,
) {

	buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size  = alloc_size,
		usage = buffer_usage,
	}

	vma_alloc_info := vma.Allocation_Create_Info {
		usage = memory_usage,
		flags = {.Mapped},
	}

	buffer.allocator = self.device.vma_allocator

	vk_ok(
		vma.create_buffer(
			buffer.allocator,
			buffer_info,
			vma_alloc_info,
			&buffer.handle,
			&buffer.allocation,
			&buffer.alloc_info,
		),
	)

	return buffer
}

allocated_buffer_cleanup :: proc(self: AllocatedBuffer) {

	vma.destroy_buffer(self.allocator, self.handle, self.allocation)
}

AllocatedImage :: struct {
	handle:     vk.Image,
	view:       vk.ImageView,
	extent:     vk.Extent3D,
	format:     vk.Format,
	allocator:  vma.Allocator,
	allocation: vma.Allocation,
}

allocated_image_cleanup :: proc(device: vk.Device, self: AllocatedImage) {

	vk.DestroyImageView(device, self.view, nil)
	vma.destroy_image(self.allocator, self.handle, self.allocation)
}

image_copy :: proc(
	command: vk.CommandBuffer,
	src_image: vk.Image,
	dest_image: vk.Image,
	src_size: vk.Extent2D,
	dst_size: vk.Extent2D,
) {

	blit_region := vk.ImageBlit2 {
		sType = .IMAGE_BLIT_2,
		pNext = nil,
		srcOffsets = [2]vk.Offset3D{{0, 0, 0}, {x = i32(src_size.width), y = i32(src_size.height), z = 1}},
		dstOffsets = [2]vk.Offset3D{{0, 0, 0}, {x = i32(dst_size.width), y = i32(dst_size.height), z = 1}},
		srcSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
		dstSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
	}

	blit_info := vk.BlitImageInfo2 {
		sType          = .BLIT_IMAGE_INFO_2,
		srcImage       = src_image,
		srcImageLayout = .TRANSFER_SRC_OPTIMAL,
		dstImage       = dest_image,
		dstImageLayout = .TRANSFER_DST_OPTIMAL,
		filter         = .LINEAR,
		regionCount    = 1,
		pRegions       = &blit_region,
	}

	vk.CmdBlitImage2(command, &blit_info)
}

image_transition :: proc(
	command: vk.CommandBuffer,
	image: vk.Image,
	old_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
) {

	barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		image = image,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcStageMask = {.ALL_COMMANDS},
		srcAccessMask = {.MEMORY_WRITE},
		dstStageMask = {.ALL_COMMANDS},
		dstAccessMask = {.MEMORY_WRITE, .MEMORY_READ},
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = (new_layout == .DEPTH_ATTACHMENT_OPTIMAL) ? {.DEPTH} : {.COLOR},
			levelCount = vk.REMAINING_MIP_LEVELS,
			layerCount = vk.REMAINING_ARRAY_LAYERS,
		},
	}

	dependency_info := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &barrier,
	}

	vk.CmdPipelineBarrier2(command, &dependency_info)
}

device_memory_type_index :: proc(
	physical_device: vk.PhysicalDevice,
	type_bits: u32,
	properties: vk.MemoryPropertyFlags,
) -> u32 {
	memory_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &memory_properties)

	for index in 0 ..< memory_properties.memoryTypeCount {
		has_bit := (type_bits & (1 << index)) != 0
		if has_bit && (memory_properties.memoryTypes[index].propertyFlags & properties == properties) {
			return index
		}
	}

	log.panic("failed to determine memory type.")
}

vk_ok :: #force_inline proc(result: vk.Result, loc := #caller_location) {

	if intrinsics.expect(result, vk.Result.SUCCESS) == .SUCCESS {return}
	log.errorf("failed vulkan proc: %v", result)
	runtime.print_caller_location(loc)
}
