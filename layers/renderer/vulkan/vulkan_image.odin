package vulkan_backend

import "base:intrinsics"
import "bedbug:vendor/vma"
import "core:log"
import "core:math"
import vk "vendor:vulkan"


AllocatedImage :: struct {
	handle:     vk.Image,
	view:       vk.ImageView,
	extent:     vk.Extent3D,
	format:     vk.Format,
	allocator:  vma.Allocator,
	allocation: vma.Allocation,
}

allocated_image_create :: proc {
	allocated_image_create_default,
	allocated_image_create_from_data,
}

allocated_image_create_default :: proc(
	self: ^Vulkan,
	extent: vk.Extent3D,
	format: vk.Format,
	usage: vk.ImageUsageFlags,
	mip_mapped := false,
) -> (
	image: AllocatedImage,
) {

	mip_levels := 1 if mip_mapped else u32(math.floor(math.log2(max(f32(extent.width), f32(extent.height))))) + 1

	image_info := vk.ImageCreateInfo {
		sType       = .IMAGE_CREATE_INFO,
		imageType   = .D2,
		format      = format,
		extent      = extent,
		mipLevels   = mip_levels,
		arrayLayers = 1,
		samples     = {._1},
		tiling      = .OPTIMAL,
		usage       = usage,
	}

	alloc_info := vma.Allocation_Create_Info {
		usage          = .Gpu_Only,
		required_flags = {.DEVICE_LOCAL},
	}

	vk_ok(vma.create_image(self.device.vma_allocator, image_info, alloc_info, &image.handle, &image.allocation, nil))

	image.format = image_info.format
	image.extent = image_info.extent
	image.allocator = self.device.vma_allocator

	aspect_flags: vk.ImageAspectFlags = {.COLOR} if format != .D32_SFLOAT else {.DEPTH}

	view_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		viewType = .D2,
		format = image_info.format,
		subresourceRange = {levelCount = 1, layerCount = 1, aspectMask = aspect_flags},
		image = image.handle,
	}

	vk_ok(vk.CreateImageView(self.device.handle, &view_info, nil, &image.view))

	return image
}

allocated_image_create_from_data :: proc(
	self: ^Vulkan,
	data: rawptr,
	extent: vk.Extent3D,
	format: vk.Format,
	usage: vk.ImageUsageFlags,
	mip_mapped := false,
) -> (
	image: AllocatedImage,
) {

	data_size := vk.DeviceSize(extent.width * extent.height * extent.depth * 4)

	staging_buffer := allocated_buffer_create(self, data_size, {.TRANSFER_SRC}, .Cpu_To_Gpu)
	defer allocated_buffer_cleanup(staging_buffer)

	intrinsics.mem_copy(staging_buffer.alloc_info.mapped_data, data, data_size)

	usage := usage
	usage += {.TRANSFER_DST, .TRANSFER_SRC}
	image = allocated_image_create_default(self, extent, format, usage, mip_mapped)

	RecordInfo :: struct {
		image_handle:  vk.Image,
		extent:        vk.Extent3D,
		buffer_handle: vk.Buffer,
	}

	record_info := RecordInfo {
		extent        = image.extent,
		image_handle  = image.handle,
		buffer_handle = staging_buffer.handle,
	}

	device_immediate_command(
		&self.device,
		record_info,
		proc(device: ^Device, command: vk.CommandBuffer, info: RecordInfo) {

			image_transition(command, info.image_handle, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

			copy_region := vk.BufferImageCopy {
				imageSubresource = {aspectMask = {.COLOR}, layerCount = 1},
				imageExtent = info.extent,
			}

			vk.CmdCopyBufferToImage(
				command,
				info.buffer_handle,
				info.image_handle,
				.TRANSFER_DST_OPTIMAL,
				1,
				&copy_region,
			)

			image_transition(command, info.image_handle, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
		},
	)

	return image
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
