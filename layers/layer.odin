package layer

import "core:mem"
import vmem "core:mem/virtual"

ArenaAllocator :: struct {
	arena:     vmem.Arena,
	allocator: mem.Allocator,
}

Memory :: struct {
	persistent: ArenaAllocator,
	ephemeral:  ArenaAllocator,
}

Layer :: struct($T: typeid) {
	memory: Memory,
	ptr:    ^T,
}

// LAYERS :: [2]Layer{Layer(PlatformLayer), Layer(RendererLayer)}

setup :: proc() -> (ok: bool) {

	// for layer in LAYERS {
	// 	persistent := &layer.memory.persistent
	// 	err := vmem.arena_init_static(&persistent.arena)
	// 	// if err {return false}
	// 	ephemeral := &layer.memory.ephemeral
	// 	err = vmem.arena_init_growing(&ephemeral.arena)
	// 	// if err {return false}
	// }

	return true
}
