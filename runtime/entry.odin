package bedbug_runtime

import config "../modules"
import "core:log"

main :: proc() {

	bedbug := new(Bedbug)
	context.user_ptr = bedbug

	context.logger = logger_setup()

	when ODIN_DEBUG {
		context.allocator = allocator_tracking_setup(&bedbug.tracking_allocator)
		defer allocator_tracking_cleanup(&bedbug.tracking_allocator)
	}

	libs: [config.Modules]Dynlib
	modules: [config.Modules]Module
	plugin := Plugin(config.Modules){libs, modules, config.CLIENT}

	ok := setup(bedbug, &plugin, &config.OPTIONS)
	if !ok {
		log.panic("failed to initialize bedbug.")
	}

	ok = run(bedbug, &plugin)
	if !ok {
		log.panic("failed to run bedbug.")
	}

	ok = cleanup(bedbug, &plugin)
	if !ok {
		log.panic("failed to cleanup bedbug.")
	}
}
