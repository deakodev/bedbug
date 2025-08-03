package vulkan_backend

import "base:intrinsics"
import "base:runtime"
import bb "bedbug:core"
import "bedbug:vendor/vma"
import "core:log"
import "core:strings"
import vk "vendor:vulkan"

AllocatedBuffer :: struct {
	handle:     vk.Buffer,
	alloc_info: vma.Allocation_Info,
	allocation: vma.Allocation,
	allocator:  vma.Allocator,
}

allocated_buffer_create :: proc(
	self: ^Vulkan,
	alloc_size: vk.DeviceSize,
	buffer_usage: vk.BufferUsageFlags,
	memory_usage: vma.Memory_Usage,
) -> (
	buffer: AllocatedBuffer,
) {

	buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size  = alloc_size,
		usage = buffer_usage,
	}

	vma_alloc_info := vma.Allocation_Create_Info {
		usage = memory_usage,
		flags = {.Mapped},
	}

	buffer.allocator = self.device.vma_allocator

	vk_ok(
		vma.create_buffer(
			buffer.allocator,
			buffer_info,
			vma_alloc_info,
			&buffer.handle,
			&buffer.allocation,
			&buffer.alloc_info,
		),
	)

	return buffer
}

allocated_buffer_cleanup :: proc(self: AllocatedBuffer) {

	vma.destroy_buffer(self.allocator, self.handle, self.allocation)
}

device_immediate_command :: proc(
	device: ^Device,
	info: $T,
	record: proc(device: ^Device, command: vk.CommandBuffer, info: T),
) {

	vk_ok(vk.ResetFences(device.handle, 1, &device.immediate.fence))
	vk_ok(vk.ResetCommandBuffer(device.immediate.command, {}))

	command := device.immediate.command

	command_begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	vk_ok(vk.BeginCommandBuffer(command, &command_begin_info))

	record(device, command, info)

	vk_ok(vk.EndCommandBuffer(command))

	command_submit_info := vk.CommandBufferSubmitInfo {
		sType         = .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer = command,
	}

	submit_info := vk.SubmitInfo2 {
		sType                  = .SUBMIT_INFO_2,
		commandBufferInfoCount = 1,
		pCommandBufferInfos    = &command_submit_info,
	}

	vk_ok(vk.QueueSubmit2(device.graphics_queue, 1, &submit_info, device.immediate.fence))

	vk_ok(vk.WaitForFences(device.handle, 1, &device.immediate.fence, true, 9999999999))
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

vk_ok :: #force_inline proc(result: vk.Result, loc := #caller_location) {

	if intrinsics.expect(result, vk.Result.SUCCESS) == .SUCCESS {return}
	log.errorf("failed vulkan proc: %v", result)
	runtime.print_caller_location(loc)
}

MeshVertex :: struct {
	position: bb.vec3,
	uv_x:     f32,
	normal:   bb.vec3,
	uv_y:     f32,
	color:    bb.vec4,
}

MeshBuffers :: struct {
	index_buffer:  AllocatedBuffer,
	vertex_buffer: AllocatedBuffer,
}

DrawPushConstants :: struct {
	world_matrix: bb.mat4,
}

// todo: these calls should really occur on a thread seperate from the render thread
mesh_buffers_create :: proc(self: ^Vulkan, indices: []u32, vertices: []MeshVertex) -> (buffers: MeshBuffers) {

	vertex_buffer_size := vk.DeviceSize(len(vertices) * size_of(MeshVertex))
	index_buffer_size := vk.DeviceSize(len(indices) * size_of(u32))

	buffers.vertex_buffer = allocated_buffer_create(
		self,
		vertex_buffer_size,
		{.STORAGE_BUFFER, .TRANSFER_DST},
		.Gpu_Only,
	)

	// device_address_info := vk.BufferDeviceAddressInfo {
	// 	sType  = .BUFFER_DEVICE_ADDRESS_INFO,
	// 	buffer = buffers.vertex_buffer.handle,
	// }
	// buffers.vertex_buffer_address = vk.GetBufferDeviceAddress(self.device.handle, &device_address_info)

	buffers.index_buffer = allocated_buffer_create(self, index_buffer_size, {.INDEX_BUFFER, .TRANSFER_DST}, .Gpu_Only)

	staging_buffer := allocated_buffer_create(self, vertex_buffer_size + index_buffer_size, {.TRANSFER_SRC}, .Cpu_Only)
	defer allocated_buffer_cleanup(staging_buffer)

	data := staging_buffer.alloc_info.mapped_data

	intrinsics.mem_copy(data, raw_data(vertices), vertex_buffer_size)
	intrinsics.mem_copy(rawptr(uintptr(data) + uintptr(vertex_buffer_size)), raw_data(indices), index_buffer_size)

	RecordInfo :: struct {
		staging_buffer_handle: vk.Buffer,
		vertex_buffer_handle:  vk.Buffer,
		index_buffer_handle:   vk.Buffer,
		vertex_buffer_size:    vk.DeviceSize,
		index_buffer_size:     vk.DeviceSize,
	}

	record_info := RecordInfo {
		staging_buffer_handle = staging_buffer.handle,
		vertex_buffer_handle  = buffers.vertex_buffer.handle,
		index_buffer_handle   = buffers.index_buffer.handle,
		vertex_buffer_size    = vertex_buffer_size,
		index_buffer_size     = index_buffer_size,
	}

	device_immediate_command(
		&self.device,
		record_info,
		proc(device: ^Device, command: vk.CommandBuffer, info: RecordInfo) {

			vertex_copy := vk.BufferCopy {
				srcOffset = 0,
				dstOffset = 0,
				size      = info.vertex_buffer_size,
			}
			vk.CmdCopyBuffer(command, info.staging_buffer_handle, info.vertex_buffer_handle, 1, &vertex_copy)

			index_copy := vk.BufferCopy {
				srcOffset = info.vertex_buffer_size,
				dstOffset = 0,
				size      = info.index_buffer_size,
			}
			vk.CmdCopyBuffer(command, info.staging_buffer_handle, info.index_buffer_handle, 1, &index_copy)
		},
	)

	return buffers
}
