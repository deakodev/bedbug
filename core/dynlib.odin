package core

import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:os"
import "core:os/os2"
import "core:time"


when ODIN_OS == .Windows {
	DYNLIB_EXT :: ".dll"
	DYNLIB_OS :: "win32"
} else when ODIN_OS == .Darwin {
	DYNLIB_EXT :: ".dylib"
	DYNLIB_OS :: "macos"
} else {
	DYNLIB_EXT :: ".so"
	DYNLIB_OS :: "linux"
}

when ODIN_DEBUG {
	DYNLIB_BUILD :: "debug"
} else {
	DYNLIB_BUILD :: "release"
}


Futon_Symbols :: struct {
	handle:  dynlib.Library,
	setup:   proc(),
	cleanup: proc(),
	update:  proc(),
}


Game_Symbols :: struct {
	handle:          dynlib.Library,
	setup:           proc(),
	cleanup:         proc(),
	update:          proc(),
	memory:          proc() -> rawptr,
	memory_size:     proc() -> int,
	hot_reloaded:    proc(mem: rawptr),
}


Dynlib :: struct(T: typeid) {
	name: string,
	generations: [dynamic]T,
	updated_at:  os.File_Time,
}


dynlib_load :: proc($T: typeid) -> ^Dynlib(T) {

	lib := new(Dynlib(T))
	lib.generations = make([dynamic]T)
	append(&lib.generations, T{})
	generation_index := len(lib.generations) - 1
	generation := &lib.generations[generation_index]

	lib.name = dynlib_name(T)
	directory := fmt.tprintf("build\\%s\\%s", DYNLIB_OS, DYNLIB_BUILD)

	src_path := fmt.tprintf("%s\\%s%s", directory, lib.name, DYNLIB_EXT)
	dst_path := fmt.tprintf("%s/%s_%d%s", directory, lib.name, generation_index, DYNLIB_EXT)

	if !dynlib_copy(src_path, dst_path) {
		log.panicf("failed to copy {0} to {1}", src_path, dst_path)
	}

	lib.updated_at = dynlib_updated_at(src_path)

	symbol_prefix := fmt.tprintf("%s_", lib.name)
	_, ok := dynlib.initialize_symbols(generation, dst_path, symbol_prefix, "handle")
	if !ok {
		log.panicf("failed initializing symbols: {0}", dynlib.last_error())
	}

	return lib
}


dynlib_unload :: proc(lib: ^Dynlib($T)) {

	for &generation, index in lib.generations {
		if lib != nil {
			if !dynlib.unload_library(generation.handle) {
				log.errorf("failed unloading lib: {0}", dynlib.last_error())
				return
			}
		}

		directory := fmt.tprintf("build\\%s\\%s", DYNLIB_OS, DYNLIB_BUILD)
		generation_path := fmt.tprintf("%s/%s_%d%s", directory, lib.name, index, DYNLIB_EXT)
		if os.remove(generation_path) != nil {
			log.errorf("failed to remove {0}", generation_path)
			return
		}

	}

	free(lib)
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


dynlib_should_reload :: proc(lib: ^Dynlib($T)) -> bool {

	directory := fmt.tprintf("build\\%s\\%s", DYNLIB_OS, DYNLIB_BUILD)
	src_path := fmt.tprintf("%s\\%s%s", directory, lib.name, DYNLIB_EXT)
	updated_at_time := dynlib_updated_at(src_path)
	return updated_at_time != lib.updated_at && updated_at_time != os.File_Time{}
}


dynlib_updated_at :: proc(path: string) -> os.File_Time {

	time, err := os.last_write_time_by_name(path)
	if err != os.ERROR_NONE {
		log.errorf("Failed getting last write time of {0}, error code: {1}", path, err)
		return os.File_Time{}
	}

	return time
}


dynlib_generation :: proc(lib: ^Dynlib($T), gen_index: int = -1) -> T {
	gen_index := gen_index >= 0 ? gen_index : len(lib.generations) - 1
	return lib.generations[gen_index]
}


dynlib_name :: proc($T: typeid) -> string {
	switch typeid_of(T) {
	case typeid_of(Futon_Symbols): return "futon"
	case typeid_of(Game_Symbols): return "game"
	}

	return "unknown"
}
