package vulkan_backend

import bb "bedbug:core"
import im "bedbug:vendor/imgui"
import im_glfw "bedbug:vendor/imgui/imgui_impl_glfw"
import im_vk "bedbug:vendor/imgui/imgui_impl_vulkan"
import "core:log"
import "vendor:glfw"
import vk "vendor:vulkan"

imgui_setup :: proc(self: ^Vulkan) -> (ok: bool) {

	im.CHECKVERSION()

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
	vk_ok(vk.CreateDescriptorPool(self.device.handle, &pool_info, nil, &imgui_pool)) or_return

	self.imgui = im.create_context()
	im_glfw.init_for_vulkan(bb.core_get().window.handle, true) or_return

	init_info := im_vk.Init_Info {
		api_version = vk.API_VERSION_1_3,
		instance = self.instance.handle,
		physical_device = self.device.physical,
		device = self.device.handle,
		queue = self.device.graphics_queue.handle,
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

	scale, _ := glfw.GetWindowContentScale(bb.core_get().window.handle)
	im_io := im.get_io()
	im_io.font_global_scale = scale
	im_style := im.get_style()
	im.style_scale_all_sizes(im_style, scale)

	resource_stack_push(&self.device.cleanup_stack, imgui_pool, im_vk.shutdown, im_glfw.shutdown)

	imgui_style()

	return true
}


// odinfmt: disable
imgui_style :: proc() {

    style := im.get_style()
    colors := &style.colors

    // Base colors for a pleasant and modern dark theme with dark accents
    colors[im.Col.Text]                  = {0.92, 0.93, 0.94, 1.00}  // Light grey text for readability
    colors[im.Col.Text_Disabled]         = {0.50, 0.52, 0.54, 1.00}  // Subtle grey for disabled text
    colors[im.Col.Window_Bg]             = {0.14, 0.14, 0.16, 1.00}  // Dark background with a hint of blue
    colors[im.Col.Child_Bg]              = {0.16, 0.16, 0.18, 1.00}  // Slightly lighter for child elements
    colors[im.Col.Popup_Bg]              = {0.18, 0.18, 0.20, 1.00}  // Popup background
    colors[im.Col.Border]                = {0.28, 0.29, 0.30, 0.60}  // Soft border color
    colors[im.Col.Border_Shadow]         = {0.00, 0.00, 0.00, 0.00}  // No border shadow
    colors[im.Col.Frame_Bg]              = {0.20, 0.22, 0.24, 1.00}  // Frame background
    colors[im.Col.Frame_Bg_Hovered]      = {0.22, 0.24, 0.26, 1.00}  // Frame hover effect
    colors[im.Col.Frame_Bg_Active]       = {0.24, 0.26, 0.28, 1.00}  // Active frame background
    colors[im.Col.Title_Bg]              = {0.14, 0.14, 0.16, 1.00}  // Title background
    colors[im.Col.Title_Bg_Active]       = {0.16, 0.16, 0.18, 1.00}  // Active title background
    colors[im.Col.Title_Bg_Collapsed]    = {0.14, 0.14, 0.16, 1.00}  // Collapsed title background
    colors[im.Col.Menu_Bar_Bg]           = {0.20, 0.20, 0.22, 1.00}  // Menu bar background
    colors[im.Col.Scrollbar_Bg]          = {0.16, 0.16, 0.18, 1.00}  // Scrollbar background
    colors[im.Col.Scrollbar_Grab]        = {0.24, 0.26, 0.28, 1.00}  // Dark accent for scrollbar grab
    colors[im.Col.Scrollbar_Grab_Hovered]= {0.28, 0.30, 0.32, 1.00}  // Scrollbar grab hover
    colors[im.Col.Scrollbar_Grab_Active] = {0.32, 0.34, 0.36, 1.00}  // Scrollbar grab active
    colors[im.Col.Check_Mark]            = {0.46, 0.56, 0.66, 1.00}  // Dark blue checkmark
    colors[im.Col.Slider_Grab]           = {0.36, 0.46, 0.56, 1.00}  // Dark blue slider grab
    colors[im.Col.Slider_Grab_Active]    = {0.40, 0.50, 0.60, 1.00}  // Active slider grab
    colors[im.Col.Button]                = {0.24, 0.34, 0.44, 1.00}  // Dark blue button
    colors[im.Col.Button_Hovered]        = {0.28, 0.38, 0.48, 1.00}  // Button hover effect
    colors[im.Col.Button_Active]         = {0.32, 0.42, 0.52, 1.00}  // Active button
    colors[im.Col.Header]                = {0.24, 0.34, 0.44, 1.00}  // Header color similar to button
    colors[im.Col.Header_Hovered]        = {0.28, 0.38, 0.48, 1.00}  // Header hover effect
    colors[im.Col.Header_Active]         = {0.32, 0.42, 0.52, 1.00}  // Active header
    colors[im.Col.Separator]             = {0.28, 0.29, 0.30, 1.00}  // Separator color
    colors[im.Col.Separator_Hovered]     = {0.46, 0.56, 0.66, 1.00}  // Hover effect for separator
    colors[im.Col.Separator_Active]      = {0.46, 0.56, 0.66, 1.00}  // Active separator
    colors[im.Col.Resize_Grip]           = {0.36, 0.46, 0.56, 1.00}  // Resize grip
    colors[im.Col.Resize_Grip_Hovered]   = {0.40, 0.50, 0.60, 1.00}  // Hover effect for resize grip
    colors[im.Col.Resize_Grip_Active]    = {0.44, 0.54, 0.64, 1.00}  // Active resize grip
    colors[im.Col.Tab]                   = {0.20, 0.22, 0.24, 1.00}  // Inactive tab
    colors[im.Col.Tab_Hovered]           = {0.28, 0.38, 0.48, 1.00}  // Hover effect for tab
    colors[im.Col.Tab_Selected]          = {0.24, 0.34, 0.44, 1.00}  // Active tab color (TabActive)
    colors[im.Col.Tab_Dimmed]            = {0.20, 0.22, 0.24, 1.00}  // Unfocused tab (TabUnfocused)
    colors[im.Col.Tab_Dimmed_Selected]   = {0.24, 0.34, 0.44, 1.00}  // Active but unfocused tab (TabUnfocusedActive)
    colors[im.Col.Docking_Preview]       = {0.24, 0.34, 0.44, 0.70}  // Docking preview
    colors[im.Col.Docking_Empty_Bg]      = {0.14, 0.14, 0.16, 1.00}  // Empty docking background
    colors[im.Col.Plot_Lines]            = {0.46, 0.56, 0.66, 1.00}  // Plot lines
    colors[im.Col.Plot_Lines_Hovered]    = {0.46, 0.56, 0.66, 1.00}  // Hover effect for plot lines
    colors[im.Col.Plot_Histogram]        = {0.36, 0.46, 0.56, 1.00}  // Histogram color
    colors[im.Col.Plot_Histogram_Hovered]= {0.40, 0.50, 0.60, 1.00}  // Hover effect for histogram
    colors[im.Col.Table_Header_Bg]       = {0.20, 0.22, 0.24, 1.00}  // Table header background
    colors[im.Col.Table_Border_Strong]   = {0.28, 0.29, 0.30, 1.00}  // Strong border for tables
    colors[im.Col.Table_Border_Light]    = {0.24, 0.25, 0.26, 1.00}  // Light border for tables
    colors[im.Col.Table_Row_Bg]          = {0.20, 0.22, 0.24, 1.00}  // Table row background
    colors[im.Col.Table_Row_Bg_Alt]      = {0.22, 0.24, 0.26, 1.00}  // Alternate row background
    colors[im.Col.Text_Selected_Bg]      = {0.24, 0.34, 0.44, 0.35}  // Selected text background
    colors[im.Col.Drag_Drop_Target]      = {0.46, 0.56, 0.66, 0.90}  // Drag and drop target
    colors[im.Col.Nav_Cursor]            = {0.46, 0.56, 0.66, 1.00}  // Navigation highlight (NavHighlight)
    colors[im.Col.Nav_Windowing_Highlight]= {1.00, 1.00, 1.00, 0.70}  // Windowing highlight
    colors[im.Col.Nav_Windowing_Dim_Bg]  = {0.80, 0.80, 0.80, 0.20}  // Dim background for windowing
    colors[im.Col.Modal_Window_Dim_Bg]   = {0.80, 0.80, 0.80, 0.35}  // Dim background for modal windows

    // Style adjustments
    style.window_rounding    = 8.0  // Softer rounded corners for windows
    style.frame_rounding     = 4.0  // Rounded corners for frames
    style.scrollbar_rounding = 6.0  // Rounded corners for scrollbars
    style.grab_rounding      = 4.0  // Rounded corners for grab elements
    style.child_rounding     = 4.0  // Rounded corners for child windows

    style.window_title_align = {0.50, 0.50}  // Centered window title
    style.window_padding     = {10.0, 10.0}  // Comfortable padding
    style.frame_padding      = {6.0, 4.0}    // Frame padding
    style.item_spacing       = {8.0, 8.0}    // Item spacing
    style.item_inner_spacing = {8.0, 6.0}    // Inner item spacing
    style.indent_spacing     = 22.0          // Indentation spacing

    style.scrollbar_size = 16.0  // Scrollbar size
    style.grab_min_size  = 10.0  // Minimum grab size

    style.anti_aliased_lines = true  // Enable anti-aliased lines
    style.anti_aliased_fill  = true  // Enable anti-aliased fill
}
// odinfmt: enable
