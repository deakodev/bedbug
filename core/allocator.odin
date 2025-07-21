package core

import "base:runtime"
import "core:log"
import "core:mem"

@(private = "file")
g_tracking_allocator: mem.Tracking_Allocator

allocator_setup :: proc() -> runtime.Allocator {

	mem.tracking_allocator_init(&g_tracking_allocator, context.allocator)
	return mem.tracking_allocator(&g_tracking_allocator)
}


allocator_clear :: proc() {

	for _, value in g_tracking_allocator.allocation_map {
		log.warnf("%v: Leaked %v bytes\n", value.location, value.size)
	}

	mem.tracking_allocator_clear(&g_tracking_allocator)
}

allocator_cleanup :: proc() {

	free_all(context.temp_allocator)

	if len(g_tracking_allocator.allocation_map) > 0 {
		log.errorf("=== %v allocations not freed: ===", len(g_tracking_allocator.allocation_map))
		for _, entry in g_tracking_allocator.allocation_map {
			log.debugf("%v bytes @ %v", entry.size, entry.location)
		}
	}
	if len(g_tracking_allocator.bad_free_array) > 0 {
		log.errorf("=== %v incorrect frees: ===", len(g_tracking_allocator.bad_free_array))
		for entry in g_tracking_allocator.bad_free_array {
			log.debugf("%p @ %v", entry.memory, entry.location)
		}
	}

	mem.tracking_allocator_destroy(&g_tracking_allocator)
}

allocator_check :: proc() {

	if len(g_tracking_allocator.bad_free_array) > 0 {
		for b in g_tracking_allocator.bad_free_array {
			log.errorf("Bad free at: %v", b.location)
		}
	}
}
