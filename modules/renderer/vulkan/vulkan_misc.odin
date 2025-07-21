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

device_image_allocate :: proc(
	device: VulkanDevice,
	format: vk.Format,
	usage: vk.ImageUsageFlags,
	extent: vk.Extent3D,
	samples := vk.SampleCountFlags{._1},
	mip_levels := u32(1),
) -> (
	device_image: GraphicsDeviceImage,
) {

	image_info := vk.ImageCreateInfo {
		sType         = .IMAGE_CREATE_INFO,
		imageType     = .D2,
		format        = format,
		extent        = extent,
		mipLevels     = mip_levels,
		arrayLayers   = 1,
		samples       = samples,
		tiling        = .OPTIMAL,
		usage         = usage,
		sharingMode   = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}

	vk.CreateImage(device.handle, &image_info, nil, &device_image.image)

	memory_requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(device.handle, device_image.image, &memory_requirements)

	memory_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(device.physical, &memory_properties)

	memory_type_index: u32
	for index in 0 ..< memory_properties.memoryTypeCount {
		property_flag := memory_properties.memoryTypes[index].propertyFlags
		if (memory_requirements.memoryTypeBits & 1) == 1 {
			if ((property_flag & {.DEVICE_LOCAL}) == {.DEVICE_LOCAL}) {
				memory_type_index = index
			}
			if ((property_flag & {.LAZILY_ALLOCATED}) == {.LAZILY_ALLOCATED}) {
				memory_type_index = index
				break
			}
		}

		memory_requirements.memoryTypeBits >>= 1
	}

	memory_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = memory_requirements.size,
		memoryTypeIndex = memory_type_index,
	}

	vk_ok(vk.AllocateMemory(device.handle, &memory_info, nil, &device_image.memory))

	vk_ok(vk.BindImageMemory(device.handle, device_image.image, device_image.memory, 0))

	aspect := vk.ImageAspectFlags{.COLOR}
	#partial switch format {
	case .D32_SFLOAT_S8_UINT, .D32_SFLOAT, .D24_UNORM_S8_UINT, .D16_UNORM_S8_UINT, .D16_UNORM:
		aspect = {.DEPTH}
	}

	if format >= .D16_UNORM_S8_UINT {
		aspect |= {.STENCIL}
	}

	view_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = device_image.image,
		viewType = .D2,
		format = format,
		subresourceRange = {aspectMask = aspect, levelCount = mip_levels, layerCount = 1},
	}

	vk_ok(vk.CreateImageView(device.handle, &view_info, nil, &device_image.view))

	device_image.format = format

	return device_image
}

vk_ok :: #force_inline proc(result: vk.Result, loc := #caller_location) {

	if intrinsics.expect(result, vk.Result.SUCCESS) == .SUCCESS {return}
	log.errorf("failed vulkan proc: %v", result)
	runtime.print_caller_location(loc)
}
