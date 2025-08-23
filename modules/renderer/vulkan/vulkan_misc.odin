package vulkan_backend

import "base:intrinsics"
import "base:runtime"
import bb "bedbug:core"
import "bedbug:vendor/vma"
import "core:log"
import "core:strings"
import vk "vendor:vulkan"

// todo: move
DrawPushConstants :: struct {
	world_matrix: bb.mat4,
}

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

	vk_ok(vk.QueueSubmit2(device.graphics_queue.handle, 1, &submit_info, device.immediate.fence))

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

vk_ok :: #force_inline proc(result: vk.Result, loc := #caller_location) -> bool {

	if intrinsics.expect(result, vk.Result.SUCCESS) == .SUCCESS {return true}
	log.errorf("failed vulkan proc: %v", result)
	runtime.print_caller_location(loc)
	return false
}
