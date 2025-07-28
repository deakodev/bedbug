package core

import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:os"
import "core:os/os2"
import "core:time"

LayerSymbols :: struct {
	handle:  dynlib.Library,
	setup:   proc(bedbug: rawptr, self: rawptr),
	cleanup: proc(bedbug: rawptr, self: rawptr),
	update:  proc(bedbug: rawptr, self: rawptr),
	self:    rawptr,
}

Layer :: struct {
	name:       string,
	versions:   [dynamic]LayerSymbols,
	updated_at: os.File_Time,
}

layer_load :: proc(name: string, layer: ^Layer) -> ^LayerSymbols {

	layer.name = name
	layer.versions = make([dynamic]LayerSymbols)
	append(&layer.versions, LayerSymbols{})
	version_index := len(layer.versions) - 1
	current_version := layer_get_version(layer, version_index)

	src_path := fmt.tprintf("%s/%s.%s", BUILD_DIR, layer.name, dynlib.LIBRARY_FILE_EXTENSION)
	dst_path := fmt.tprintf("%s/%s_%d.%s", BUILD_DIR, layer.name, version_index, dynlib.LIBRARY_FILE_EXTENSION)

	if !layer_copy(src_path, dst_path) {
		log.panicf("failed to copy {0} to {1}", src_path, dst_path)
	}

	layer.updated_at = layer_updated_at(src_path)

	layer_prefix := fmt.tprintf("%s_", layer.name)
	_, ok := dynlib.initialize_symbols(current_version, dst_path, layer_prefix, "handle")
	if !ok {
		log.panicf("failed initializing symbols: {0}", dynlib.last_error())
	}

	return current_version
}

layer_unload :: proc(layer: ^Layer) {

	for &version, index in layer.versions {
		if layer != nil {
			if !dynlib.unload_library(version.handle) {
				log.errorf("failed unloading layer: {0}", dynlib.last_error())
				return
			}
		}

		version_path := fmt.tprintf("%s/%s_%d.%s", BUILD_DIR, layer.name, index, dynlib.LIBRARY_FILE_EXTENSION)
		if os.remove(version_path) != nil {
			log.errorf("failed to remove {0}", version_path)
			return
		}
	}
}

layer_copy :: proc(src_path, dst_path: string) -> bool {

	max_attempts := 10
	for _ in 0 ..< max_attempts {
		if os2.copy_file(dst_path, src_path) == nil {
			return true
		}
		time.sleep(100 * time.Millisecond)
	}

	return false
}

layer_should_reload :: proc(layer: ^Layer) -> bool {

	src_path := fmt.tprintf("%s/%s.%s", BUILD_DIR, layer.name, dynlib.LIBRARY_FILE_EXTENSION)
	updated_at_time := layer_updated_at(src_path)
	return updated_at_time != layer.updated_at && updated_at_time != os.File_Time{}
}

layer_updated_at :: proc(path: string) -> os.File_Time {

	time, err := os.last_write_time_by_name(path)
	if err != os.ERROR_NONE {
		log.errorf("failed getting last write time of {0}, error code: {1}", path, err)
		return os.File_Time{}
	}

	return time
}

layer_get_version :: proc(layer: ^Layer, index: int = -1) -> ^LayerSymbols {

	i := index > 0 ? index : len(layer.versions) - 1
	return &layer.versions[i]
}
