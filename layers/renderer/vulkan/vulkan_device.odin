package vulkan_backend

import bb "bedbug:core"
import "bedbug:vendor/vma"
import "core:log"
import vk "vendor:vulkan"

Device :: struct {
	handle:         vk.Device,
	physical:       vk.PhysicalDevice,
	vma_allocator:  vma.Allocator,
	cleanup_stack:  ResourceStack,
	graphics_queue: struct {
		handle: vk.Queue,
		index:  u32,
	},
	immediate:      struct {
		pool:    vk.CommandPool,
		command: vk.CommandBuffer,
		fence:   vk.Fence,
	},
}

device_setup :: proc(backend: ^Vulkan) -> (ok: bool) {

	device := &backend.device
	device.physical = physical_device_select(backend.instance.handle)

	features_11 := vk.PhysicalDeviceVulkan11Features {
		sType                = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		shaderDrawParameters = true,
	}

	features_12 := vk.PhysicalDeviceVulkan12Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		pNext = &features_11,
	}

	features_13 := vk.PhysicalDeviceVulkan13Features {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
		synchronization2 = true,
		pNext            = &features_12,
	}

	device.graphics_queue.index = queue_family_index(device.physical, backend.instance.surface, .GRAPHICS)

	queue_priority: f32 = 1.0
	graphics_queue_info := vk.DeviceQueueCreateInfo {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueCount       = 1,
		pQueuePriorities = &queue_priority,
		queueFamilyIndex = device.graphics_queue.index,
	}

	device_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = 1,
		pQueueCreateInfos       = &graphics_queue_info,
		enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
		ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
		pEnabledFeatures        = nil,
		pNext                   = &features_13,
	}

	vk_ok(vk.CreateDevice(device.physical, &device_info, nil, &device.handle)) or_return

	resource_stack_setup(&device.cleanup_stack, device.handle)

	vk.GetDeviceQueue(device.handle, device.graphics_queue.index, 0, &device.graphics_queue.handle)

	vma_vulkan_functions := vma.create_vulkan_functions()
	allocator_create_info: vma.Allocator_Create_Info = {
		instance         = backend.instance.handle,
		physical_device  = device.physical,
		device           = device.handle,
		vulkan_functions = &vma_vulkan_functions,
	}
	vk_ok(vma.create_allocator(allocator_create_info, &device.vma_allocator)) or_return

	command_pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = device.graphics_queue.index,
		flags            = {.RESET_COMMAND_BUFFER},
	}
	vk_ok(vk.CreateCommandPool(device.handle, &command_pool_info, nil, &device.immediate.pool)) or_return

	command_alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = device.immediate.pool,
		commandBufferCount = 1,
		level              = .PRIMARY,
	}
	vk_ok(vk.AllocateCommandBuffers(device.handle, &command_alloc_info, &device.immediate.command)) or_return

	fence_create_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	vk_ok(vk.CreateFence(device.handle, &fence_create_info, nil, &device.immediate.fence)) or_return

	resource_stack_push(&device.cleanup_stack, device.vma_allocator, device.immediate.pool, device.immediate.fence)

	return true
}

device_cleanup :: proc(backend: ^Vulkan) {

	device := &backend.device
	resource_stack_cleanup(&device.cleanup_stack)
	if device.handle != nil {
		vk.DestroyDevice(device.handle, nil)
	}
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

	if flag == .COMPUTE {
		for family, index in families {
			if flag in family.queueFlags && .GRAPHICS not_in family.queueFlags && .TRANSFER not_in family.queueFlags {
				return u32(index)
			}
		}
	}

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

	// other non-dedicated queues for fallback
	for family, index in families {
		if flag in family.queueFlags {
			return u32(index)
		}
	}

	log.panic("failed to find matching queue family index for queue flag.")
}
