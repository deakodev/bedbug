package core

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:strings"

allocator_tracking_setup :: proc(tracking: ^mem.Tracking_Allocator) -> runtime.Allocator {

	mem.tracking_allocator_init(tracking, context.allocator)
	return mem.tracking_allocator(tracking)
}

allocator_tracking_cleanup :: proc(tracking: ^mem.Tracking_Allocator) {

	free_all(context.temp_allocator)

	if len(tracking.allocation_map) > 0 {
		log.errorf("=== %v allocations not freed: ===", len(tracking.allocation_map))
		for _, entry in tracking.allocation_map {
			log.warnf("%v bytes @ %v", entry.size, entry.location)
		}
	}

	if len(tracking.bad_free_array) > 0 {
		log.errorf("=== %v incorrect frees: ===", len(tracking.bad_free_array))
		for entry in tracking.bad_free_array {
			log.warnf("%p @ %v", entry.memory, entry.location)
		}
	}

	mem.tracking_allocator_destroy(tracking)
}

allocator_tracking_check :: proc(tracking: ^mem.Tracking_Allocator) {

	if len(tracking.bad_free_array) > 0 {
		for b in tracking.bad_free_array {
			log.warnf("Bad free at: %v", b.location)
		}
	}
}

bytes_formated_string :: proc(bytes: i64) -> string {

	backing: [1024]byte
	buf := strings.builder_from_bytes(backing[:])

	value := f64(bytes)
	unit := "bytes"

	if bytes >= mem.Gigabyte {
		value = value / f64(mem.Gigabyte)
		unit = "GB"
	} else if bytes >= mem.Megabyte {
		value = value / f64(mem.Megabyte)
		unit = "MB"
	} else if bytes >= mem.Kilobyte {
		value = value / f64(mem.Kilobyte)
		unit = "KB"
	}

	fmt.sbprintf(&buf, "%.2f %s", value, unit)

	return strings.to_string(buf)
}
