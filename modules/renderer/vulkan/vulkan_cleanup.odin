package vulkan_backend

import "bedbug:vendor/vma"
import "core:log"
import "core:mem"
import vk "vendor:vulkan"

Resource :: union {
	proc "c" (), // cleanup procs
	vk.Pipeline,
	vk.PipelineLayout,
	vk.DescriptorPool,
	vk.DescriptorSetLayout,
	vk.ImageView,
	vk.Sampler,
	vk.CommandPool,
	vk.Fence,
	vk.Semaphore,
	vk.Buffer,
	vk.DeviceMemory,
	vma.Allocator,
	AllocatedImage,
}

ResourceStack :: struct {
	device:    vk.Device,
	allocator: mem.Allocator,
	resources: [dynamic]Resource, // lifo stack
}

resource_stack_setup :: proc(self: ^ResourceStack, device: vk.Device, allocator := context.allocator) {

	log.assert(self != nil, "invalid cleanup queue pointer.")
	log.assert(device != nil, "invalid device handle.")
	self.device = device
	self.allocator = allocator
	self.resources = make([dynamic]Resource, self.allocator)
}

resource_stack_cleanup :: proc(self: ^ResourceStack) {

	log.assert(self != nil, "invalid cleanup queue pointer.")
	context.allocator = self.allocator
	resource_stack_flush(self)
	delete(self.resources)
}

resource_stack_push :: proc(self: ^ResourceStack, resources: ..Resource) {

	for resource in resources {
		append(&self.resources, resource)
	}
}

resource_stack_flush :: proc(self: ^ResourceStack) {

	log.assert(self != nil, "invalid cleanup queue pointer.")

	if len(self.resources) == 0 {
		return
	}

	#reverse for union_resource in self.resources {
		switch resource in union_resource {
		case proc "c" ():
			resource() // call cleanup proc
		case vk.Pipeline:
			vk.DestroyPipeline(self.device, resource, nil)
		case vk.PipelineLayout:
			vk.DestroyPipelineLayout(self.device, resource, nil)
		case vk.DescriptorPool:
			vk.DestroyDescriptorPool(self.device, resource, nil)
		case vk.DescriptorSetLayout:
			vk.DestroyDescriptorSetLayout(self.device, resource, nil)
		case vk.ImageView:
			vk.DestroyImageView(self.device, resource, nil)
		case vk.Sampler:
			vk.DestroySampler(self.device, resource, nil)
		case vk.CommandPool:
			vk.DestroyCommandPool(self.device, resource, nil)
		case vk.Fence:
			vk.DestroyFence(self.device, resource, nil)
		case vk.Semaphore:
			vk.DestroySemaphore(self.device, resource, nil)
		case vk.Buffer:
			vk.DestroyBuffer(self.device, resource, nil)
		case vk.DeviceMemory:
			vk.FreeMemory(self.device, resource, nil)
		case vma.Allocator:
			vma.destroy_allocator(resource)
		case AllocatedImage:
			allocated_image_cleanup(self.device, resource)
		}
	}

	clear(&self.resources)
}
