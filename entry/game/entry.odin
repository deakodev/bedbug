package entry

import "bedbug:bedbug"
import "core:log"

LayerTag :: enum {
	GAME,
}

main :: proc() {

	when ODIN_DEBUG {
		context.logger = bedbug.logger_setup()
		context.allocator = bedbug.allocator_setup()
		defer bedbug.allocator_cleanup()
	}

	bedbug_ptr := new(bedbug.Bedbug)
	context.user_ptr = bedbug_ptr

	layers: [LayerTag]bedbug.Layer
	plugin := bedbug.Plugin(LayerTag) {
		tag    = LayerTag,
		layers = layers,
	}

	bedbug.setup(bedbug_ptr, &plugin)

	bedbug.run(bedbug_ptr, &plugin)

	bedbug.cleanup(bedbug_ptr, &plugin)
	free(bedbug_ptr)
}
