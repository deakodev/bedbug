package bedbug_runtime

import "core:encoding/entity"
import "core:log"

PROJECT :: Modules.VIEWER
Modules :: enum u8 {
	VIEWER,
	EDITOR,
}

import ecs "bedbug:vendor/ode_ecs"

my_ecs: ecs.Database

main :: proc() {

	when ODIN_DEBUG {
		context.logger = logger_setup()
		context.allocator = allocator_setup()
		defer allocator_cleanup()
	}

	bedbug_ptr := new(Bedbug)
	context.user_ptr = bedbug_ptr

	ecs.init(&my_ecs, entities_cap = 10, allocator = context.allocator)

	libs: [Modules]Dynlib
	modules: [Modules]Module
	plugin := Plugin(Modules){libs, modules}
	options := Options {
		// fullscreen = true,
	}

	setup(bedbug_ptr, &plugin, &options)

	run(bedbug_ptr, &plugin)

	cleanup(bedbug_ptr, &plugin)
}
