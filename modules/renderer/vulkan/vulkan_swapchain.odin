package vulkan_backend

import bb "bedbug:core"
import "core:log"
import "vendor:glfw"
import vk "vendor:vulkan"

GraphicsDeviceImage :: struct {
	image:  vk.Image,
	view:   vk.ImageView,
	memory: vk.DeviceMemory,
	format: vk.Format,
}


GraphicsTarget :: struct {
	depth:        GraphicsDeviceImage,
	sample_count: vk.SampleCountFlags,
}


VulkanSwapchain :: struct {
	handle: vk.SwapchainKHR,
	images: []vk.Image,
	views:  []vk.ImageView,
	format: vk.SurfaceFormatKHR,
	extent: vk.Extent2D,
	target: GraphicsTarget,
}


vulkan_swapchain_setup :: proc(surface: vk.SurfaceKHR, device: VulkanDevice) -> (swapchain: VulkanSwapchain) {

	support, result := swapchain_support_query(device.physical, surface, context.temp_allocator)
	if result != .SUCCESS {
		log.panicf("failed to query swapchain support: %v", result)
	}

	swapchain.format = swapchain_surface_format_select(support.formats)
	swapchain.extent = swapchain_extent_select(support.capabilities)
	present_mode := swapchain_present_mode_select(support.presentModes)

	image_count := support.capabilities.minImageCount + 1
	if support.capabilities.maxImageCount > 0 && image_count > support.capabilities.maxImageCount {
		image_count = support.capabilities.maxImageCount
	}

	pre_transform: vk.SurfaceTransformFlagsKHR
	if .IDENTITY in support.capabilities.supportedTransforms {
		pre_transform = {.IDENTITY} // prefer a non-rotated transform
	} else {
		pre_transform = support.capabilities.currentTransform
	}

	create_info := vk.SwapchainCreateInfoKHR {
		sType                 = .SWAPCHAIN_CREATE_INFO_KHR,
		surface               = surface,
		minImageCount         = image_count,
		imageFormat           = swapchain.format.format,
		imageColorSpace       = swapchain.format.colorSpace,
		imageExtent           = swapchain.extent,
		imageArrayLayers      = 1,
		imageUsage            = {.COLOR_ATTACHMENT},
		preTransform          = pre_transform,
		compositeAlpha        = {.OPAQUE},
		queueFamilyIndexCount = 0,
		imageSharingMode      = .EXCLUSIVE,
		presentMode           = present_mode,
		clipped               = true,
	}

	vk_ok(vk.CreateSwapchainKHR(device.handle, &create_info, nil, &swapchain.handle))

	swapchain.images = make([]vk.Image, int(image_count))
	swapchain.views = make([]vk.ImageView, int(image_count))
	vk_ok(vk.GetSwapchainImagesKHR(device.handle, swapchain.handle, &image_count, raw_data(swapchain.images)))

	for image, index in swapchain.images {
		view_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = image,
			viewType = .D2,
			format = swapchain.format.format,
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}
		vk_ok(vk.CreateImageView(device.handle, &view_info, nil, &swapchain.views[index]))
	}

	swapchain.target.sample_count = {._1}

	image_extent := vk.Extent3D{swapchain.extent.width, swapchain.extent.height, 1}
	depth_format := depth_format(device.physical, true)
	depth_usage := vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT}

	swapchain.target.depth = device_image_allocate(device, depth_format, depth_usage, image_extent)

	return swapchain
}


Swapchain_Support :: struct {
	capabilities: vk.SurfaceCapabilitiesKHR,
	formats:      []vk.SurfaceFormatKHR,
	presentModes: []vk.PresentModeKHR,
}


swapchain_support_query :: proc(
	device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	allocator := context.temp_allocator,
) -> (
	support: Swapchain_Support,
	result: vk.Result,
) {
	// NOTE: looks like a wrong binding with the third arg being a multipointer.
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &support.capabilities) or_return


	{
		count: u32
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &count, nil) or_return

		support.formats = make([]vk.SurfaceFormatKHR, count, allocator)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &count, raw_data(support.formats)) or_return
	}


	{
		count: u32
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &count, nil) or_return

		support.presentModes = make([]vk.PresentModeKHR, count, allocator)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &count, raw_data(support.presentModes)) or_return
	}

	return
}


swapchain_surface_format_select :: proc(formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {

	for format in formats {
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			return format
		}
	}

	return formats[0] // fallback
}


swapchain_present_mode_select :: proc(modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {

	for mode in modes {
		if mode == .MAILBOX {
			return .MAILBOX
		}
	}

	return .FIFO // fallback
}


swapchain_extent_select :: proc(capabilities: vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {

	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	width, height := glfw.GetFramebufferSize(bb.core().window.handle)
	return (vk.Extent2D {
				width = clamp(u32(width), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
				height = clamp(u32(height), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
			})
}

depth_format :: proc(physical_device: vk.PhysicalDevice, check_sampling_support: bool) -> vk.Format {
	depth_formats := [5]vk.Format{.D32_SFLOAT_S8_UINT, .D32_SFLOAT, .D24_UNORM_S8_UINT, .D16_UNORM_S8_UINT, .D16_UNORM}
	for format in depth_formats {
		format_properties: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(physical_device, format, &format_properties)
		if (format_properties.optimalTilingFeatures & {.DEPTH_STENCIL_ATTACHMENT}) == {.DEPTH_STENCIL_ATTACHMENT} {
			if check_sampling_support {
				if (format_properties.optimalTilingFeatures & {.SAMPLED_IMAGE}) != {.SAMPLED_IMAGE} {
					continue
				}
			}
			return format
		}
	}

	log.panic("failed to find matching depth format.")
}
