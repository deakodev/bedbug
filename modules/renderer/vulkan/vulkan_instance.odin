package vulkan_backend

import "base:runtime"
import bb "bedbug:core"
import "bedbug:vendor/vma"
import "core:log"
import "core:slice"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"

VALIDATION_ENABLED :: #config(VALIDATION_ENABLED, ODIN_DEBUG)
VALIDATION_LAYERS :: []cstring{"VK_LAYER_KHRONOS_validation", "VK_LAYER_LUNARG_monitor"} //"VK_LAYER_LUNARG_api_dump"

Instance :: struct {
	handle:    vk.Instance,
	messenger: vk.DebugUtilsMessengerEXT,
	surface:   vk.SurfaceKHR,
}

vulkan_instance_setup :: proc(self: ^Vulkan) {

	instance_layers := VALIDATION_LAYERS when VALIDATION_ENABLED else []cstring{}
	instance_extensions := slice.clone_to_dynamic(INSTANCE_EXTENSIONS, context.temp_allocator)
	messenger_info: vk.DebugUtilsMessengerCreateInfoEXT = {}

	when VALIDATION_ENABLED {
		append(&instance_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
		messenger_info = vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.ERROR, .WARNING},
			messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE, .DEVICE_ADDRESS_BINDING},
			pfnUserCallback = vulkan_message,
		}
	}

	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Bedbug",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "Bedbug Engine",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_3,
	}

	create_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		flags                   = INSTANCE_FLAG,
		pApplicationInfo        = &app_info,
		enabledLayerCount       = u32(len(instance_layers)),
		ppEnabledLayerNames     = raw_data(instance_layers),
		enabledExtensionCount   = u32(len(instance_extensions)),
		ppEnabledExtensionNames = raw_data(instance_extensions),
	}

	messenger_info.pNext = create_info.pNext
	create_info.pNext = &messenger_info

	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
	vk_ok(vk.CreateInstance(&create_info, nil, &self.instance.handle))
	vk.load_proc_addresses_instance(self.instance.handle)

	when VALIDATION_ENABLED {
		vk_ok(vk.CreateDebugUtilsMessengerEXT(self.instance.handle, &messenger_info, nil, &self.instance.messenger))
	}

	vk_ok(glfw.CreateWindowSurface(self.instance.handle, bb.core().window.handle, nil, &self.instance.surface))
}

vulkan_instance_cleanup :: proc(self: ^Vulkan) {

	vk.DestroySurfaceKHR(self.instance.handle, self.instance.surface, nil)
	when VALIDATION_ENABLED {
		vk.DestroyDebugUtilsMessengerEXT(self.instance.handle, self.instance.messenger, nil)
	}
	vk.DestroyInstance(self.instance.handle, nil)
}

vulkan_message :: proc "system" (
	message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	message_type: vk.DebugUtilsMessageTypeFlagsEXT,
	p_callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	_: rawptr,
) -> b32 {

	context = g_foreign_context

	level: log.Level
	switch {
	case .ERROR in message_severity:
		level = .Error
	case .WARNING in message_severity:
		level = .Warning
	case:
		level = .Info
	}

	message := strings.trim_space(string(p_callback_data.pMessage))
	log.logf(level, "[%v]:\n%s", message_type, message)

	if level == .Error {
		runtime.debug_trap()
	}

	return false
}
