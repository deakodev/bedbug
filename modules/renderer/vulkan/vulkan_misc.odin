package vulkan_backend

import "base:intrinsics"
import "base:runtime"
import "core:log"
import "core:strings"
import vk "vendor:vulkan"

DeviceBuffer :: struct {
	handle: vk.Buffer,
	memory: vk.DeviceMemory,
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

// device_image_allocate :: proc(
// 	device: Device,
// 	format: vk.Format,
// 	usage: vk.ImageUsageFlags,
// 	extent: vk.Extent3D,
// 	samples := vk.SampleCountFlags{._1},
// 	mip_levels := u32(1),
// ) -> (
// 	device_image: GraphicsDeviceImage,
// ) {

// 	image_info := vk.ImageCreateInfo {
// 		sType         = .IMAGE_CREATE_INFO,
// 		imageType     = .D2,
// 		format        = format,
// 		extent        = extent,
// 		mipLevels     = mip_levels,
// 		arrayLayers   = 1,
// 		samples       = samples,
// 		tiling        = .OPTIMAL,
// 		usage         = usage,
// 		sharingMode   = .EXCLUSIVE,
// 		initialLayout = .UNDEFINED,
// 	}

// 	vk.CreateImage(device.handle, &image_info, nil, &device_image.image)

// 	memory_requirements: vk.MemoryRequirements
// 	vk.GetImageMemoryRequirements(device.handle, device_image.image, &memory_requirements)

// 	memory_properties: vk.PhysicalDeviceMemoryProperties
// 	vk.GetPhysicalDeviceMemoryProperties(device.physical, &memory_properties)

// 	memory_type_index: u32
// 	for index in 0 ..< memory_properties.memoryTypeCount {
// 		property_flag := memory_properties.memoryTypes[index].propertyFlags
// 		if (memory_requirements.memoryTypeBits & 1) == 1 {
// 			if ((property_flag & {.DEVICE_LOCAL}) == {.DEVICE_LOCAL}) {
// 				memory_type_index = index
// 			}
// 			if ((property_flag & {.LAZILY_ALLOCATED}) == {.LAZILY_ALLOCATED}) {
// 				memory_type_index = index
// 				break
// 			}
// 		}

// 		memory_requirements.memoryTypeBits >>= 1
// 	}

// 	memory_info := vk.MemoryAllocateInfo {
// 		sType           = .MEMORY_ALLOCATE_INFO,
// 		allocationSize  = memory_requirements.size,
// 		memoryTypeIndex = memory_type_index,
// 	}

// 	vk_ok(vk.AllocateMemory(device.handle, &memory_info, nil, &device_image.memory))

// 	vk_ok(vk.BindImageMemory(device.handle, device_image.image, device_image.memory, 0))

// 	aspect := vk.ImageAspectFlags{.COLOR}
// 	#partial switch format {
// 	case .D32_SFLOAT_S8_UINT, .D32_SFLOAT, .D24_UNORM_S8_UINT, .D16_UNORM_S8_UINT, .D16_UNORM:
// 		aspect = {.DEPTH}
// 	}

// 	if format >= .D16_UNORM_S8_UINT {
// 		aspect |= {.STENCIL}
// 	}

// 	view_info := vk.ImageViewCreateInfo {
// 		sType = .IMAGE_VIEW_CREATE_INFO,
// 		image = device_image.image,
// 		viewType = .D2,
// 		format = format,
// 		subresourceRange = {aspectMask = aspect, levelCount = mip_levels, layerCount = 1},
// 	}

// 	vk_ok(vk.CreateImageView(device.handle, &view_info, nil, &device_image.view))

// 	device_image.format = format

// 	return device_image
// }

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

vk_ok :: #force_inline proc(result: vk.Result, loc := #caller_location) {

	if intrinsics.expect(result, vk.Result.SUCCESS) == .SUCCESS {return}
	log.errorf("failed vulkan proc: %v", result)
	runtime.print_caller_location(loc)
}
