package vulkan_backend

import bb "bedbug:core"
import "core:log"
import vk "vendor:vulkan"

VulkanDevice :: struct {
	handle:       vk.Device,
	physical:     vk.PhysicalDevice,
	queue:        struct {
		graphics: vk.Queue,
	},
	command_pool: vk.CommandPool,
}

vulkan_device_setup :: proc(instance: VulkanInstance) -> (device: VulkanDevice) {

	device.physical = physical_device_select(instance.handle)

	graphics_index := queue_family_index(device.physical, instance.surface, .GRAPHICS)

	queue_priority: f32 = 0.0
	graphics_queue_info := vk.DeviceQueueCreateInfo {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueCount       = 1,
		pQueuePriorities = &queue_priority,
		queueFamilyIndex = graphics_index,
	}

	instance_layers := VALIDATION_LAYERS when VALIDATION_ENABLED else []cstring{}

	vulkan13_features := vk.PhysicalDeviceVulkan13Features {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
		synchronization2 = true,
	}

	device_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = 1,
		pQueueCreateInfos       = &graphics_queue_info,
		enabledLayerCount       = u32(len(instance_layers)),
		ppEnabledLayerNames     = raw_data(instance_layers),
		enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
		ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
		pEnabledFeatures        = nil,
		pNext                   = &vulkan13_features,
	}

	vk_ok(vk.CreateDevice(device.physical, &device_info, nil, &device.handle))

	vk.GetDeviceQueue(device.handle, graphics_index, 0, &device.queue.graphics)

	command_pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = graphics_index,
	}

	vk_ok(vk.CreateCommandPool(device.handle, &command_pool_info, nil, &device.command_pool))

	return device
}

@(require_results)
physical_device_select :: proc(instance: vk.Instance) -> vk.PhysicalDevice {

	score :: proc(device: vk.PhysicalDevice) -> (score: int) {

		props: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(device, &props)

		name := bb.string_of_bytes(&props.deviceName)
		log.infof("evaluating %s...", name)
		defer log.infof("...final score of %v", score)

		features: vk.PhysicalDeviceFeatures
		vk.GetPhysicalDeviceFeatures(device, &features)


		{
			extensions, result := physical_device_extensions(device, context.temp_allocator)
			if result != .SUCCESS {
				log.infof("...failed to enumerate extension properties: %v", result)
				return 0
			}

			required_loop: for required in DEVICE_EXTENSIONS {
				for &extension in extensions {
					extension_name := bb.string_of_bytes(&extension.extensionName)
					if extension_name == string(required) {
						continue required_loop
					}
				}

				log.infof("...failed to support required extension %q", required)
				return 0
			}

			if props.apiVersion < vk.API_VERSION_1_3 {
				return 0
			}
		}

		switch props.deviceType {
		case .DISCRETE_GPU:
			score += 300_000
		case .INTEGRATED_GPU:
			score += 200_000
		case .VIRTUAL_GPU:
			score += 100_000
		case .CPU, .OTHER:
		}

		score += int(props.limits.maxImageDimension2D)

		return score
	}

	count: u32
	vk.EnumeratePhysicalDevices(instance, &count, nil)
	if count == 0 {
		log.panic("failed to find a physical device.")
	}

	devices := make([]vk.PhysicalDevice, count, context.temp_allocator)
	vk.EnumeratePhysicalDevices(instance, &count, raw_data(devices))

	best_score := 0
	best_device: Maybe(vk.PhysicalDevice)
	for device in devices {
		if score := score(device); score > best_score {
			best_score = score
			best_device = device
		}
	}

	return best_device.? or_else log.panic("failed to find suitable physical device.")
}

physical_device_extensions :: proc(
	device: vk.PhysicalDevice,
	allocator := context.temp_allocator,
) -> (
	extensions: []vk.ExtensionProperties,
	result: vk.Result,
) {
	count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil) or_return

	extensions = make([]vk.ExtensionProperties, count, allocator)
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(extensions)) or_return

	return
}

queue_family_index :: proc(
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	flag: vk.QueueFlag,
) -> (
	index: u32,
) {

	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &count, nil)

	families := make([]vk.QueueFamilyProperties, count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &count, raw_data(families))

	// attempt to find dedicated compute queue
	if flag == .COMPUTE {
		for family, index in families {
			if flag in family.queueFlags && .GRAPHICS not_in family.queueFlags && .TRANSFER not_in family.queueFlags {
				return u32(index)
			}
		}
	}

	// attempt to find dedicated compute queue
	if flag == .TRANSFER {
		for family, index in families {
			if flag in family.queueFlags && .GRAPHICS not_in family.queueFlags && .COMPUTE not_in family.queueFlags {
				return u32(index)
			}
		}
	}

	if flag == .GRAPHICS {
		for family, index in families {
			supports_present: b32
			if flag in family.queueFlags && supports_present {
				vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, u32(index), surface, &supports_present)
				if supports_present {
					return u32(index)}
			}
		}
	}

	// other non-dedicated queues
	for family, index in families {
		if flag in family.queueFlags {
			return u32(index)
		}
	}

	log.panic("failed to find matching queue family index for queue flag.")
}
