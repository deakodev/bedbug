package core

import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os/os2"
import "core:path/filepath"
import "core:reflect"
import "core:slice"
import "core:time"

PLUGIN_BUILD_DIR :: BUILD_DIR + "/plugins"

Interface :: distinct rawptr

Plugin :: struct {
	name:       string,
	lib:        dynlib.Library,
	interface:  Interface,
	updated_at: time.Time,
	version:    int,
}

PluginConfig :: struct {
	interface_type: typeid,
	package_dir:    string,
	build_flags:    []string,
}


@(private = "file")
g_plugin_registry: map[typeid]^Plugin

plugin_interface :: proc($T: typeid, config: ^PluginConfig) -> (interface: ^T, ok: bool) {

	INTERFACE_T :: T

	plugin, exists := g_plugin_registry[INTERFACE_T]
	if !exists {
		plugin, ok = plugin_create(INTERFACE_T, config)
		if !ok {
			return nil, false
		}

	}

	log.assertf(plugin.interface != nil, "failed to find plugin interface.")
	return cast(^INTERFACE_T)plugin.interface, true
}

plugin_create :: proc($T: typeid, config: ^PluginConfig) -> (plugin: ^Plugin, ok: bool) {

	INTERFACE_T :: T

	plugin_build(config.package_dir, config.build_flags) or_return

	plugin = new(Plugin)
	plugin^ = Plugin {
		name       = filepath.base(config.package_dir),
		lib        = nil,
		interface  = nil,
		updated_at = time.Time{},
		version    = 0,
	}

	plugin_load(INTERFACE_T, plugin) or_return

	g_plugin_registry[INTERFACE_T] = plugin

	return plugin, true
}

plugin_register :: proc(interface: ^$T) {

	log.ensuref(interface != nil, "failed to register plugin. interface is nil.")

	INTERFACE_T :: T
	plugin := new(Plugin)


	// g_plugin_registry[INTERFACE_T] =
	// if plugin.interface != nil {
	// 	plugin_unregister(T)
	// }

	plugin.interface = cast(Interface)(interface)
}

plugin_unregister :: proc($T: typeid) {

	plugin := g_plugin_registry[T]
	if plugin.interface != nil {
		free(plugin.interface)
	}
}

plugin_build :: proc(package_dir: string, flags: []string) -> (ok: bool) {

	os2.make_directory_all(PLUGIN_BUILD_DIR)

	build_mode_flag := "-build-mode:dll"
	collection_flag := "-collection:bedbug=."
	out_flag := fmt.tprintf("-out:%s/%s.dll", PLUGIN_BUILD_DIR, filepath.base(package_dir))

	defaults := []string{"odin", "build", package_dir, out_flag, collection_flag, build_mode_flag}
	command: [dynamic]string
	append(&command, ..defaults[:])
	append(&command, ..flags[:])

	fmt.printfln("%#v", command)

	process_desc: os2.Process_Desc
	process_desc.command = command[:]
	process_state, _, err_out, err := os2.process_exec(process_desc, context.allocator)

	if err != nil {
		log.error("Failed to execute odin build command: %v", err)
		return false
	}

	if process_state.exit_code != 0 {
		log.error("Failed to compile plugin dll(%v): %v", package_dir, string(err_out))
		return false
	}

	return true
}

plugin_load :: proc($INTERFACE_T: typeid, plugin: ^Plugin) -> (ok: bool) {

	lib_path := fmt.tprintf("%s/%s.%s", PLUGIN_BUILD_DIR, plugin.name, dynlib.LIBRARY_FILE_EXTENSION)
	copy_path := fmt.tprintf(
		"%s/%s_%d.%s",
		PLUGIN_BUILD_DIR,
		plugin.name,
		plugin.version,
		dynlib.LIBRARY_FILE_EXTENSION,
	)

	err := os2.copy_file(copy_path, lib_path)
	if err != nil {
		log.error("failed to copy and load plugin %v.dll: %v", plugin.name, err)
		return false
	}

	plugin.lib, ok = dynlib.load_library(copy_path, false)
	if !ok {
		log.error("failed to load plugin %v.dll", plugin.name)
		return false
	}

	InterfaceProc :: proc(interface: ^INTERFACE_T)
	plugin_interface_pfn := cast(InterfaceProc)dynlib.symbol_address(plugin.lib, "bedbug_interface")

	if plugin_interface_pfn == nil {
		log.error("failed to find plugin interface proc symbol in %v.dll", plugin.name)
		// dynlib.free_library(lib)
		return false
	}

	interface := new(INTERFACE_T)
	plugin_interface_pfn(interface)
	plugin.interface = cast(Interface)(interface)

	plugin.updated_at, err = os2.modification_time_by_path(copy_path)
	if err != nil {
		log.error("failed to get plugin modification time: %v", err)
		// dynlib.free_library(lib)
		return false
	}

	return true
}

plugin_reload :: proc($T: typeid, config: PluginConfig) -> (interface: ^T, ok: bool) {

	INTERFACE_T :: T

	plugin, exists := g_plugin_registry[INTERFACE_T]
	if !exists {
		return plugin_load(INTERFACE_T, config)
	}

	// _plugin_load(INTERFACE_T, config) or_return

	plugin_build(plugin.package_dir, build_flags) or_return

	plugin_update()

	name := filepath.base(package_dir)
	version := 0

	lib_path := fmt.tprintf("%s/%s.%s", PLUGIN_BUILD_DIR, name, dynlib.LIBRARY_FILE_EXTENSION)

	copy_path := fmt.tprintf("%s/%s_%d.%s", PLUGIN_BUILD_DIR, name, version, dynlib.LIBRARY_FILE_EXTENSION)

	err := os2.copy_file(copy_path, lib_path)
	if err != nil {
		log.error("failed to copy and load plugin %v.dll: %v", name, err)
		return false
	}

	plugin_lib: dynlib.Library
	plugin_lib, ok = dynlib.load_library(copy_path, false)
	if !ok {
		log.error("failed to load plugin %v.dll", name)
		return false
	}

	InterfaceProc :: proc(interface: ^INTERFACE_T)
	plugin_interface_pfn := cast(InterfaceProc)(dynlib.symbol_address(plugin_lib, "bedbug_interface"))

	if plugin_interface_pfn == nil {
		log.error("failed to find plugin interface proc symbol in %v.dll", name)
		// dynlib.free_library(lib)
		return false
	}

	plugin_interface := new(INTERFACE_T)
	plugin_interface_pfn(plugin_interface)
	interface := cast(Interface)(plugin_interface)

	updated_at: time.Time
	updated_at, err = os2.modification_time_by_path(copy_path)
	if err != nil {
		log.error("failed to get plugin modification time: %v", err)
		// dynlib.free_library(lib)
		return false
	}

	plugin := Plugin {
		lib        = plugin_lib,
		interface  = interface,
		path       = lib_path,
		updated_at = updated_at,
		version    = version,
	}

	g_plugin_registry[INTERFACE_T] = plugin

	fmt.println("Loaded plugin:", name, "version:", version)
	return true
}
