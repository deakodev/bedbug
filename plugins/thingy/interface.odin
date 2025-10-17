package thingy

import bc "bedbug:core"

@(private = "file")
g_thingy_config: bc.PluginConfig = {
	package_dir = "plugins/thingy",
	build_flags = {"-debug"},
}

Interface :: struct {
	using state: ^Hello,
	hello:       proc(state: ^Hello) -> ^Hello,
}

@(export)
bedbug_interface :: proc(interface: ^Interface) {

	state := new(Hello)
	state.value = "Hello from Thingy Plugin!"
	interface^ = Interface {
		state = state,
		hello = hello,
	}
}

config :: proc() -> ^bc.PluginConfig {
	return &g_thingy_config
}
