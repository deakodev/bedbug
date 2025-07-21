package vulkan_backend

import vk "vendor:vulkan"

INSTANCE_FLAG :: vk.InstanceCreateFlags{}

INSTANCE_EXTENSIONS :: []cstring{vk.KHR_SURFACE_EXTENSION_NAME}

DEVICE_EXTENSIONS :: []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
