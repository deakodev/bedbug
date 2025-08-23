package entry

import "bedbug:bedbug"
import "core:log"

Layers :: enum u8 {
	GAME,
	EDITOR,
}

main :: proc() {

	when ODIN_DEBUG {
		context.logger = bedbug.logger_setup()
		context.allocator = bedbug.allocator_setup()
		defer bedbug.allocator_cleanup()
	}

	bedbug_ptr := new(bedbug.Bedbug)
	context.user_ptr = bedbug_ptr

	libs: [Layers]bedbug.Dynlib
	layers: [Layers]bedbug.Layer
	plugin := bedbug.Plugin(Layers){libs, layers}
	options := bedbug.Options {
		// fullscreen = true,
	}
	bedbug.setup(bedbug_ptr, &plugin, &options)

	bedbug.run(bedbug_ptr, &plugin)

	bedbug.cleanup(bedbug_ptr, &plugin)
}
