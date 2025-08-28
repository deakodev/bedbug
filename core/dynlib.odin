package core

import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:os"
import "core:os/os2"
import "core:time"

DynlibSymbols :: struct {
	handle:  dynlib.Library,
	setup:   proc(bedbug: rawptr) -> (self: rawptr, type: typeid),
	cleanup: proc(bedbug: rawptr, self: rawptr) -> (ok: bool),
	update:  proc(bedbug: rawptr, self: rawptr) -> (ok: bool),
	draw:    proc(bedbug: rawptr, self: rawptr) -> (ok: bool),
}

Dynlib :: struct {
	name:       string,
	versions:   [dynamic]DynlibSymbols,
	updated_at: os.File_Time,
}

dynlib_load :: proc(lib: ^Dynlib) -> ^DynlibSymbols {

	log.assert(lib != nil, "failed to load. Dynlib is nil")

	append(&lib.versions, DynlibSymbols{})
	version_index := len(lib.versions) - 1
	current_version := dynlib_get_version(lib, version_index)

	src_path := fmt.tprintf("%s/%s.%s", BUILD_DIR, lib.name, dynlib.LIBRARY_FILE_EXTENSION)
	dst_path := fmt.tprintf("%s/%s_%d.%s", BUILD_DIR, lib.name, version_index, dynlib.LIBRARY_FILE_EXTENSION)

	if !dynlib_copy(src_path, dst_path) {
		log.panicf("failed to copy {0} to {1}", src_path, dst_path)
	}

	lib.updated_at = dynlib_updated_at(src_path)

	lib_prefix := fmt.tprintf("%s_", lib.name)
	_, ok := dynlib.initialize_symbols(current_version, dst_path, lib_prefix, "handle")
	if !ok {
		log.panicf("failed initializing symbols: {0}", dynlib.last_error())
	}

	return current_version
}

dynlib_unload :: proc(lib: ^Dynlib) -> (ok: bool) {

	log.assert(lib != nil, "failed to unload. Dynlib is nil.")

	for &version, index in lib.versions {
		if lib != nil {
			if !dynlib.unload_library(version.handle) {
				log.errorf("failed unloading lib: {0}", dynlib.last_error())
				return false
			}
		}

		version_path := fmt.tprintf("%s/%s_%d.%s", BUILD_DIR, lib.name, index, dynlib.LIBRARY_FILE_EXTENSION)
		if os.remove(version_path) != nil {
			log.errorf("failed to remove {0}", version_path)
			return false
		}
	}

	delete(lib.versions)
	delete(lib.name)

	return true
}

dynlib_copy :: proc(src_path, dst_path: string) -> bool {

	max_attempts := 10
	for _ in 0 ..< max_attempts {
		if os2.copy_file(dst_path, src_path) == nil {
			return true
		}
		time.sleep(100 * time.Millisecond)
	}

	return false
}

dynlib_should_reload :: proc(lib: ^Dynlib) -> bool {

	src_path := fmt.tprintf("%s/%s.%s", BUILD_DIR, lib.name, dynlib.LIBRARY_FILE_EXTENSION)
	updated_at_time := dynlib_updated_at(src_path)
	return updated_at_time != lib.updated_at && updated_at_time != os.File_Time{}
}

dynlib_updated_at :: proc(path: string) -> os.File_Time {

	time, err := os.last_write_time_by_name(path)
	if err != os.ERROR_NONE {
		log.errorf("failed getting last write time of {0}, error code: {1}", path, err)
		return os.File_Time{}
	}

	return time
}

dynlib_get_version :: proc(lib: ^Dynlib, index: int = -1) -> ^DynlibSymbols {

	i := index > 0 ? index : len(lib.versions) - 1
	return &lib.versions[i]
}
