package vulkan_backend

import bb "bedbug:core"
import im "bedbug:vendor/imgui"
import im_glfw "bedbug:vendor/imgui/imgui_impl_glfw"
import im_vk "bedbug:vendor/imgui/imgui_impl_vulkan"
import "core:log"
import "vendor:glfw"
import vk "vendor:vulkan"

imgui_setup :: proc(self: ^Vulkan) {

	im.CHECKVERSION()

	// 1: create descriptor pool for IMGUI
	// The size of the pool is very oversize, but it's copied from imgui demo itself.
	pool_sizes := []vk.DescriptorPoolSize {
		{.SAMPLER, 1000},
		{.COMBINED_IMAGE_SAMPLER, 1000},
		{.SAMPLED_IMAGE, 1000},
		{.STORAGE_IMAGE, 1000},
		{.UNIFORM_TEXEL_BUFFER, 1000},
		{.STORAGE_TEXEL_BUFFER, 1000},
		{.UNIFORM_BUFFER, 1000},
		{.STORAGE_BUFFER, 1000},
		{.UNIFORM_BUFFER_DYNAMIC, 1000},
		{.STORAGE_BUFFER_DYNAMIC, 1000},
		{.INPUT_ATTACHMENT, 1000},
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = {.FREE_DESCRIPTOR_SET},
		maxSets       = 1000,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes    = raw_data(pool_sizes),
	}

	imgui_pool: vk.DescriptorPool
	vk_ok(vk.CreateDescriptorPool(self.device.handle, &pool_info, nil, &imgui_pool))

	self.imgui = im.create_context()
	im_glfw.init_for_vulkan(bb.core().window.handle, true)

	init_info := im_vk.Init_Info {
		api_version = vk.API_VERSION_1_3,
		instance = self.instance.handle,
		physical_device = self.device.physical,
		device = self.device.handle,
		queue = self.device.graphics_queue,
		descriptor_pool = imgui_pool,
		min_image_count = 3,
		image_count = 3,
		use_dynamic_rendering = true,
		pipeline_rendering_create_info = {
			sType = .PIPELINE_RENDERING_CREATE_INFO,
			colorAttachmentCount = 1,
			pColorAttachmentFormats = &self.swapchain.format.format,
		},
		msaa_samples = ._1,
	}

	im_vk.load_functions(
		init_info.api_version,
		proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
			backend := cast(^Vulkan)user_data
			return vk.GetInstanceProcAddr(backend.instance.handle, function_name)
		},
		self,
	)

	im_vk.init(&init_info)

	scale, _ := glfw.GetWindowContentScale(bb.core().window.handle)
	im_io := im.get_io()
	im_io.font_global_scale = scale
	im_style := im.get_style()
	im.style_scale_all_sizes(im_style, scale)

	resource_stack_push(&self.device.cleanup_stack, imgui_pool, im_vk.shutdown, im_glfw.shutdown)
}
