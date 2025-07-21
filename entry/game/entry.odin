package entry

import "bedbug:bedbug"
import "core:log"

main :: proc() {
	context.user_ptr = new(bedbug.Bedbug)
	context.logger = bedbug.logger_setup("bedbug")
	context.allocator = bedbug.allocator_setup()

	bedbug.setup()

	game_lib := bedbug.dynlib_load(bedbug.Game_Symbols)
	game := bedbug.dynlib_generation(game_lib)
	game.setup()

	for bedbug.should_run() {
		bedbug.update()
		game.update()

		bedbug.allocator_check()
	}

	game.cleanup()
	bedbug.dynlib_unload(game_lib)
	delete(game_lib.generations)

	bedbug.cleanup()
}
