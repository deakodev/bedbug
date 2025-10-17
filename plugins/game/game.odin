package game

import br "bedbug:bedbug"
import bc "bedbug:core"
import "core:log"

Game :: struct {
	scene: br.Scene,
}

@(export)
game_setup :: proc(bedbug: rawptr) -> (self: rawptr, type: typeid) {

	log.info("setting up game...")

	self = new(Game)
	game := (^Game)(self)
	entity := br.entity_create(&game.scene)

	return self, type_of(self)
}

@(export)
game_cleanup :: proc(bedbug: rawptr, self: rawptr) {
	log.info("cleaning up game...")
	free(self)
}

@(export)
game_update :: proc(bedbug: rawptr, self: rawptr) {
	game := (^Game)(self)

}

@(export)
game_draw :: proc(bedbug: rawptr, self: rawptr) {

}
